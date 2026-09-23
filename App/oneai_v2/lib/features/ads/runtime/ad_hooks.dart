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

/// Placements, as v1 named them (docs/08 §6).
abstract final class AdPlacement {
  static const preSummary = 'pre_summary';
  static const summaryExit = 'summary_exit';
  static const afterShare = 'after_share';
  static const settingsExit = 'settings_exit';
}
