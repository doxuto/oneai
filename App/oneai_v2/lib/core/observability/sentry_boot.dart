import 'package:one_ai/core/config/app_config.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Sentry wraps runApp so uncaught errors in every zone are reported.
/// Nothing is sent from a dev build (empty DSN disables the SDK).
abstract final class SentryBoot {
  static Future<void> run(AppConfig config, Future<void> Function() appRunner) => SentryFlutter.init(
        (o) {
          o.dsn = config.flavor == Flavor.dev ? '' : config.sentryDsn;
          o.environment = config.flavor.name;
          o.tracesSampleRate = config.sentryTracesSampleRate;
          o.debug = config.verboseSdkLogging;
          o.sendDefaultPii = false;
          o.attachScreenshot = false;
        },
        appRunner: appRunner,
      );
}
