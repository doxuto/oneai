import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:one_ai/core/config/remote_config.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/features/ads/ad_gate.dart';
import 'package:one_ai/features/ads/ad_ledger.dart';
import 'package:one_ai/features/ads/ads_config.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/ads/runtime/ad_units.dart';
import 'package:one_ai/features/ads/runtime/consent.dart';
import 'package:one_ai/features/ads/runtime/ledger_store.dart';
import 'package:one_ai/features/analytics/appsflyer_boot.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/bootstrap.dart';

/// The one object that talks to the GMA SDK. Everything it decides goes
/// through the pure [AdGate] with the persisted [AdLedger]; it only owns the
/// SDK objects (load / show / dispose) and the app-lifecycle hook.
///
/// Rules it enforces (docs/08 §6):
///   - nothing runs before consent (UMP → ATT → MobileAds.initialize);
///   - a premium user never sees an ad and loaded ads are dropped at once;
///   - a full-screen ad is shown only if already loaded — never "load and wait";
///   - rewarded ads carry SSV with the auth uid; the client never credits;
///   - the app-open ad is shown on resume, gated by seconds in background.
class AdsRuntime with WidgetsBindingObserver implements InterstitialHook, RewardedHook {
  AdsRuntime(this._ref, {ConsentGate? consent, LedgerStore? store})
      : _consent = consent ?? ConsentGate(),
        _store = store ?? LedgerStore();

  final Ref _ref;
  final ConsentGate _consent;
  final LedgerStore _store;

  AdLedger _ledger = AdLedger();
  AdsConfig _config = const AdsConfig();
  AdUnits _units = AdUnits.parse(null, forceTest: true);

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  AppOpenAd? _appOpen;
  bool _loadingInterstitial = false;
  bool _loadingRewarded = false;
  bool _loadingAppOpen = false;

  bool _started = false;
  bool _ready = false;
  bool _showing = false;
  DateTime? _backgroundedAt;

  AdsConfig get config => _config;
  AdUnits get units => _units;

  /// Whether the SDK is initialised and this user should see ads. Banner
  /// widgets read this; it flips to false the moment premium activates.
  bool get canServe => _ready && adsEntitled && _config.enabled;

  bool get adsEntitled => !(_ref.read(isPremiumProvider).valueOrNull ?? false);

  AdContext _ctx() => AdContext(ledger: _ledger, adsEntitled: adsEntitled, now: DateTime.now());

  // ---- lifecycle ---------------------------------------------------------

  /// Idempotent. Runs after the first frame; never throws.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _ledger = await _store.load();
    _ledger.recordSessionStart(DateTime.now());
    unawaited(_store.save(_ledger));

    _ref.listen<AsyncValue<bool>>(isPremiumProvider, (_, next) {
      if (next.valueOrNull ?? false) _dropLoaded();
    });

    final rc = await _ref.read(remoteConfigProvider.future);
    _config = rc.adsConfig;
    _units = AdUnits.parse(rc.adUnitsJson);

    final ok = await _consent.gather();
    // AppsFlyer waits for ATT (part of gather) so iOS attribution is not
    // started before the prompt — Apple rejects the reverse order.
    unawaited(AppsFlyerBoot.start(_ref.read(appConfigProvider)));
    if (!ok) {
      dev.log('ads: consent denied or SDK init failed; ads stay off', name: 'ads');
      return;
    }
    _ready = true;
    _preloadAll();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dropLoaded();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _backgroundedAt = DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null) unawaited(_maybeShowAppOpen(DateTime.now().difference(since).inSeconds));
      default:
        break;
    }
  }

  // ---- ledger -----------------------------------------------------------

  /// A "done" moment (note created, share finished). Feeds the interstitial
  /// pacing; call BEFORE the placement's maybeShow.
  void recordCompletion() {
    _ledger.recordCompletion();
    unawaited(_store.save(_ledger));
  }

  void _recordShown(AdFormat f) {
    _ledger.recordShown(f, DateTime.now());
    unawaited(_store.save(_ledger));
  }

  void _recordDismissed() {
    _showing = false;
    _ledger.recordFullScreenDismissed(DateTime.now());
    unawaited(_store.save(_ledger));
  }

  // ---- loading ----------------------------------------------------------

  void _preloadAll() {
    if (!canServe) return;
    if (_config.interstitial.enabled) _loadInterstitial();
    if (_config.rewarded.enabled) _loadRewarded();
    if (_config.appOpen.enabled) _loadAppOpen();
  }

  void _dropLoaded() {
    _interstitial?.dispose();
    _rewarded?.dispose();
    _appOpen?.dispose();
    _interstitial = null;
    _rewarded = null;
    _appOpen = null;
  }

  void _loadInterstitial() {
    if (_loadingInterstitial || _interstitial != null || !canServe) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: _units[AdFormat.interstitial],
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          if (!canServe) return ad.dispose();
          _interstitial = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingInterstitial = false;
          dev.log('interstitial load failed', name: 'ads', error: e.message);
        },
      ),
    );
  }

  void _loadRewarded() {
    if (_loadingRewarded || _rewarded != null || !canServe) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: _units[AdFormat.rewarded],
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) async {
          _loadingRewarded = false;
          if (!canServe) return ad.dispose();
          // SSV: the uid is what the server reads back from AdMob's callback
          // (docs/08 §5). Without it the reward is dropped server-side.
          final uid = _ref.read(authUserProvider).valueOrNull?.uid;
          if (uid == null) return ad.dispose();
          await ad.setServerSideOptions(ServerSideVerificationOptions(userId: uid));
          _rewarded = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingRewarded = false;
          dev.log('rewarded load failed', name: 'ads', error: e.message);
        },
      ),
    );
  }

  void _loadAppOpen() {
    if (_loadingAppOpen || _appOpen != null || !canServe) return;
    _loadingAppOpen = true;
    AppOpenAd.load(
      adUnitId: _units[AdFormat.appOpen],
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingAppOpen = false;
          if (!canServe) return ad.dispose();
          _appOpen = ad;
        },
        onAdFailedToLoad: (e) {
          _loadingAppOpen = false;
          dev.log('app open load failed', name: 'ads', error: e.message);
        },
      ),
    );
  }

  // ---- InterstitialHook -------------------------------------------------

  @override
  Future<void> maybeShow(String placement) async {
    if (_showing) return;
    // Opening a note or finishing a share is a completion in v1's sense.
    if (placement == AdPlacement.preSummary || placement == AdPlacement.afterShare) recordCompletion();
    final decision = AdGate.interstitial(_config, _ctx(), placement: placement);
    if (decision is AdRefused) {
      dev.log('interstitial refused: ${decision.reason.name} @$placement', name: 'ads');
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial(); // for next time; never wait
      return;
    }
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _recordShown(AdFormat.interstitial),
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _recordDismissed();
        if (!done.isCompleted) done.complete();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showing = false;
        dev.log('interstitial show failed', name: 'ads', error: e.message);
        if (!done.isCompleted) done.complete();
        _loadInterstitial();
      },
    );
    _showing = true;
    await ad.show();
    await done.future;
  }

  // ---- RewardedHook -----------------------------------------------------

  @override
  bool get isReady => _rewarded != null && AdGate.rewarded(_config, _ctx()).isAllowed;

  @override
  Future<bool> show() async {
    final ad = _rewarded;
    if (ad == null || _showing || !AdGate.rewarded(_config, _ctx()).isAllowed) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    var earned = false;
    final done = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _recordShown(AdFormat.rewarded),
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _recordDismissed();
        if (!done.isCompleted) done.complete(earned);
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showing = false;
        dev.log('rewarded show failed', name: 'ads', error: e.message);
        if (!done.isCompleted) done.complete(false);
        _loadRewarded();
      },
    );
    _showing = true;
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return done.future;
  }

  // ---- App open ---------------------------------------------------------

  Future<void> _maybeShowAppOpen(int secondsInBackground) async {
    if (_showing) return;
    final decision = AdGate.appOpen(_config, _ctx(), secondsInBackground: secondsInBackground);
    if (decision is AdRefused) {
      dev.log('app open refused: ${decision.reason.name}', name: 'ads');
      return;
    }
    final ad = _appOpen;
    if (ad == null) {
      _loadAppOpen();
      return;
    }
    _appOpen = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _recordShown(AdFormat.appOpen),
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _recordDismissed();
        _loadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showing = false;
        dev.log('app open show failed', name: 'ads', error: e.message);
        _loadAppOpen();
      },
    );
    _showing = true;
    await ad.show();
  }

  // ---- Privacy options --------------------------------------------------

  Future<void> showPrivacyOptions(BuildContext context) => _consent.showPrivacyOptions(context);
}

/// App-wide singleton. Watched once from [OneAiApp]; screens reach it only
/// through the hook providers below.
final adsRuntimeProvider = Provider<AdsRuntime>((ref) {
  final rt = AdsRuntime(ref);
  ref.onDispose(rt.dispose);
  WidgetsBinding.instance.addPostFrameCallback((_) => rt.start());
  return rt;
});

/// Overrides for the four hook providers; bootstrap passes them to
/// ProviderScope so tests keep the no-op defaults.
List<Override> adsOverrides() => [
      interstitialHookProvider.overrideWith((ref) => ref.watch(adsRuntimeProvider)),
      rewardedHookProvider.overrideWith((ref) => ref.watch(adsRuntimeProvider)),
      privacyOptionsHookProvider.overrideWith((ref) => ref.watch(adsRuntimeProvider).showPrivacyOptions),
      bannerBuilderProvider.overrideWith((ref) => (_, placement) => BannerAdWidget(placement: placement)),
    ];

/// Inline anchored-adaptive banner. Empty (zero height) until an ad has
/// actually loaded, so the page never reserves space for a no-fill.
class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({required this.placement, super.key});
  final String placement;

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) _load();
  }

  Future<void> _load() async {
    final rt = ref.read(adsRuntimeProvider);
    if (!rt.canServe) return;
    final decision = AdGate.banner(rt.config, placement: widget.placement, adsEntitled: rt.adsEntitled);
    if (!decision.isAllowed) return;
    _requested = true;
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    final ad = BannerAd(
      adUnitId: rt.units[AdFormat.banner],
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, e) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
          dev.log('banner load failed @${widget.placement}', name: 'ads', error: e.message);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Premium bought while the tab is open → hide at once.
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final ad = _ad;
    if (premium || ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad));
  }
}
