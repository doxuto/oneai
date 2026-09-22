import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/router/routes.dart';

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
        builder: (_, __) => const _Placeholder('Login'),
      ),
      GoRoute(
        path: Routes.root,
        builder: (_, __) => const _Placeholder('Home'),
        routes: <RouteBase>[
          GoRoute(
            path: 'transcriptionSummary',
            builder: (_, __) => const _Placeholder('Summary'),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, __) => const _Placeholder('Settings'),
          ),
        ],
      ),
      GoRoute(
        path: Routes.recordAudio,
        builder: (_, __) => const _Placeholder('Record'),
      ),
      GoRoute(
        path: Routes.uploadFile,
        builder: (_, __) => const _Placeholder('Upload'),
      ),
      GoRoute(
        path: Routes.audioProcessing,
        builder: (_, __) => const _Placeholder('Processing'),
      ),
    ],
  );
});

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
