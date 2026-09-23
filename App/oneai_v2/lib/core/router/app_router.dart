import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/features/auth/login_screen.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/features/minutes/detail/summary_screen.dart';
import 'package:one_ai/features/minutes/home/home_screen.dart';
import 'package:one_ai/features/transcription/audio_processing_screen.dart';
import 'package:one_ai/features/transcription/record_audio_screen.dart';
import 'package:one_ai/features/transcription/upload_file_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) {
  // While auth is still resolving on cold start, treat as signed out; the
  // redirect re-runs when the stream emits because the provider is watched.
  final isSignedIn = ref.watch(authUserProvider).valueOrNull != null;

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.root,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == Routes.login;
      if (!isSignedIn && !atLogin) return Routes.login;
      if (isSignedIn && atLogin) return Routes.root;
      return null;
    },
    errorBuilder: (context, state) => _ErrorPage(path: state.uri.path),
    routes: <RouteBase>[
      GoRoute(
        path: Routes.login,
        pageBuilder: (_, state) => MaterialPage(key: state.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: Routes.root,
        pageBuilder: (_, state) => CustomTransitionPage<void>(
          key: state.pageKey,
          child: const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: 'transcriptionSummary',
            pageBuilder: (_, state) {
              final args = SummaryArgs.from(state.extra, state.uri.queryParameters);
              if (args == null) return _slide(state, _ErrorPage(path: state.uri.path));
              return _slide(state, TranscriptionSummaryScreen(args: args));
            },
          ),
          GoRoute(
            path: 'settings',
            builder: (_, __) => const _Placeholder('Settings'),
          ),
        ],
      ),
      GoRoute(
        path: Routes.recordAudio,
        pageBuilder: (_, state) => _slide(state, const RecordAudioScreen()),
      ),
      GoRoute(
        path: Routes.uploadFile,
        pageBuilder: (_, state) => _slide(state, const UploadFileScreen()),
      ),
      GoRoute(
        path: Routes.audioProcessing,
        pageBuilder: (_, state) {
          final args = state.extra;
          if (args is! AudioProcessingArgs) return _slide(state, _ErrorPage(path: state.uri.path));
          return _slide(state, AudioProcessingScreen(args: args));
        },
      ),
    ],
  );
});

/// v1's slideRightToLeft transition (docs/07 §2).
CustomTransitionPage<void> _slide(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionsBuilder: (_, animation, __, child) => SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );

/// Replaced feature by feature during S3–S6.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(name)),
        body: Center(child: Text('$name — not built yet')),
      );
}

class _ErrorPage extends StatelessWidget {
  const _ErrorPage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 64, color: colors.error),
            const SizedBox(height: 16),
            Text(
              'No route for $path',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go(Routes.root),
              child: const Text('Go home'),
            ),
          ],
        ),
      ),
    );
  }
}
