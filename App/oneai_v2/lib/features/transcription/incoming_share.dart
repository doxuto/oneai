import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// A file another app handed to One AI through the OS share sheet
/// (iOS Share Extension / Android ACTION_SEND). See PLATFORM-SETUP.md.
class IncomingShare {
  const IncomingShare({required this.path, this.mimeType});
  final String path;
  final String? mimeType;

  String get fileName => path.split('/').last;
}

/// Same list as the in-app file picker (UploadFileScreen) — the server rejects
/// anything else anyway, so a shared .docx is dropped here with no navigation.
const acceptedShareExtensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'pdf'};

/// Picks the first usable file out of one share event. Pure so it is testable
/// without the plugin: `null` when nothing shared is audio/video/PDF.
IncomingShare? pickIncomingShare(Iterable<({String path, String? mimeType})> files) {
  for (final f in files) {
    final ext = f.path.split('.').last.toLowerCase();
    final mime = f.mimeType ?? '';
    if (acceptedShareExtensions.contains(ext) || mime.startsWith('audio/') || mime.startsWith('video/') || mime == 'application/pdf') {
      return IncomingShare(path: f.path, mimeType: f.mimeType);
    }
  }
  return null;
}

/// Emits once per share, for a cold start (the app was launched by the share
/// sheet) and while running. `reset()` after reading so the same share is not
/// replayed on the next subscription.
final incomingShareProvider = StreamProvider<IncomingShare>((ref) async* {
  final rsi = ReceiveSharingIntent.instance;
  final initial = pickIncomingShare(await rsi.getInitialMedia().then(_asRecords));
  if (initial != null) {
    rsi.reset();
    yield initial;
  }
  await for (final files in rsi.getMediaStream()) {
    final share = pickIncomingShare(_asRecords(files));
    if (share != null) yield share;
  }
});

List<({String path, String? mimeType})> _asRecords(List<SharedMediaFile> files) =>
    [for (final f in files) (path: f.path, mimeType: f.mimeType)];

/// A share that arrived while the user was signed out (or before the router was
/// ready) waits here; UploadFileScreen picks it up when it opens.
class PendingIncomingShare extends Notifier<IncomingShare?> {
  @override
  IncomingShare? build() => null;
  void set(IncomingShare? s) => state = s;

  /// Returns the pending share and clears it.
  IncomingShare? take() {
    final s = state;
    state = null;
    return s;
  }
}

final pendingIncomingShareProvider = NotifierProvider<PendingIncomingShare, IncomingShare?>(PendingIncomingShare.new);
