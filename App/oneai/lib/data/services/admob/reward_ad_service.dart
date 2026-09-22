import 'dart:async';

import 'package:codebase_ai/data/services/api/oneai/oneai_api_service.dart';
import 'package:codebase_ai/data/services/remote_config_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/utils/extensions.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:logging/logging.dart';

/// Service to manage Reward Ad logic.
class RewardAdService {
  final RemoteConfigService remoteConfig;
  final SharedPreferencesService prefsService;
  final OneAiApiService apiService;
  final Logger _log = Logger('RewardAdService');

  // Wait for ad to load and show completely before proceeding, return reward amount
  Completer<int?>? _adLockCompleter;

  // Wait for ad to load before showing
  // = null if ad is not loading or reseted by _showAd()
  // = Completed RewardedAd if ad is loaded successfully
  // = Completed null if ad failed to load or timed out
  // = Not completed if ad is still loading
  Completer<RewardedAd?>? _adLoadCompleter;

  // Wait for ad to finish showing before proceeding
  // = null if ad is not loading
  // = Completed int if ad is shown successfully and exits, int is reward amount
  //   (0 if no reward, >0 if reward given)
  // = Completed null if ad failed to show or timed out
  // = Not completed if ad is still preparing to show
  Completer<int?>? _adShowCompleter;

  Timer? _timeoutLoadTimer;
  Timer? _timeoutShowTimer;

  Completer<BuildContext>? _loadingDialogContext;

  DateTime? _lastAdPreloadTime;

  RewardAdService(this.remoteConfig, this.prefsService, this.apiService);

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
    _adLockCompleter = Completer<int?>();
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

  Future<int?> _show({
    required BuildContext context,
    required String adUnitId,
    required int loadTimeoutSeconds,
    bool showLoading = true,
  }) async {
    _log.info('Reward ad start showing');
    // Check if reward ad is already in progress
    if (isLocked()) {
      _log.info('Reward ad is already in progress, skipping new ad request');
      if (context.mounted) _showToast(context, '⚠️ Reward ad is already in loading, please wait.');
      return null;
    }

    // Check if already showing a fullscreen ad
    if (context.isFullscreenAdInProgress()) {
      _log.info('A fullscreen ad is already in progress, skipping reward ad');
      if (context.mounted) _showToast(context, '⚠️ A fullscreen ad is already in progress, please try again later.');
      return null;
    }

    // Initialize the completer to wait for reward ad load
    _lock(context: context, showLoading: showLoading);

    // Check if user is premium
    if (await isPremium()) {
      _log.info('User is premium, skipping reward ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return null;
    }

    // Check if reward ads are enabled in remote config
    if (!remoteConfig.adRewardedEnabled) {
      _log.info('Reward ads are disabled in remote config, skipping reward ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      if (context.mounted) {
        _showToast(context, '⚠️ No rewarded ads available at the moment. Please try again later.');
      }
      return null;
    }

    // Check if satisfy the frequency cap for fullscreen ads
    final freqSeconds = remoteConfig.adFullscreenGlobalFreqSeconds;
    final lastShownTime = DateTime.tryParse(await prefsService.getFullScreenAdLastShownTime() ?? '');
    if (lastShownTime != null && DateTime.now().difference(lastShownTime).inSeconds < freqSeconds) {
      _log.info('Full screen ad frequency cap not met, skipping reward ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      if (context.mounted) _showToast(context, remoteConfig.adToastFreqLimitMessage);
      return null;
    }

    await checkAndResetDailyCounter();

    final rewardedShownToday = await prefsService.getRewardedAdShownToday();
    _log.fine('Rewarded ads shown today: $rewardedShownToday / ${remoteConfig.adRewardedDailyLimit}');
    // If remoteConfig.adRewardedDailyLimit == 0, it means no limit
    if (remoteConfig.adRewardedDailyLimit != 0 && rewardedShownToday >= remoteConfig.adRewardedDailyLimit) {
      _log.info('User has reached daily rewarded ad limit');
      if (context.mounted) {
        _showToast(context, "⚠️ You have reached today's reward ad limit.");
      }
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return null;
    }

    if (!await hasInternetConnection()) {
      _log.info('No internet connection, cannot show rewarded ad');
      if (context.mounted) {
        _showToast(context, '📡 Please connect to the internet...');
      }
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      return null;
    }

    // Wait for the ad to load
    final ad = context.mounted ? await _loadAd(adUnitId: adUnitId, loadTimeoutSeconds: loadTimeoutSeconds) : null;
    if (ad == null) {
      _log.warning('Reward ad failed to load, skipping ad');
      // ignore: use_build_context_synchronously
      await _unlock(context: context, showLoading: showLoading);
      if (context.mounted) {
        _showToast(context, '⚠️ No rewarded ads available at the moment. Please try again later.');
      }
      return null;
    }

    // Wait for the ad to show completely
    if (context.mounted) {
      // Clear the ad load completer when using the ad to show, because the ad is disposed after showing
      _adLoadCompleter = null;
      _log.info('Reward ad loaded successfully, showing ad');
      final amountRewarded = await _showAd(context: context, ad: ad, showTimeoutSeconds: loadTimeoutSeconds);
      if (_adLockCompleter?.isCompleted == false) {
        _adLockCompleter?.complete(amountRewarded);
      }
    }

    // ignore: use_build_context_synchronously
    await _unlock(context: context, showLoading: showLoading);

    _log.info('Reward ad shown successfully');

    // Preload the next rewarded ad after showing the current one
    unawaited(
      Future.delayed(const Duration(seconds: 1), () async {
        final ad = await _adLoadCompleter?.future;
        if (ad == null) {
          _log.info('Preloading next rewarded ad');
          await _loadAd(adUnitId: adUnitId, loadTimeoutSeconds: loadTimeoutSeconds);
        }
      }),
    );

    return _adLockCompleter?.future;
  }

  Future<RewardedAd?> _loadAd({required String adUnitId, required int loadTimeoutSeconds}) async {
    // Check if reward ad is already loaded
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

    // Check if reward ad is loading
    if (_adLoadCompleter?.isCompleted == false) {
      _log.info('Reward ad is loading, waiting for existing load to complete');
      return _adLoadCompleter!.future;
    }

    // Initialize the completer to wait for reward ad load
    _adLoadCompleter = Completer<RewardedAd?>();
    _timeoutLoadTimer?.cancel();
    bool adLoaded = false;
    final startTime = DateTime.now();
    _log.info('Loading reward ad: $adUnitId, timeout: $loadTimeoutSeconds s');

    _timeoutLoadTimer = Timer(Duration(seconds: loadTimeoutSeconds), () {
      if (!adLoaded) {
        _log.warning('Reward ad load timed out after $loadTimeoutSeconds seconds');
        _adLoadCompleter?.complete(null);
      }
    });

    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          adLoaded = true;
          _timeoutLoadTimer?.cancel();
          _log.info('Reward ad loaded successfully in ${DateTime.now().difference(startTime).inSeconds} seconds');
          _lastAdPreloadTime = DateTime.now();
          if (_adLoadCompleter?.isCompleted == false) {
            _log.info('Completing ad load completer with loaded rewarded ad');
            _adLoadCompleter?.complete(ad);
          } else {
            _log.warning('Ad load completer is already completed for rewarded ad, in case load success after timeout');
            _adLoadCompleter = Completer<RewardedAd?>();
            _adLoadCompleter?.complete(ad);
          }
        },
        onAdFailedToLoad: (error) {
          _log.warning('Reward ad failed to load: $error');
          _timeoutLoadTimer?.cancel();
          _adLoadCompleter?.complete(null);
        },
      ),
    );

    return _adLoadCompleter!.future;
  }

  Future<int?> _showAd({required BuildContext context, required RewardedAd ad, required int showTimeoutSeconds}) async {
    // Check if reward ad is already showing
    if (_adShowCompleter?.isCompleted == false) {
      // Check ad preload time
      if (_lastAdPreloadTime != null &&
          DateTime.now().difference(_lastAdPreloadTime!).inMinutes < remoteConfig.adPreloadTimeoutMinutes) {
        _log.info('Ad preload time is still valid, add Rewarded ad to load completer again');
        _adLoadCompleter = Completer<RewardedAd?>();
        _adLoadCompleter?.complete(ad);
      }
      _log.info('Reward ad is already showing, waiting for existing show to complete');
      return _adShowCompleter!.future;
    }

    // Initialize the completer to wait for reward ad show
    _adShowCompleter = Completer<int?>();
    _timeoutShowTimer?.cancel();
    bool adShown = false;
    final startTime = DateTime.now();
    _log.info('Showing reward ad: timeout: $showTimeoutSeconds s');
    bool rewarded = false;
    int rewardAmount = 1; // Default reward amount, can be adjusted later

    _timeoutShowTimer = Timer(Duration(seconds: showTimeoutSeconds), () {
      if (!adShown) {
        _log.warning('Reward ad show timed out after $showTimeoutSeconds seconds');
        _adShowCompleter?.complete(null);
      }
    });

    // Clear the ad load completer since we are showing the ad now
    _adLoadCompleter = null;
    // Set callbacks for ad events
    _log.info('Setting up reward ad callbacks');
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) async {
        adShown = true;
        _timeoutShowTimer?.cancel();
        _log.info('Reward ad shown successfully in ${DateTime.now().difference(startTime).inSeconds} seconds');
        await prefsService.setFullScreenAdLastShownTime(DateTime.now().toIso8601String());
      },
      onAdDismissedFullScreenContent: (ad) async {
        _log.info('Reward ad dismissed');
        await ad.dispose();
        await prefsService.setFullScreenAdLastShownTime(DateTime.now().toIso8601String());
        if (rewarded) {
          _log.info('User completed watching rewarded ad, calling reward API');
          final success = await _callRewardApiWithRetry(reward: rewardAmount);
          if (success) {
            _log.info('Reward API call succeeded, incrementing rewarded ad counter');
            final current = await prefsService.getRewardedAdShownToday();
            await prefsService.setRewardedAdShownToday(current + 1);
            if (context.mounted) {
              _showToast(context, '✅ You received $rewardAmount free credit!');
            }
            _adShowCompleter?.complete(rewardAmount);
          } else {
            _log.warning('Reward API call failed after retries');
            if (context.mounted) {
              _showToast(context, '✅ Ad completed! We will add your credit soon...');
            }
            _adShowCompleter?.complete(null);
          }
        } else {
          _log.info('User did not complete watching rewarded ad');
          if (context.mounted) {
            _showToast(context, '⚠️ Ad not completed. No credit awarded.');
          }
          _adShowCompleter?.complete(null);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _log.warning('Reward ad failed to show: $error');
        ad.dispose();
        if (context.mounted) _showToast(context, '⚠️ No rewarded ads available at the moment. Please try again later.');
        _timeoutShowTimer?.cancel();
        _adShowCompleter?.complete(null);
      },
    );

    try {
      // NOTE: Only show ad if screen that trigger ad is still mounted
      if (context.mounted) {
        await ad.show(
          onUserEarnedReward: (ad, reward) {
            _log.info('User earned reward: type=[33m${reward.type}[0m, amount=[33m${reward.amount}[0m');
            rewarded = true;
            rewardAmount = reward.amount.toInt();
          },
        );
        _log.info('Showing reward ad');
      } else {
        _log.warning('Context is not mounted, cannot show reward ad');
        _timeoutShowTimer?.cancel();
        await ad.dispose();
        _adShowCompleter?.complete(null);
      }
    } catch (e) {
      _log.warning('Failed to show reward ad: $e');
      if (context.mounted) _showToast(context, '⚠️ No rewarded ads available at the moment. Please try again later.');
      _timeoutShowTimer?.cancel();
      await ad.dispose();
      _adShowCompleter?.complete(null);
      return null;
    }

    return _adShowCompleter!.future;
  }

  //--------------------------------------------------------------------------------------
  /// Call this at app start or when user logs in to reset daily counter if needed
  Future<void> checkAndResetDailyCounter() async {
    _log.fine('Checking and resetting daily rewarded ad counter if needed');
    final now = DateTime.now();
    final lastResetDateStr = await prefsService.getRewardedAdLastResetDate();
    DateTime? lastResetDate;
    if (lastResetDateStr != null) {
      try {
        lastResetDate = DateTime.parse(lastResetDateStr);
        _log.fine('Last reset date loaded: $lastResetDate');
      } catch (e) {
        _log.warning('Failed to parse last reset date: $lastResetDateStr, error: $e');
      }
    }
    if (lastResetDate == null ||
        now.year != lastResetDate.year ||
        now.month != lastResetDate.month ||
        now.day != lastResetDate.day) {
      _log.info('Resetting rewarded ad counter for new day');
      await prefsService.setRewardedAdShownToday(0);
      await prefsService.setRewardedAdLastResetDate(now.toIso8601String());
    }
  }

  Future<bool> _callRewardApiWithRetry({int reward = 1}) async {
    int retries = 0;
    const maxRetries = 3;
    while (retries < maxRetries) {
      try {
        _log.fine('Calling reward API, attempt \\${retries + 1}, reward: $reward');
        final result = await apiService.postRewardedAdCredit(reward: reward);
        if (result is Ok<int>) {
          final value = result.value;
          if (value > 0) {
            _log.info('Reward API call successful, received $value credits');
            return true;
          } else {
            _log.warning('Reward API call returned unexpected value: $value');
          }
        } else if (result is Error) {
          _log.warning('Reward API call error: $result');
        }
      } catch (e) {
        _log.warning('Reward API call failed: $e');
      }
      retries++;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _log.warning('Reward API call failed after $maxRetries attempts');
    return false;
  }

  void _showToast(BuildContext context, String message) {
    _log.fine('Showing toast: $message');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  //--------------------------------------------------------------------------------------
  // Show reward ad at specific positions
  Future<int?> showBeforeTranscribeProcess({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitRewarded,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds * 2, // Increased timeout for better user experience
    showLoading: showLoading,
  );

  Future<int?> showWhenWaitingTranscribeProcess({required BuildContext context, bool showLoading = true}) => _show(
    context: context,
    adUnitId: remoteConfig.adUnitRewarded,
    loadTimeoutSeconds: remoteConfig.adLoadTimeoutSeconds * 2, // Increased timeout for better user experience
    showLoading: showLoading,
  );
}
