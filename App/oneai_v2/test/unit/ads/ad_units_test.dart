import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/ads/ads_config.dart';
import 'package:one_ai/features/ads/runtime/ad_units.dart';

void main() {
  const json = '{"banner":{"ios":"ca-app-pub-1/ios-banner","android":"ca-app-pub-1/android-banner"},'
      '"rewarded":{"ios":"ca-app-pub-1/ios-rewarded"}}';

  test('forceTest ignores live ids and returns Google test ids', () {
    final u = AdUnits.parse(json, forceTest: true);
    expect(u[AdFormat.banner], startsWith('ca-app-pub-3940256099942544/'));
    expect(u[AdFormat.rewarded], startsWith('ca-app-pub-3940256099942544/'));
  });

  test('live ids are used per platform, missing keys fall back to test ids', () {
    final u = AdUnits.parse(json, forceTest: false);
    final ios = Platform.isIOS;
    expect(u[AdFormat.banner], ios ? 'ca-app-pub-1/ios-banner' : 'ca-app-pub-1/android-banner');
    // rewarded has no android id → test id on android; interstitial absent everywhere.
    expect(u[AdFormat.interstitial], startsWith('ca-app-pub-3940256099942544/'));
    if (!ios) expect(u[AdFormat.rewarded], startsWith('ca-app-pub-3940256099942544/'));
  });

  test('garbage json yields test ids for every format', () {
    final u = AdUnits.parse('not json', forceTest: false);
    for (final f in AdFormat.values) {
      expect(u[f], startsWith('ca-app-pub-3940256099942544/'), reason: f.name);
    }
  });
}
