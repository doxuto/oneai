import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The screens call ads through these two hooks only. Until A6 wires the
/// GMA SDK they are no-ops, so every screen works ad-free (and in tests).
/// A6 overrides the providers with the real runtime.
abstract interface class InterstitialHook {
  /// Shows an interstitial for [placement] if the gate allows AND one is
  /// already loaded; returns immediately otherwise. Never waits for a load.
  Future<void> maybeShow(String placement);
}

abstract interface class RewardedHook {
  /// Whether a rewarded ad is loaded and the gate allows it right now.
  bool get isReady;

  /// Shows it. Resolves true when the SDK reported the reward was earned
  /// (the CREDIT still arrives later via SSV — see waitForRewardCredit).
  Future<bool> show();
}

class NoopInterstitial implements InterstitialHook {
  const NoopInterstitial();
  @override
  Future<void> maybeShow(String placement) async {}
}

class NoopRewarded implements RewardedHook {
  const NoopRewarded();
  @override
  bool get isReady => false;
  @override
  Future<bool> show() async => false;
}

final interstitialHookProvider = Provider<InterstitialHook>((_) => const NoopInterstitial());
final rewardedHookProvider = Provider<RewardedHook>((_) => const NoopRewarded());

/// Placement names. These are the strings Remote Config `ads_config`
/// lists under `interstitial.placements` / `banner.placements`
/// (Backend/oneai_backend/remote-config/ads_config.defaults.json), so a
/// placement can be switched off from the console without a release.
abstract final class AdPlacement {
  // interstitial
  static const preSummary = 'summaryEnter';
  static const summaryExit = 'summaryExit';
  static const afterShare = 'afterShare';
  static const settingsExit = 'settingsExit';
  // banner
  static const summaryTab = 'summaryTab';
  static const transcriptTab = 'transcriptTab';
  static const chatTab = 'chatTab';
}

/// Inline adaptive banner slot (v1 showed one at the top of each tab).
/// Renders nothing until A6 provides a builder (BannerAdWidget); the layout
/// reserves no space so the page never jumps when there is no fill.

/// Settings → "Privacy options" (UMP). No-op until A6 overrides it.
final privacyOptionsHookProvider = Provider<Future<void> Function(BuildContext)>((_) => (_) async {});

/// Whether UMP says a privacy-options entry point must be shown (GDPR
/// regions). v1 hid the row otherwise; false until A6 overrides it.
final privacyOptionsRequiredProvider = FutureProvider<bool>((_) async => false);
typedef BannerBuilder = Widget Function(BuildContext context, String placement);
final bannerBuilderProvider = Provider<BannerBuilder>((_) => (_, __) => const SizedBox.shrink());

class AdBannerSlot extends ConsumerWidget {
  const AdBannerSlot({required this.placement, super.key});
  final String placement;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(bannerBuilderProvider)(context, placement);
}
