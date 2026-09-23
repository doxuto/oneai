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

/// Every usable file out of one share event, in the order shared (S11-06b:
/// several at once). Pure so it is testable without the plugin.
List<IncomingShare> pickIncomingShares(Iterable<({String path, String? mimeType})> files) => [
      for (final f in files)
        if (_accepted(f)) IncomingShare(path: f.path, mimeType: f.mimeType),
    ];

/// The first usable file, `null` when nothing shared is audio/video/PDF.
IncomingShare? pickIncomingShare(Iterable<({String path, String? mimeType})> files) {
  final all = pickIncomingShares(files);
  return all.isEmpty ? null : all.first;
}

bool _accepted(({String path, String? mimeType}) f) {
  final ext = f.path.split('.').last.toLowerCase();
  final mime = f.mimeType ?? '';
  return acceptedShareExtensions.contains(ext) || mime.startsWith('audio/') || mime.startsWith('video/') || mime == 'application/pdf';
}

/// Emits once per share, for a cold start (the app was launched by the share
/// sheet) and while running. `reset()` after reading so the same share is not
/// replayed on the next subscription.
final incomingShareProvider = StreamProvider<List<IncomingShare>>((ref) async* {
  final rsi = ReceiveSharingIntent.instance;
  final initial = pickIncomingShares(await rsi.getInitialMedia().then(_asRecords));
  if (initial.isNotEmpty) {
    rsi.reset();
    yield initial;
  }
  await for (final files in rsi.getMediaStream()) {
    final shares = pickIncomingShares(_asRecords(files));
    if (shares.isNotEmpty) yield shares;
  }
});

List<({String path, String? mimeType})> _asRecords(List<SharedMediaFile> files) =>
    [for (final f in files) (path: f.path, mimeType: f.mimeType)];

/// Shares waiting to be processed: the ones that arrived while signed out (or
/// before the router was ready) and, for a multi-file share, the files after
/// the first. UploadFileScreen takes one at a time; Home shows the rest.
class PendingIncomingShares extends Notifier<List<IncomingShare>> {
  @override
  List<IncomingShare> build() => const [];
  void addAll(List<IncomingShare> s) => state = [...state, ...s];

  /// Returns the next pending share and removes it.
  IncomingShare? takeFirst() {
    if (state.isEmpty) return null;
    final s = state.first;
    state = state.sublist(1);
    return s;
  }

  void clear() => state = const [];
}

final pendingIncomingSharesProvider = NotifierProvider<PendingIncomingShares, List<IncomingShare>>(PendingIncomingShares.new);
