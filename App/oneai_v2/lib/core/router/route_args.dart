import 'package:one_ai/features/transcription/new_minute_flow.dart';

/// Typed `extra` payloads. v1 passed untyped maps; a typo there was a runtime
/// null. Screens read these through `GoRouterState.extra as …`.
class AudioProcessingArgs {
  const AudioProcessingArgs({required this.request});
  final NewMinuteRequest request;
}

class SummaryArgs {
  const SummaryArgs({required this.minuteId, this.initialTab = 0, this.seekSeconds});
  final String minuteId;
  /// 0 summary · 1 transcript · 2 chat
  final int initialTab;
  /// S11-01b: open the player at this moment (an ask-all citation).
  final double? seekSeconds;

  /// From a notification tap or a `/transcriptionSummary?minuteId=` link.
  static SummaryArgs? from(Object? extra, Map<String, String> query) {
    if (extra is SummaryArgs) return extra;
    if (extra is Map && extra['minuteId'] is String) return SummaryArgs(minuteId: extra['minuteId'] as String);
    final q = query['minuteId'];
    return q == null ? null : SummaryArgs(minuteId: q);
  }
}
