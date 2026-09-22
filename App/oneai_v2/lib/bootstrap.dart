import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/config/app_config.dart';

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
  developer.log('app.bootstrap', name: 'one_ai', error: null);

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
