import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/transcribe_models.dart';

void main() {
  test('wire names match the server enum (snake_case for 1:1)', () {
    expect(MinuteTemplate.values.map((t) => t.wire), ['auto', 'standup', 'one_on_one', 'interview', 'lecture', 'brainstorm']);
  });
  test('fromWire round-trips and falls back to auto', () {
    for (final t in MinuteTemplate.values) {
      expect(MinuteTemplate.fromWire(t.wire), t);
    }
    expect(MinuteTemplate.fromWire('retro'), MinuteTemplate.auto);
    expect(MinuteTemplate.fromWire(null), MinuteTemplate.auto);
  });
}
