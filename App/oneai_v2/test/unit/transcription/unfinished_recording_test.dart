import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/recorder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('marker round-trips and loads only when the file is real', () async {
    final f = File('${Directory.systemTemp.path}/oneai_unfinished.m4a')..writeAsBytesSync(List.filled(20 * 1024, 1));
    SharedPreferences.setMockInitialValues({});
    await UnfinishedRecording.save(UnfinishedRecording(path: f.path, startedAt: DateTime(2026, 9, 24, 9), seconds: 95));
    final r = await UnfinishedRecording.load();
    expect(r, isNotNull);
    expect((r!.path, r.seconds), (f.path, 95));
    await UnfinishedRecording.clear();
    expect(await UnfinishedRecording.load(), isNull);
  });

  test('a missing or tiny file, or a 1-second clip, is dropped and the marker cleared', () async {
    SharedPreferences.setMockInitialValues({});
    await UnfinishedRecording.save(UnfinishedRecording(path: '${Directory.systemTemp.path}/nope.m4a', startedAt: DateTime(2026), seconds: 60));
    expect(await UnfinishedRecording.load(), isNull);
    final tiny = File('${Directory.systemTemp.path}/oneai_tiny.m4a')..writeAsBytesSync([1, 2, 3]);
    await UnfinishedRecording.save(UnfinishedRecording(path: tiny.path, startedAt: DateTime(2026), seconds: 60));
    expect(await UnfinishedRecording.load(), isNull);
    final ok = File('${Directory.systemTemp.path}/oneai_short.m4a')..writeAsBytesSync(List.filled(20 * 1024, 1));
    await UnfinishedRecording.save(UnfinishedRecording(path: ok.path, startedAt: DateTime(2026), seconds: 1));
    expect(await UnfinishedRecording.load(), isNull);
    expect((await SharedPreferences.getInstance()).getString(UnfinishedRecording.key), isNull);
  });

  test('fromJson tolerates junk', () {
    expect(UnfinishedRecording.fromJson('x'), isNull);
    expect(UnfinishedRecording.fromJson({'path': 1}), isNull);
  });
}
