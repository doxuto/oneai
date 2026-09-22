import 'dart:async';

import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/utils/extensions.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

/// Service to manage Interstitial Ad logic.
class InterstitialAdService {
  final RemoteConfigService remoteConfig;
  final SharedPreferencesService prefsService;
  final Logger _log = Logger('InterstitialAdService');

  // Wait for ad to load and show completely before proceeding
  Completer<void>? _adLockCompleter;

  // Wait for ad to load before showing
  // = null if ad is not loading or reseted by _showAd()
  // = Completed InterstitialAd if ad is loaded successfully
  // = Completed null if ad failed to load or timed out
  // = Not completed if ad is still loading
  Completer<InterstitialAd?>? _adLoadCompleter;

  // Wait for ad to finish showing before proceeding
  // = null if ad is not loading
  // = Completed int if ad is shown successfully and exits, int is always 0
  // = Completed null if ad failed to show or timed out
  // = Not completed if ad is still preparing to show
  Completer<int?>? _adShowCompleter;

  Timer? _timeoutLoadTimer;
  Timer? _timeoutShowTimer;

  Completer<BuildContext>? _loadingDialogContext;

  DateTime? _lastAdPreloadTime;

  InterstitialAdService(this.remoteConfig, this.prefsService);

  Future<void> _showLoadingDialog(BuildContext context) async {
    _log.info('Loading dialog: show start');
    if (_loadingDialogContext == null) {
      _loadingDialogContext = Completer<BuildContext>();
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        builder: (ctx) {
          if (_loadingDialogContext != null && !_loadingDialogContext!.isCompleted) {
            _log.info('Loading dialog: show complete, assigned context');
            _loadingDialogContext?.complete(ctx);
          }
          // Use PopScope to prevent user from closing dialog
          return const PopScope(canPop: false, child: Center(child: CircularProgressIndicator()));
        },
      );
    }
  }

  // NOTE: Have to wait to hide the dialog completely before return _show()
  // Because Navigator pop can lead to unspecific route cases
  Future<void> _hideLoadingDialog(BuildContext context) async {
    _log.info('Loading dialog: hide start');
    if (_loadingDialogContext != null) {
      final ctx = await _loadingDialogContext!.future;
      if (!ctx.mounted) {
        _loadingDialogContext = null;
        _log.warning('Loading dialog: context is not mounted, cannot hide dialog');
        return;
      }
      _log.info('Loading dialog: context is mounted, hiding dialog');
      if (Navigator.of(ctx).canPop()) {
        _log.info('Loading dialog: hiding dialog Navigator pop');
        Navigator.of(ctx).pop();
      }
      _log.info('Loading dialog: hidden successfully');
      _loadingDialogContext = null;
    }
  }

  void _lock({required BuildContext context, required bool showLoading}) {
    _adLockCompleter = Completer<void>();
    if (showLoading && context.mounted) {
      _showLoadingDialog(context);
    }
  }

  Future<void> _unlock({required BuildContext context, required bool showLoading}) async {
    if (_adLockCompleter?.isCompleted == false) {
      _adLockCompleter?.complete();
    }
    if (showLoading && context.mounted) {
      await _hideLoadingDialog(context);
    }
  }

  bool isLocked() => _adLockCompleter?.isCompleted == false;

  Future<void> _show({
    required BuildContext context,
    required String adUnitId,
    required int loadTimeoutSeconds,
    bool showLoading = true,
  }) async {
    _log.info('Interstitial ad start showing');
    // Check if interstitial ad is already in progress
    if (isLocked()) {
      _log.info('Interstitial ad is already in progress, skipping new ad request');
      return;
    }

    // Check if already showing a fullscreen ad
    if (context.isFullscreenAdInProgress()) {
      _log.info('A fullscreen ad is already in progress, skipping interstitial ad');
      return;
    }

    // Initialize the completer to wait for interstitial ad load
    _lock(context: context, showLoading: showLoading);

    // Check if user is premium
    if (await isPremium()) {
      _log.info('User is premium, skipping interstitial ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return;
    }

    // Check if interstitial ads are enabled in remote config
    if (!remoteConfig.adInterstitialEnabled) {
      _log.info('Interstitial ads are disabled in remote config, skipping interstitial ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return;
    }

    // Check if satisfy the frequency cap for fullscreen ads
    final freqSeconds = remoteConfig.adFullscreenGlobalFreqSeconds;
    final lastShownTime = DateTime.tryParse(await prefsService.getFullScreenAdLastShownTime() ?? '');
    if (lastShownTime != null && DateTime.now().difference(lastShownTime).inSeconds < freqSeconds) {
      _log.info('Full screen ad frequency cap not met, skipping interstitial ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return;
    }

    if (!await hasInternetConnection()) {
      _log.info('No internet connection, cannot show interstitial ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return;
    }

    // Wait for the ad to load
    final ad = context.mounted ? await _loadAd(adUnitId: adUnitId, loadTimeoutSeconds: loadTimeoutSeconds) : null;
    if (ad == null) {
      _log.warning('Interstitial ad failed to load, skipping ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return;
    }

    // Wait for the ad to show completely
    if (context.mounted) {
      // Clear the ad load completer when using the ad to show, because the ad is disposed after showing
      _adLoadCompleter = null;
      _log.info('Interstitial ad loaded successfully, showing ad');
      await _showAd(context: context, ad: ad, showTimeoutSeconds: loadTimeoutSeconds);
    }

    // ignore: use_build_context_synchronously
    await _unlock(context: context, showLoading: showLoading);

    _log.info('Interstitial ad shown successfully');

    // Preload the next interstitial ad after showing the current one
    unawaited(
      Future.delayed(const Duration(seconds: 1), () async {
        final ad = await _adLoadCompleter?.future;
        if (ad == null) {
          _log.info('Preloading next interstitial ad');
          await _loadAd(adUnitId: adUnitId, loadTimeoutSeconds: loadTimeoutSeconds);
        }
      }),
    );

    return _adLockCompleter?.future;
  }

  Future<InterstitialAd?> _loadAd({required String adUnitId, required int loadTimeoutSeconds}) async {
    // Check if interstitial ad is already loaded
    if (_adLoadCompleter?.isCompleted ?? false) {
      final ad = await _adLoadCompleter!.future;
      if (ad != null) {
        if (_lastAdPreloadTime != null &&
            DateTime.now().difference(_lastAdPreloadTime!).inMinutes < remoteConfig.adPreloadTimeoutMinutes) {
          _log.info('Ad preload time is still valid, reusing existing interstitial ad');
          return ad;
        } else {
          _log.info('Ad preload time has expired, continue loading new interstitial ad');
        }
      }
    }

    // Check if interstitial ad is loading
    if (_adLoadCompleter?.isCompleted == false) {
      _log.info('Interstitial ad is loading, waiting for existing load to complete');
      return _adLoadCompleter!.future;
    }

    // Initialize the completer to wait for interstitial ad load
    _adLoadCompleter = Completer<InterstitialAd?>();
    _timeoutLoadTimer?.cancel();
    bool adLoaded = false;
    final startTime = DateTime.now();
    _log.info('Loading interstitial ad: $adUnitId, timeout: $loadTimeoutSeconds s');

    _timeoutLoadTimer = Timer(Duration(seconds: loadTimeoutSeconds), () {
      if (!adLoaded) {
        _log.warning('Interstitial ad load timed out after $loadTimeoutSeconds seconds');
        _adLoadCompleter?.complete(null);
      }
    });

    await InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          adLoaded = true;
          _timeoutLoadTimer?.cancel();
          _log.info('Interstitial ad loaded successfully in ${DateTime.now().difference(startTime).inSeconds} seconds');
          _lastAdPreloadTime = DateTime.now();
          if (_adLoadCompleter?.isCompleted == false) {
            _log.info('Completing ad load completer with loaded interstitial ad');
            _adLoadCompleter?.complete(ad);
          } else {
            _log.warning(
              'Ad load completer is already completed for interstitial ad, in case load success after timeout',
            );
            _adLoadCompleter = Completer<InterstitialAd?>();
            _adLoadCompleter?.complete(ad);
          }
        },
        onAdFailedToLoad: (error) {
          _log.warning('Interstitial ad failed to load: $error');
          _timeoutLoadTimer?.cancel();
          _adLoadCompleter?.complete(null);
        },
      ),
    );

    return _adLoadCompleter!.future;
  }

  Future<int?> _showAd({
    required BuildContext context,
    required InterstitialAd ad,
    required int showTimeoutSeconds,
  }) async {
    // Check if interstitial ad is already showing
    if (_adShowCompleter?.isCompleted == false) {
      // Check ad preload time
      if (_lastAdPreloadTime != null &&
          DateTime.now().difference(_lastAdPreloadTime!).inMinutes < remoteConfig.adPreloadTimeoutMinutes) {
        _log.info('Ad preload time is still valid, add Interstitial ad to load completer again');
        _adLoadCompleter = Completer<InterstitialAd?>();
        _adLoadCompleter?.complete(ad);
      }
      _log.info('Interstitial ad is already showing, waiting for existing show to complete');
      return _adShowCompleter!.future;
    }

    // Initialize the completer to wait for interstitial ad show
    _adShowCompleter = Completer<int?>();
    _timeoutShowTimer?.cancel();
    bool adShown = false;
    final startTime = DateTime.now();
    _log.info('Showing interstitial ad: timeout: $showTimeoutSeconds s');

    _timeoutShowTimer = Timer(Duration(seconds: showTimeoutSeconds), () {
      if (!adShown) {
        _log.warning('Interstitial ad show timed out after $showTimeoutSeconds seconds');
        _adShowCompleter?.complete(null);
      }
    });

    // Clear the ad load completer since we are showing the ad now
    _adLoadCompleter = null;
    // Set callbacks for ad events
    _log.info('Setting up interstitial ad callbacks');
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) async {
        adShown = true;
        _timeoutShowTimer?.cancel();
        _log.info('Interstitial ad shown successfully in ${DateTime.now().difference(startTime).inSeconds} seconds');
        await prefsService.setFullScreenAdLastShownTime(DateTime.now().toIso8601String());
      },
      onAdDismissedFullScreenContent: (ad) async {
        _log.info('Interstitial ad dismissed');
        await ad.dispose();
        await prefsService.setFullScreenAdLastShownTime(DateTime.now().toIso8601String());
        _adShowCompleter?.complete(0);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _log.warning('Interstitial ad failed to show: $error');
        _timeoutShowTimer?.cancel();
        ad.dispose();
        _adShowCompleter?.complete(null);
      },
    );

    try {
      // NOTE: Only show ad if screen that trigger ad is still mounted
      if (context.mounted) {
        await ad.show();
        _log.info('Showing interstitial ad');
      } else {
        _log.warning('Context is not mounted, cannot show interstitial ad');
        _timeoutShowTimer?.cancel();
        await ad.dispose();
        _adShowCompleter?.complete(null);
      }
    } catch (e) {
      _log.warning('Failed to show interstitial ad: $e');
      _timeoutShowTimer?.cancel();
      await ad.dispose();
      _adShowCompleter?.complete(null);
      return null;
    }

    return _adShowCompleter!.future;
  }

  //--------------------------------------------------------------------------------------
  // Show interstitial ad at specific positions
  Future<void> showBeforeSummaryEnter({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitInterstitialPreSummary,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds,
    showLoading: showLoading,
  );

  Future<void> showBeforeSummaryExit({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitInterstitialSummaryExit,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds,
    showLoading: showLoading,
  );

  Future<void> showAfterShare({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitInterstitialAfterShare,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds,
    showLoading: showLoading,
  );

  Future<void> showBeforeSettingsExit({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitInterstitialSettingsExit,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds,
    showLoading: showLoading,
  );
}
