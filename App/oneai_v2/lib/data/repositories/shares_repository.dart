import 'dart:convert';
import 'dart:io';

import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/minute_models.dart';

/// A note someone shared by link, as the public `sharePage?format=json`
/// endpoint returns it (no auth — the token is the credential).
class SharedNote {
  const SharedNote({required this.token, required this.title, required this.iconEmoji, required this.createdAt, required this.sourceType, required this.summary, required this.transcript, required this.speakers, required this.pdfUrl});
  factory SharedNote.fromJson(Map<String, dynamic> j) {
    final s = readObject(j, 'summary');
    final t = readObject(j, 'transcript');
    return SharedNote(
      token: readRequiredString(j, 'token'),
      title: readString(j, 'title') ?? 'Untitled',
      iconEmoji: readString(j, 'iconEmoji'),
      createdAt: readString(j, 'createdAt') ?? '',
      sourceType: SourceType.from(j, 'sourceType'),
      summary: s == null ? null : Summary.fromJson(s),
      transcript: t == null ? null : Transcript.fromJson(t),
      speakers: readObjectList(j, 'speakers').map(Speaker.fromJson).toList(),
      pdfUrl: readString(j, 'pdfUrl') ?? '',
    );
  }
  final String token;
  final String title;
  final String? iconEmoji;
  final String createdAt;
  final SourceType sourceType;
  final Summary? summary;
  final Transcript? transcript;
  final List<Speaker> speakers;
  final String pdfUrl;

  String speakerLabelFor(String id) => speakers.where((s) => s.id == id).map((s) => s.label).firstOrNull ?? id;
}

class ImportResult {
  const ImportResult({required this.minuteId, required this.duplicate});
  final String minuteId;
  final bool duplicate;
}

class SharesRepository {
  SharesRepository({required FunctionsClient functions, required this.shareBaseUrl, HttpClient? http})
      : _fns = functions,
        _http = http ?? HttpClient();
  final FunctionsClient _fns;
  /// Same base the server puts in share links (`…/s` on Hosting or the function URL).
  final String shareBaseUrl;
  final HttpClient _http;

  /// Public read; 404 → [NotFoundFailure] (revoked / deleted).
  Future<SharedNote> fetch(String token) async {
    final uri = Uri.parse('$shareBaseUrl${shareBaseUrl.contains('?') ? '&' : '?'}t=$token&format=json');
    final req = await _http.getUrl(uri);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 404) throw const NotFoundFailure('This link is no longer available');
    if (res.statusCode != 200) throw TransientFailure('share fetch ${res.statusCode}');
    return SharedNote.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// "Save to my notes": copies summary (+ transcript when shared) into the
  /// caller's account. No quota — nothing is transcribed.
  Future<ImportResult> import(String token) async {
    final j = await _fns.call('importSharedNote', {'token': token});
    return ImportResult(minuteId: readRequiredString(j, 'minuteId'), duplicate: readBool(j, 'duplicate'));
  }
}
