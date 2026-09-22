import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/config/app_config.dart';
import 'package:one_ai/core/config/firebase_options_prod.dart' as prod;

/// Composition root. Everything that must exist before the first frame goes
/// here, and it fails loudly rather than limping along with a half-built app.
///
/// Deliberately NOT here (v1 did both and blocked first paint twice):
///   - waiting for Remote Config
///   - waiting for the cold-start App Open ad
/// Both now resolve behind the UI; see docs/08-ADS-FLOW.md §6.
Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    developer.log(
      'flutter.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  final config = AppConfig.fromEnvironment();

  // One Firebase project per flavor. dev/staging options files are generated
  // by `flutterfire configure` once those projects exist (S0-06); until then
  // every flavor points at prod and dev work happens against the emulator.
  await Firebase.initializeApp(options: prod.DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    // Debug provider only outside prod, so a dev build never needs a real
    // attestation; prod uses App Attest / Play Integrity.
    appleProvider: config.isProd ? AppleProvider.appAttest : AppleProvider.debug,
    androidProvider: config.isProd ? AndroidProvider.playIntegrity : AndroidProvider.debug,
  );
  developer.log('app.bootstrap flavor=${config.flavor.name}', name: 'one_ai');

  runApp(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(config),
      ],
      child: builder(),
    ),
  );
}

/// Overridden in bootstrap; reading it without an override is a programming
/// error and throws, which is what we want.
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden in bootstrap()'),
);
