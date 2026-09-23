import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/ads/ads_config.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';

/// The placement strings the screens use must be the ones Remote Config
/// lists, or a placement silently never shows (placementDisabled).
void main() {
  test('interstitial placements match ads_config defaults', () {
    const c = InterstitialRules();
    for (final p in [AdPlacement.preSummary, AdPlacement.summaryExit, AdPlacement.afterShare, AdPlacement.settingsExit]) {
      expect(c.placements, contains(p), reason: p);
    }
  });

  test('banner summaryTab is the default; other tabs are opt-in from RC', () {
    const b = BannerRules();
    expect(b.placements, contains(AdPlacement.summaryTab));
    expect(b.placements, isNot(contains(AdPlacement.transcriptTab)));
    expect(b.placements, isNot(contains(AdPlacement.chatTab)));
  });

  test('a placement can be switched off from Remote Config alone', () {
    final c = AdsConfig.parse('{"enabled":true,"interstitial":{"placements":["summaryExit"]}}');
    expect(c.interstitial.placements, ['summaryExit']);
    expect(c.interstitial.placements, isNot(contains(AdPlacement.preSummary)));
  });
}
