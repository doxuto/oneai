import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/translation_sheet.dart';

class FakeAi implements AiRepository {
  final calls = <String>[];
  Object? error;
  @override
  Stream<TranslateEvent> translate({required String minuteId, required TranslatePart part, required String languageCode, bool force = false}) async* {
    calls.add('${part.name}:$languageCode:$force');
    if (error != null) throw error!;
    yield const TranslateDelta('Xin ');
    yield const TranslateDelta('chào');
    yield TranslateDone(Translation(part: part.name, languageCode: languageCode, text: 'Xin chào', cached: false));
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  const key = (minuteId: 'm1', part: TranslatePart.summary, languageCode: 'vie');

  test('deltas accumulate, done replaces with the server text', () async {
    final ai = FakeAi();
    final c = ProviderContainer.test(overrides: [aiRepositoryProvider.overrideWithValue(ai)]);
    final seen = <String>[];
    c.listen(translationProvider(key), (_, next) => seen.add('${next.text}|${next.streaming}|${next.done}'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(ai.calls, ['summary:vie:false']);
    expect(seen.last, 'Xin chào|false|true');
    expect(seen, contains('Xin |true|false'));
  });

  test('error stops streaming and is exposed; start() retries', () async {
    final ai = FakeAi()..error = const TransientFailure('x');
    final c = ProviderContainer.test(overrides: [aiRepositoryProvider.overrideWithValue(ai)]);
    c.listen(translationProvider(key), (_, __) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(translationProvider(key)).error, isA<TransientFailure>());
    expect(c.read(translationProvider(key)).streaming, isFalse);
    ai.error = null;
    await c.read(translationProvider(key).notifier).start(force: true);
    await Future<void>.delayed(Duration.zero);
    expect(ai.calls.last, 'summary:vie:true');
    expect(c.read(translationProvider(key)).done, isTrue);
  });
}
