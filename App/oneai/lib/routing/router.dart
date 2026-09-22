import 'dart:async';

import 'package:codebase_ai/data/repositories/demo/demo_post_repository.dart';
import 'package:codebase_ai/data/repositories/demo/demo_user_repository.dart';
import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/data/repositories/share_repository.dart';
import 'package:codebase_ai/domain/models/demo/demo_post_model.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_bloc.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_state.dart';
import 'package:codebase_ai/data/repositories/auth_repository.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/domain/use_cases/tag_usecase.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/features/auth/login_page.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/ui/animation/page_animation_manager.dart';
import 'package:codebase_ai/ui/features/demo/view_model/demo_user_bloc.dart';
import 'package:codebase_ai/ui/features/demo/widgets/demo_home_screen.dart';
import 'package:codebase_ai/ui/features/demo/widgets/demo_post_detail_screen.dart';
import 'package:codebase_ai/ui/features/demo/widgets/demo_user_screen.dart';
import 'package:codebase_ai/ui/features/home/screens/home_screen.dart';
import 'package:codebase_ai/ui/features/home/screens/record_audio_screen.dart';
import 'package:codebase_ai/ui/features/home/screens/upload_file_screen.dart';
import 'package:codebase_ai/ui/features/home/screens/youtube_video_screen.dart';
import 'package:codebase_ai/ui/features/home/view_model/home_bloc.dart';
import 'package:codebase_ai/ui/features/settings/view_model/settings_bloc.dart';
import 'package:codebase_ai/ui/features/transcription/screens/audio_processing_screen.dart';
import 'package:codebase_ai/ui/features/transcription/screens/transcription_summary_screen.dart';
import 'package:codebase_ai/ui/features/transcription/view_model/transcription_summary_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:codebase_ai/ui/features/settings/screens/settings_screen.dart';

/// Custom ChangeNotifier that listens to AuthBloc state changes
/// and notifies listeners when authentication status changes
class AuthStateNotifier extends ChangeNotifier {
  final AuthBloc _authBloc;
  late final StreamSubscription<AuthState> _subscription;

  AuthStateNotifier(this._authBloc) {
    _subscription = _authBloc.stream.listen((state) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Error page displayed when navigation fails or route not found
/// Shows a user-friendly error message with the path and a button to return home
Widget _errorPage(BuildContext context, GoRouterState state) => Scaffold(
  appBar: AppBar(title: Text(context.loc.pageNotFound)),
  body: Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, size: 64, color: context.colorScheme.error),
        gapH16,
        Text(
          context.loc.pageNotFoundMessage(state.uri.path),
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        gapH16,
        ElevatedButton(onPressed: () => context.go(Routes.root), child: Text(context.loc.goHome)),
      ],
    ),
  ),
);

/// Auth guard that redirects unauthenticated users to the login page
String? _authGuard(BuildContext context, GoRouterState state) {
  // Get auth repository to check authentication status
  final authRepository = context.read<AuthRepository>();
  final isAuthenticated = authRepository.isAuthenticated;
  final isLoginRoute = state.matchedLocation == Routes.login;

  // If user is not authenticated and not heading to login page,
  // redirect to login page
  if (!isAuthenticated && !isLoginRoute) {
    return Routes.login;
  }

  // If user is authenticated and heading to login page,
  // redirect to root page
  if (isAuthenticated && isLoginRoute) {
    return Routes.root;
  }

  // No redirection needed
  return null;
}

/// Creates a router configuration for the app
GoRouter createAppRouter(AuthBloc authBloc) {
  final refreshListenable = AuthStateNotifier(authBloc);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: Routes.root,
    errorBuilder: _errorPage,
    redirect: _authGuard,
    refreshListenable: refreshListenable,
    routes: [
      // Login route
      GoRoute(
        path: Routes.login,
        pageBuilder: (context, state) => MaterialPage<void>(key: state.pageKey, child: const LoginPage()),
      ),
      // Home route
      GoRoute(
        path: Routes.root,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: BlocProvider(
                create:
                    (context) =>
                        HomeBloc(tagUseCase: context.read<TagUseCase>(), minuteUseCase: context.read<MinuteUseCase>())
                          ..add(const HomeEvent.onInit()),
                child: const HomeScreen(),
              ),
              transitionBuilder: PageAnimationManager.fadeTransition,
            ),
        routes: [
          // Transcription summary screen
          GoRoute(
            path: Routes.transcriptionSummary,
            pageBuilder:
                (context, state) => PageAnimationManager.createPage(
                  key: state.pageKey,
                  child: BlocProvider(
                    create:
                        (context) => TranscriptionSummaryBloc(
                          shareRepository: context.read<ShareRepository>(),
                          minuteUseCase: context.read<MinuteUseCase>(),
                          oneAiRepository: context.read<OneAiRepository>(),
                        )..add(TranscriptionSummaryEvent.loadMinute(minuteId: state.extra as String)),
                    child: const TranscriptionSummaryScreen(),
                  ),
                  transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
                ),
          ),
          // Settings screen
          GoRoute(
            path: Routes.settings,
            pageBuilder:
                (context, state) => PageAnimationManager.createPage(
                  key: state.pageKey,
                  child: BlocProvider(
                    create: (context) => SettingsBloc(authRepository: context.read<AuthRepository>()),
                    child: const SettingsScreen(),
                  ),
                  transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
                ),
          ),
        ],
      ),
      GoRoute(path: Routes.demoHome, builder: (context, state) => const DemoHomeScreen()),
      // Users route with BlocProvider
      GoRoute(
        path: Routes.demoUsers,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: BlocProvider(
                create:
                    (context) => DemoUserBloc(
                      userRepository: context.read<DemoUserRepository>(),
                      postRepository: context.read<DemoPostRepository>(),
                    ),
                child: const DemoUserScreen(),
              ),
              transitionBuilder: PageAnimationManager.fadeTransition,
            ),
      ),

      // Post detail route
      GoRoute(
        path: '${Routes.demoPosts}/:postId',
        pageBuilder: (context, state) {
          // Get the post from the extra parameter passed during navigation
          final post = state.extra as DemoPostModel;
          return PageAnimationManager.createPage(
            key: state.pageKey,
            child: DemoPostDetailScreen(post: post),
            transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
          );
        },
      ),

      // Settings placeholder route
      GoRoute(
        path: Routes.demoSettings,
        builder:
            (context, state) => Scaffold(
              appBar: AppBar(
                title: Text(context.loc.settings),
                leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(Routes.demoHome)),
              ),
              body: Center(child: Text(context.loc.settingsComingSoon)),
            ),
      ),

      // Categories placeholder route
      GoRoute(
        path: Routes.demoCategories,
        builder:
            (context, state) => Scaffold(
              appBar: AppBar(
                title: Text(context.loc.categories),
                leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(Routes.demoHome)),
              ),
              body: Center(child: Text(context.loc.categoriesComingSoon)),
            ),
      ),

      // Record Audio Screen
      GoRoute(
        path: Routes.recordAudio,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: const RecordAudioScreen(),
              transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
            ),
      ),
      // Upload File Screen
      GoRoute(
        path: Routes.uploadFile,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: const UploadFileScreen(),
              transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
            ),
      ),
      // YouTube Video Screen
      GoRoute(
        path: Routes.youtubeVideo,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: const YouTubeVideoScreen(),
              transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
            ),
      ),
      // Audio Processing Screen
      GoRoute(
        path: Routes.audioProcessing,
        pageBuilder:
            (context, state) => PageAnimationManager.createPage(
              key: state.pageKey,
              child: const AudioProcessingScreen(),
              transitionBuilder: PageAnimationManager.slideRightToLeftTransition,
            ),
      ),
    ],
  );
}
