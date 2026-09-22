import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/bootstrap.dart';
import 'package:one_ai/core/router/app_router.dart';
import 'package:one_ai/core/theme/app_theme.dart';

class OneAiApp extends ConsumerWidget {
  const OneAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    return MaterialApp.router(
      title: config.appShortName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light,
      // Dark mode stays off until OQ-08 is decided. v1 defined a dark palette
      // but hardcoded `theme: lightTheme`, so it never ran; turning it on now
      // would change what users see.
      themeMode: ThemeMode.light,
    );
  }
}
