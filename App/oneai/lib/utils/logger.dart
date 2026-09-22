import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Configures the root logger with appropriate level and handlers
///
/// Sets up logging to output to console in debug mode with the following format:
/// timestamp: level: logger name: message
/// Additionally outputs errors and stack traces if available
void configureLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      debugPrint('${record.time}: ${record.level.name}: ${record.loggerName}: ${record.message}');
      if (record.error != null) {
        debugPrint('Error: ${record.error}');
      }
      if (record.stackTrace != null) {
        debugPrint('Stack trace: ${record.stackTrace}');
      }
    }
  });
}
