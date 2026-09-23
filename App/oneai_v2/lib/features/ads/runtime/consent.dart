import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// UMP consent, then (iOS only) ATT — in that order, per docs/08 §4. GMA is
/// initialised only after `canRequestAds` is true. Nothing here blocks the
/// first frame: it runs after the app is up.
class ConsentGate {
  bool _initialized = false;
  bool get canRequestAds => _initialized;

  /// Resolves true when ads may be requested. Never throws.
  Future<bool> gather() async {
    final done = Completer<bool>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          ConsentForm.loadAndShowConsentFormIfRequired((formError) async {
            if (formError != null) dev.log('ump form error', name: 'ads', error: formError.message);
            done.complete(await _afterConsent());
          });
        } else {
          done.complete(await _afterConsent());
        }
      },
      (error) async {
        dev.log('ump update error', name: 'ads', error: error.message);
        // A UMP failure must not brick ads for users outside regulated regions.
        done.complete(await _afterConsent());
      },
    );
    return done.future.timeout(const Duration(seconds: 20), onTimeout: () => false);
  }

  Future<bool> _afterConsent() async {
    final allowed = await ConsentInformation.instance.canRequestAds();
    if (!allowed) return false;
    if (Platform.isIOS) {
      try {
        if (await AppTrackingTransparency.trackingAuthorizationStatus == TrackingStatus.notDetermined) {
          await AppTrackingTransparency.requestTrackingAuthorization();
        }
      } on Object catch (e) {
        dev.log('att failed', name: 'ads', error: e);
      }
    }
    if (!_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
    return true;
  }

  /// Settings → "Privacy options" (required by UMP when a form exists).
  Future<void> showPrivacyOptions(BuildContext context) async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error != null) dev.log('privacy options error', name: 'ads', error: error.message);
      if (!done.isCompleted) done.complete();
    });
    await done.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  Future<bool> get privacyOptionsRequired async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() == PrivacyOptionsRequirementStatus.required;
}
