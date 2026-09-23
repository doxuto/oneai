import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/minutes/share/export.dart';

/// v1's five share options.
enum ShareOption { notesAsPdf, notesAsText, transcriptAsPdf, transcriptAsText, audioFile, copyLink, revokeLink }

/// Implemented in A5 (export.dart). Defined here so the summary screen's
/// menu compiles without the export code.
abstract interface class MinuteSharer {
  Future<void> share(BuildContext context, MinuteDetail detail, ShareOption option);
}

class NoopSharer implements MinuteSharer {
  const NoopSharer();
  @override
  Future<void> share(BuildContext context, MinuteDetail detail, ShareOption option) async {}
}

final minuteSharerProvider = Provider<MinuteSharer>((ref) => ShareSheetSharer(ref));
