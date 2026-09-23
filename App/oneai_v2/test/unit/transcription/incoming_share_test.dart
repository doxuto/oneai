import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/incoming_share.dart';

void main() {
  test('takes the first audio/video/PDF file and skips the rest', () {
    final s = pickIncomingShare([
      (path: '/tmp/notes.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
      (path: '/tmp/Meeting 12.m4a', mimeType: 'audio/mp4'),
      (path: '/tmp/b.mp3', mimeType: null),
    ]);
    expect(s?.path, '/tmp/Meeting 12.m4a');
    expect(s?.fileName, 'Meeting 12.m4a');
  });

  test('accepts by mime type when the extension is unknown', () {
    expect(pickIncomingShare([(path: '/tmp/rec.bin', mimeType: 'audio/x-caf')])?.path, '/tmp/rec.bin');
    expect(pickIncomingShare([(path: '/tmp/clip', mimeType: 'video/quicktime')]), isNotNull);
    expect(pickIncomingShare([(path: '/tmp/slides', mimeType: 'application/pdf')]), isNotNull);
  });

  test('accepts by extension when the mime type is missing, case-insensitive', () {
    expect(pickIncomingShare([(path: '/tmp/A.WAV', mimeType: null)]), isNotNull);
    expect(pickIncomingShare([(path: '/tmp/a.txt', mimeType: null)]), isNull);
    expect(pickIncomingShare(const []), isNull);
  });
}
