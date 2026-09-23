import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/features/auth/login_screen.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/features/minutes/detail/summary_screen.dart';
import 'package:one_ai/features/minutes/home/home_screen.dart';
import 'package:one_ai/features/minutes/ask/ask_all_screen.dart';
import 'package:one_ai/features/minutes/share/shared_note_screen.dart';
import 'package:one_ai/features/settings/glossary_screen.dart';
import 'package:one_ai/features/settings/settings_screen.dart';
import 'package:one_ai/features/transcription/audio_processing_screen.dart';
import 'package:one_ai/features/transcription/incoming_share.dart';
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
      if (!isSignedIn && !atLogin) {
        // Keep a deep link alive across sign-in (`/s?t=…` from a share,
        // `/n/<id>` from a notification link); Home has nothing to keep.
        final target = state.uri.toString();
        return target == Routes.root ? Routes.login : Uri(path: Routes.login, queryParameters: {'from': target}).toString();
      }
      if (isSignedIn && atLogin) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/') && !from.startsWith('//')) ? from : Routes.root;
      }
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
            pageBuilder: (_, state) => _slide(state, const SettingsScreen()),
            routes: [
              GoRoute(path: 'glossary', pageBuilder: (_, state) => _slide(state, const GlossaryScreen())),
            ],
          ),
        ],
      ),
      // ---- Deep links ----
      GoRoute(
        path: Routes.sharedNote,
        pageBuilder: (_, state) {
          final t = state.uri.queryParameters['t'];
          if (t == null || t.isEmpty) return _slide(state, _ErrorPage(path: state.uri.path));
          return _slide(state, SharedNoteScreen(token: t));
        },
      ),
      GoRoute(
        path: Routes.ownNote,
        redirect: (_, state) {
          final id = state.pathParameters['minuteId'];
          return id == null || id.isEmpty ? Routes.root : Uri(path: Routes.transcriptionSummary, queryParameters: {'minuteId': id}).toString();
        },
      ),
      GoRoute(
        path: Routes.recordAudio,
        pageBuilder: (_, state) => _slide(state, const RecordAudioScreen()),
      ),
      GoRoute(
        path: Routes.askAll,
        pageBuilder: (_, state) => _slide(state, const AskAllScreen()),
      ),
      GoRoute(
        path: Routes.uploadFile,
        pageBuilder: (_, state) => _slide(state, UploadFileScreen(sharedFile: state.extra is IncomingShare ? state.extra! as IncomingShare : null)),
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
