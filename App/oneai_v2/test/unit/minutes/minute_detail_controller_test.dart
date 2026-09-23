import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/data/repositories/minutes_repository.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/settings/language_settings.dart';

MinuteDetail detail({List<Speaker> speakers = const []}) => MinuteDetail(
      summaryInfo: MinuteSummary(
        id: 'm1',
        title: 'T',
        iconEmoji: null,
        sourceType: SourceType.audio,
        contentKind: null,
        status: MinuteStatus.ready,
        durationSeconds: 1,
        tagIds: const [],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      summary: null,
      transcript: null,
      sourcePath: null,
      speakers: speakers,
      failure: null,
      description: null,
      keywords: const [],
      summaryLanguage: null,
    );

class FakeMinutes implements MinutesRepository {
  int gets = 0;
  Object? getError;
  @override
  Future<MinuteDetail> get(String minuteId) async {
    gets++;
    if (getError != null) throw getError!;
    return detail(speakers: const [Speaker(id: 'speaker_0', label: 'Speaker 1')]);
  }

  @override
  Stream<List<MinuteSummary>> watchList(String uid, {int limit = 100}) => throw UnimplementedError();
  @override
  Stream<MinuteProgress> watchProgress(String uid, String minuteId) => throw UnimplementedError();
  @override
  Future<CreateMinuteResult> create({required SourceType sourceType, required String fileName, required int sizeBytes, required String contentType}) =>
      throw UnimplementedError();
  @override
  Future<MinutePage> list({int limit = 20, String? cursor, List<String>? tagIds, ListSort sort = ListSort.createdAtDesc}) =>
      throw UnimplementedError();
  @override
  Future<MinuteSummary> update(String minuteId, {String? title, String? iconEmoji, bool clearIconEmoji = false, List<String>? tagIds}) =>
      throw UnimplementedError();
  @override
  Future<void> delete(String minuteId) => throw UnimplementedError();
}

class FakeAi implements AiRepository {
  final calls = <String>[];
  Object? error;

  @override
  Future<Generated<ShortQuestions>> shortQuestions(String minuteId, {String languageCode = 'en', bool force = false}) async {
    calls.add('sq:$languageCode:$force');
    if (error != null) throw error!;
    return Generated(data: ShortQuestions(questions: ['q${calls.length}']), cached: !force);
  }

  @override
  Future<Generated<Speakers>> mapSpeakers(String minuteId, {bool force = false}) async {
    calls.add('map:$force');
    return const Generated(data: Speakers(speakers: [Speaker(id: 'speaker_0', label: 'Alice')]), cached: true);
  }

  @override
  Future<Speakers> renameSpeaker(String minuteId, {required String speakerId, required String name}) async {
    calls.add('rename:$speakerId:$name');
    if (error != null) throw error!;
    return Speakers(speakers: [Speaker(id: speakerId, label: name)]);
  }

  @override
  Future<Generated<Quiz>> quiz(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Flashcards>> flashcards(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Mindmap>> mindmap(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  ActionItems stored = const ActionItems(items: [ActionItem(id: 'a1', text: 'Thank Ana', owner: null, due: null, quote: 'q'), ActionItem(id: 'a2', text: 'Send notes', owner: null, due: null, quote: 'q')], decisions: []);
  @override
  Future<Generated<ActionItems>> actionItems(String minuteId, {String languageCode = 'en', bool force = false, String? timezone}) async {
    calls.add('ai:$force');
    return Generated(data: stored, cached: !force);
  }

  @override
  Future<Generated<ActionItems>> setActionItemDone(String minuteId, {required String itemId, required bool done}) async {
    calls.add('tick:$itemId:$done');
    if (error != null) throw error!;
    stored = stored.withDone(itemId, done);
    return Generated(data: stored, cached: true);
  }
  @override
  Future<Generated<KeyTerms>> keyTerms(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Chapters>> chapters(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<CalendarEvents>> calendarEvents(String minuteId, {String languageCode = 'en', bool force = false, String? timezone}) => throw UnimplementedError();
  @override
  Stream<ChatEvent> chat({required String minuteId, required String question, String languageCode = 'en'}) => throw UnimplementedError();
  @override
  Future<ChatPage> history(String minuteId, {int limit = 50, String? cursor}) => throw UnimplementedError();
}

class Harness {
  Harness() {
    container = ProviderContainer.test(overrides: [
      minutesRepositoryProvider.overrideWithValue(minutes),
      aiRepositoryProvider.overrideWithValue(ai),
      aiLanguageCodeProvider.overrideWithValue('vie'),
    ]);
    container
      ..listen(minuteDetailProvider('m1'), (_, __) {})
      ..listen(shortQuestionsProvider('m1'), (_, __) {})
      ..listen(speakersProvider('m1'), (_, __) {});
  }
  final minutes = FakeMinutes();
  final ai = FakeAi();
  late final ProviderContainer container;
}

void main() {
  test('detail loads once and refresh keeps the previous value while reloading', () async {
    final h = Harness();
    final d = await h.container.read(minuteDetailProvider('m1').future);
    expect(d.id, 'm1');
    expect(h.minutes.gets, 1);
    final refreshing = h.container.read(minuteDetailProvider('m1').notifier).refresh();
    expect(h.container.read(minuteDetailProvider('m1')).isLoading, isTrue);
    expect(h.container.read(minuteDetailProvider('m1')).valueOrNull?.id, 'm1');
    await refreshing;
    expect(h.minutes.gets, 2);
  });

  test('detail load failure is an AsyncError carrying the ApiFailure', () async {
    final h = Harness()..minutes.getError = const NotFoundFailure('gone');
    await expectLater(h.container.read(minuteDetailProvider('m1').future), throwsA(isA<NotFoundFailure>()));
  });

  test('artifact: first load does not force; regenerate forces and keeps old data while loading', () async {
    final h = Harness();
    final first = await h.container.read(shortQuestionsProvider('m1').future);
    expect(first.cached, isTrue);
    expect(h.ai.calls, ['sq:vie:false']);

    final regen = h.container.read(shortQuestionsProvider('m1').notifier).regenerate();
    final mid = h.container.read(shortQuestionsProvider('m1'));
    expect(mid.isLoading, isTrue);
    expect(mid.valueOrNull?.data.questions, first.data.questions);
    await regen;
    final second = h.container.read(shortQuestionsProvider('m1')).requireValue;
    expect(second.cached, isFalse);
    expect(h.ai.calls.last, 'sq:vie:true');
  });

  test('artifact: regenerate while loading is ignored', () async {
    final h = Harness();
    await h.container.read(shortQuestionsProvider('m1').future);
    final n = h.container.read(shortQuestionsProvider('m1').notifier);
    final a = n.regenerate();
    final b = n.regenerate();
    await Future.wait([a, b]);
    expect(h.ai.calls.where((c) => c == 'sq:vie:true').length, 1);
  });

  test('artifact: generation failure surfaces as error but keeps previous data', () async {
    final h = Harness();
    await h.container.read(shortQuestionsProvider('m1').future);
    h.ai.error = const QuotaFailure('ai cap', null);
    await h.container.read(shortQuestionsProvider('m1').notifier).regenerate();
    final s = h.container.read(shortQuestionsProvider('m1'));
    expect(s.hasError, isTrue);
    expect(s.error, isA<QuotaFailure>());
    expect(s.valueOrNull?.data.questions, ['q1']);
  });

  group('action items', () {
    test('tick is optimistic, then the server list replaces it', () async {
      final h = Harness();
      h.container.listen(actionItemsProvider('m1'), (_, __) {});
      await h.container.read(actionItemsProvider('m1').future);
      final fut = h.container.read(actionItemsProvider('m1').notifier).setDone('a2', true);
      expect(h.container.read(actionItemsProvider('m1')).requireValue.data.items[1].done, isTrue, reason: 'flipped before the call returns');
      expect(await fut, isTrue);
      expect(h.ai.calls.last, 'tick:a2:true');
      expect(h.container.read(actionItemsProvider('m1')).requireValue.data.items.map((i) => i.done), [false, true]);
    });

    test('tick failure rolls back and exposes the error', () async {
      final h = Harness();
      h.container.listen(actionItemsProvider('m1'), (_, __) {});
      await h.container.read(actionItemsProvider('m1').future);
      h.ai.error = const TransientFailure('boom');
      expect(await h.container.read(actionItemsProvider('m1').notifier).setDone('a1', true), isFalse);
      expect(h.container.read(actionItemsProvider('m1')).requireValue.data.items[0].done, isFalse);
      expect(h.container.read(actionItemsProvider('m1').notifier).lastTickError, isA<TransientFailure>());
    });
  });

  group('speakers', () {
    test('rename updates the artifact and the loaded detail', () async {
      final h = Harness();
      await h.container.read(minuteDetailProvider('m1').future);
      await h.container.read(speakersProvider('m1').future);
      final ok = await h.container.read(speakersProvider('m1').notifier).rename('speaker_0', '  Bob ');
      expect(ok, isTrue);
      expect(h.ai.calls.last, 'rename:speaker_0:Bob');
      expect(h.container.read(speakersProvider('m1')).requireValue.data.speakers.single.label, 'Bob');
      expect(h.container.read(minuteDetailProvider('m1')).requireValue.speakerLabelFor('speaker_0'), 'Bob');
    });

    test('blank name is refused without a call; server failure keeps old names', () async {
      final h = Harness();
      await h.container.read(speakersProvider('m1').future);
      expect(await h.container.read(speakersProvider('m1').notifier).rename('speaker_0', ' '), isFalse);
      h.ai.error = const TransientFailure('x');
      expect(await h.container.read(speakersProvider('m1').notifier).rename('speaker_0', 'Zed'), isFalse);
      final s = h.container.read(speakersProvider('m1'));
      expect(s.hasError, isTrue);
      expect(s.valueOrNull?.data.speakers.single.label, 'Alice');
      expect(h.ai.calls.where((c) => c.startsWith('rename:')).length, 1);
    });
  });
}
