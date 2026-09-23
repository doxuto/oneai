import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/bootstrap.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/app_router.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/app_theme.dart';
import 'package:one_ai/features/ads/runtime/ads_runtime.dart';
import 'package:one_ai/features/auth/splash_gate.dart';
import 'package:one_ai/features/notifications/push_registrar.dart';
import 'package:one_ai/features/transcription/incoming_share.dart';
import 'package:one_ai/features/transcription/upload_queue.dart';

class OneAiApp extends ConsumerWidget {
  const OneAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);

    // Keep the push registrar alive for the app's lifetime: it follows auth
    // and token rotation on its own. Permission is requested from the UI.
    ref.watch(pushRegistrarProvider);

    // Ads runtime: consent → SDK init → preload, all after first frame; also
    // owns the app-open-on-resume hook. Premium users get no ads from it.
    ref.watch(adsRuntimeProvider);

    // Upload queue (S11-07): resumes saved recordings and retries when online.
    ref.watch(uploadQueueProvider);

    // A tapped "your note is ready" notification opens that note. Failed
    // notes open too — the summary screen shows the failure and the retry.
    ref.listen(pushTapProvider, (_, next) {
      final tap = next.valueOrNull;
      if (tap == null) return;
      router.push(Routes.transcriptionSummary, extra: {'minuteId': tap.minuteId});
    });

    // A file shared from another app (iOS Share Extension / Android
    // ACTION_SEND) lands on the upload screen with the file preselected. The
    // share is parked first so it survives the sign-in redirect: UploadFileScreen
    // takes it from the provider when it finally opens.
    ref.listen(incomingShareProvider, (_, next) {
      final shares = next.valueOrNull;
      if (shares == null || shares.isEmpty) return;
      ref.read(pendingIncomingSharesProvider.notifier).addAll(shares);
      router.push(Routes.uploadFile);
    });

    return MaterialApp.router(
      title: config.appShortName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // gen-l10n (l10n.yaml → core/l10n/generated). Without these every
      // `context.l10n` throws; the device locale picks en / vi / es.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // v1 wrapped the whole app so a tap outside a field closes the keyboard.
      builder: (_, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: SplashGate(child: child ?? const SizedBox.shrink()),
      ),
      theme: AppTheme.light,
      // Dark mode stays off until OQ-08 is decided. v1 defined a dark palette
      // but hardcoded `theme: lightTheme`, so it never ran; turning it on now
      // would change what users see.
      themeMode: ThemeMode.light,
    );
  }
}
