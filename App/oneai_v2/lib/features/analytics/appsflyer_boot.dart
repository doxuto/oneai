import 'dart:developer' as dev;
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:one_ai/core/config/app_config.dart';

/// AppsFlyer attribution. Started once, AFTER the ATT prompt on iOS (the
/// ads runtime calls this from its consent step), never in a dev build so
/// installs from simulators do not pollute attribution.
abstract final class AppsFlyerBoot {
  static AppsflyerSdk? _sdk;

  static Future<void> start(AppConfig config) async {
    if (_sdk != null || config.flavor == Flavor.dev) return;
    try {
      final sdk = AppsflyerSdk(AppsFlyerOptions(
        afDevKey: config.appsFlyerDevKey,
        appId: Platform.isIOS ? config.appsFlyerAppIdIos : config.appsFlyerAppIdAndroid,
        showDebug: config.verboseSdkLogging,
        // ATT already answered by ConsentGate; 0 = do not wait again.
        timeToWaitForATTUserAuthorization: 0,
        disableAdvertisingIdentifier: false,
      ));
      await sdk.initSdk(registerConversionDataCallback: false, registerOnAppOpenAttributionCallback: false, registerOnDeepLinkingCallback: false);
      sdk.startSDK();
      _sdk = sdk;
    } on Object catch (e) {
      dev.log('appsflyer init failed', name: 'analytics', error: e);
    }
  }

  static void logEvent(String name, [Map<String, Object?> params = const {}]) {
    _sdk?.logEvent(name, params);
  }
}
