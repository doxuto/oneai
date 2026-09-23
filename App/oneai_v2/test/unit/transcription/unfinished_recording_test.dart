import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/transcription/recorder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('marker round-trips and loads only when the file is real', () async {
    final f = File('${Directory.systemTemp.path}/oneai_unfinished.m4a')..writeAsBytesSync(List.filled(20 * 1024, 1));
    SharedPreferences.setMockInitialValues({});
    await UnfinishedRecording.save(UnfinishedRecording(paths: [f.path], startedAt: DateTime(2026, 9, 24, 9), seconds: 95));
    final r = await UnfinishedRecording.load();
    expect(r, isNotNull);
    expect((r!.path, r.seconds), (f.path, 95));
    await UnfinishedRecording.clear();
    expect(await UnfinishedRecording.load(), isNull);
  });

  test('a missing or tiny file, or a 1-second clip, is dropped and the marker cleared', () async {
    SharedPreferences.setMockInitialValues({});
    await UnfinishedRecording.save(UnfinishedRecording(paths: ['${Directory.systemTemp.path}/nope.m4a'], startedAt: DateTime(2026), seconds: 60));
    expect(await UnfinishedRecording.load(), isNull);
    final tiny = File('${Directory.systemTemp.path}/oneai_tiny.m4a')..writeAsBytesSync([1, 2, 3]);
    await UnfinishedRecording.save(UnfinishedRecording(paths: [tiny.path], startedAt: DateTime(2026), seconds: 60));
    expect(await UnfinishedRecording.load(), isNull);
    final ok = File('${Directory.systemTemp.path}/oneai_short.m4a')..writeAsBytesSync(List.filled(20 * 1024, 1));
    await UnfinishedRecording.save(UnfinishedRecording(paths: [ok.path], startedAt: DateTime(2026), seconds: 1));
    expect(await UnfinishedRecording.load(), isNull);
    expect((await SharedPreferences.getInstance()).getString(UnfinishedRecording.key), isNull);
  });

  test('fromJson tolerates junk and still reads the pre-chunk single-path shape', () {
    expect(UnfinishedRecording.fromJson('x'), isNull);
    expect(UnfinishedRecording.fromJson({'path': 1}), isNull);
    expect(UnfinishedRecording.fromJson({'paths': [], 'startedAt': '2026-01-01T00:00:00'}), isNull);
    final old = UnfinishedRecording.fromJson({'path': '/a.m4a', 'startedAt': '2026-01-01T00:00:00', 'seconds': 5});
    expect(old?.paths, ['/a.m4a']);
  });

  test('S11-09 chunks: a truncated last chunk is dropped, complete ones are recovered in order', () async {
    SharedPreferences.setMockInitialValues({});
    final a = File('${Directory.systemTemp.path}/oneai_c0.m4a')..writeAsBytesSync(List.filled(20 * 1024, 1));
    final b = File('${Directory.systemTemp.path}/oneai_c1.m4a')..writeAsBytesSync(List.filled(20 * 1024, 2));
    final open = File('${Directory.systemTemp.path}/oneai_c2.m4a')..writeAsBytesSync([0, 0, 0]);
    await UnfinishedRecording.save(UnfinishedRecording(paths: [a.path, b.path, open.path], startedAt: DateTime(2026), seconds: 640));
    final r = await UnfinishedRecording.load();
    expect(r?.usableFiles().map((f) => f.path), [a.path, b.path]);
    expect(r?.path, open.path);
  });
}
