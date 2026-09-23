import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/repositories/transcription_repository.dart';

void main() {
  test('S11-09 part paths sit under source/parts next to the final file, zero-padded, same extension', () {
    expect(TranscriptionRepository.partPathFor('users/u/minutes/m/source/rec.m4a', 0), 'users/u/minutes/m/source/parts/part-000.m4a');
    expect(TranscriptionRepository.partPathFor('users/u/minutes/m/source/rec.m4a', 12), 'users/u/minutes/m/source/parts/part-012.m4a');
    expect(TranscriptionRepository.partPathFor('users/u/minutes/m/source/noext', 1), 'users/u/minutes/m/source/parts/part-001.m4a');
  });
}
