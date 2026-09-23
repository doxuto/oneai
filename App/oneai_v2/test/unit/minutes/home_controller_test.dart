import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/data/repositories/minutes_repository.dart';
import 'package:one_ai/data/repositories/tags_repository.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';

MinuteSummary m(String id, {List<String> tags = const [], String? title, String? preview, bool pinned = false, DateTime? pinnedAt}) => MinuteSummary(
      id: id,
      title: title ?? id,
      pinned: pinned,
      pinnedAt: pinnedAt,
      transcriptPreview: preview,
      iconEmoji: null,
      sourceType: SourceType.audio,
      contentKind: null,
      status: MinuteStatus.ready,
      durationSeconds: 1,
      tagIds: tags,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Tag tag(String id) => Tag(id: id, name: id, minuteCount: 0, createdAt: DateTime(2026));

class FakeMinutes implements MinutesRepository {
  final list = StreamController<List<MinuteSummary>>.broadcast();
  final calls = <String>[];
  Object? deleteError;
  Object? updateError;

  final limits = <int>[];
  @override
  Stream<List<MinuteSummary>> watchList(String uid, {int limit = 100}) {
    limits.add(limit);
    return list.stream;
  }
  @override
  Future<ShareInfo> createShareLink(String minuteId, {bool includeTranscript = false}) => throw UnimplementedError();
  @override
  Future<void> revokeShareLink(String minuteId) => throw UnimplementedError();
  @override
  Future<void> delete(String minuteId) async {
    calls.add('delete:$minuteId');
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<MinuteSummary> update(String minuteId, {String? title, String? iconEmoji, bool clearIconEmoji = false, List<String>? tagIds}) async {
    calls.add('update:$minuteId:${title ?? ''}:${iconEmoji ?? ''}:$clearIconEmoji:${tagIds?.join(',') ?? ''}');
    if (updateError != null) throw updateError!;
    return m(minuteId);
  }

  @override
  Stream<MinuteProgress> watchProgress(String uid, String minuteId) => throw UnimplementedError();
  @override
  Future<CreateMinuteResult> create({required SourceType sourceType, required String fileName, required int sizeBytes, required String contentType}) =>
      throw UnimplementedError();
  @override
  Future<MinutePage> list({int limit = 20, String? cursor, List<String>? tagIds, ListSort sort = ListSort.createdAtDesc}) =>
      throw UnimplementedError();
  @override
  Future<MinuteDetail> get(String minuteId) => throw UnimplementedError();
}

class FakeTags implements TagsRepository {
  final tags = StreamController<List<Tag>>.broadcast();
  @override
  Stream<List<Tag>> watch(String uid) => tags.stream;
  @override
  Future<Tag> create(String name) => throw UnimplementedError();
  @override
  Future<List<Tag>> list() => throw UnimplementedError();
  @override
  Future<Tag> rename(String tagId, String name) => throw UnimplementedError();
  @override
  Future<int> delete(String tagId) => throw UnimplementedError();
}

class Harness {
  Harness() {
    container = ProviderContainer.test(overrides: [
      currentUidProvider.overrideWithValue('u1'),
      minutesRepositoryProvider.overrideWithValue(minutes),
      tagsRepositoryProvider.overrideWithValue(tags),
    ]);
    container
      ..listen(visibleMinutesProvider, (_, __) {})
      ..listen(tagsListProvider, (_, __) {})
      ..listen(selectedTagIdsProvider, (_, __) {});
  }
  final minutes = FakeMinutes();
  final tags = FakeTags();
  late final ProviderContainer container;

  List<MinuteSummary>? get visible => container.read(visibleMinutesProvider).valueOrNull;
  Set<String> get selected => container.read(selectedTagIdsProvider);
  SelectedTagIds get selection => container.read(selectedTagIdsProvider.notifier);
  MinuteActions get actions => container.read(minuteActionsProvider.notifier);
}

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('filterMinutes', () {
    final all = [m('a', tags: ['t1', 't2']), m('b', tags: ['t1']), m('c')];
    test('no selection returns the same list instance', () {
      expect(identical(filterMinutes(all, const {}), all), isTrue);
    });
    test('AND across selected tags, like v1', () {
      expect(filterMinutes(all, {'t1'}).map((x) => x.id), ['a', 'b']);
      expect(filterMinutes(all, {'t1', 't2'}).map((x) => x.id), ['a']);
      expect(filterMinutes(all, {'t3'}), isEmpty);
    });
    test('hidden ids are removed even with no selection', () {
      expect(filterMinutes(all, const {}, hidden: {'b'}).map((x) => x.id), ['a', 'c']);
    });
    test('pinned notes come first, most recently pinned on top; others keep stream order', () {
      final list = [m('x'), m('p1', pinned: true, pinnedAt: DateTime(2026, 1, 1)), m('y'), m('p2', pinned: true, pinnedAt: DateTime(2026, 2, 1))];
      expect(filterMinutes(list, const {}).map((x) => x.id), ['p2', 'p1', 'x', 'y']);
    });
  });

  group('search', () {
    final list = [
      m('a', title: 'Họp sprint planning', preview: 'chốt scope release'),
      m('b', title: 'Lecture 3', preview: 'photosynthesis and chlorophyll'),
      m('c', title: 'Standup'),
    ];
    test('matches title or preview, case- and diacritic-insensitive', () {
      expect(filterMinutes(list, const {}, query: 'hop').map((x) => x.id), ['a']);
      expect(filterMinutes(list, const {}, query: 'CHLOROPHYLL').map((x) => x.id), ['b']);
      expect(filterMinutes(list, const {}, query: 'scope').map((x) => x.id), ['a']);
    });
    test('every term must match; blank query is a no-op', () {
      expect(filterMinutes(list, const {}, query: 'sprint release').map((x) => x.id), ['a']);
      expect(filterMinutes(list, const {}, query: 'sprint photo'), isEmpty);
      expect(identical(filterMinutes(list, const {}, query: ''), list), isTrue);
      expect(matchesQuery(list[2], '   '), isTrue);
    });
    test('combines with the tag filter', () {
      final tagged = [m('a', tags: ['t1'], title: 'Họp'), m('b', title: 'Họp')];
      expect(filterMinutes(tagged, {'t1'}, query: 'hop').map((x) => x.id), ['a']);
    });
  });

  group('load more (OQ-17)', () {
    test('a full window means more; grow re-subscribes with a bigger limit', () async {
      final h = Harness();
      h.container.listen(hasMoreMinutesProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      h.minutes.list.add([for (var i = 0; i < 100; i++) m('n$i')]);
      await Future<void>.delayed(Duration.zero);
      expect(h.container.read(hasMoreMinutesProvider), isTrue);
      expect(h.minutes.limits, [100]);
      h.container.read(minutesWindowProvider.notifier).grow();
      await Future<void>.delayed(Duration.zero);
      expect(h.minutes.limits, [100, 200]);
      h.minutes.list.add([for (var i = 0; i < 150; i++) m('n$i')]);
      await Future<void>.delayed(Duration.zero);
      expect(h.container.read(hasMoreMinutesProvider), isFalse, reason: '150 < 200 → nothing older');
    });
  });

  group('selection', () {
    test('toggle adds then removes; clear empties', () async {
      final h = Harness();
      h.selection.toggle('t1');
      h.selection.toggle('t2');
      expect(h.selected, {'t1', 't2'});
      h.selection.toggle('t1');
      expect(h.selected, {'t2'});
      h.selection.clear();
      expect(h.selected, isEmpty);
    });

    test('a tag deleted on the server is dropped from the selection', () async {
      final h = Harness();
      h.tags.tags.add([tag('t1'), tag('t2')]);
      await settle();
      h.selection.toggle('t1');
      h.selection.toggle('t2');
      h.tags.tags.add([tag('t2')]);
      await settle();
      expect(h.selected, {'t2'});
    });
  });

  group('visibleMinutesProvider', () {
    test('applies the live filter', () async {
      final h = Harness();
      h.minutes.list.add([m('a', tags: ['t1']), m('b')]);
      await settle();
      expect(h.visible!.map((x) => x.id), ['a', 'b']);
      h.selection.toggle('t1');
      await settle();
      expect(h.visible!.map((x) => x.id), ['a']);
    });
  });

  group('delete', () {
    test('hides the row immediately, then releases once confirmed', () async {
      final h = Harness();
      h.minutes.list.add([m('a'), m('b')]);
      await settle();
      final done = h.actions.delete('a');
      await settle();
      expect(h.visible!.map((x) => x.id), ['b']);
      expect(await done, isTrue);
      // The stream drops it afterwards, as Firestore would.
      h.minutes.list.add([m('b')]);
      await settle();
      expect(h.visible!.map((x) => x.id), ['b']);
      expect(h.minutes.calls, ['delete:a']);
    });

    test('server failure brings the row back with an error', () async {
      final h = Harness()..minutes.deleteError = const TransientFailure('x');
      h.minutes.list.add([m('a')]);
      await settle();
      expect(await h.actions.delete('a'), isFalse);
      await settle();
      expect(h.visible!.map((x) => x.id), ['a']);
      expect(h.container.read(minuteActionsProvider).lastError, isA<TransientFailure>());
      h.actions.clearError();
      expect(h.container.read(minuteActionsProvider).lastError, isNull);
    });

    test('double tap does not delete twice', () async {
      final h = Harness();
      final a = h.actions.delete('a');
      final b = h.actions.delete('a');
      expect(await b, isFalse);
      await a;
      expect(h.minutes.calls, ['delete:a']);
    });
  });

  group('rename / tags / icon', () {
    test('rename trims and refuses blank', () async {
      final h = Harness();
      expect(await h.actions.rename('a', '  New  '), isTrue);
      expect(h.minutes.calls, ['update:a:New::false:']);
      expect(await h.actions.rename('a', '   '), isFalse);
      expect(h.minutes.calls.length, 1);
    });
    test('setTags and setIcon (null clears)', () async {
      final h = Harness();
      await h.actions.setTags('a', ['t1', 't2']);
      await h.actions.setIcon('a', '🎧');
      await h.actions.setIcon('a', null);
      expect(h.minutes.calls, ['update:a:::false:t1,t2', 'update:a::🎧:false:', 'update:a:::true:']);
    });
    test('update failure is reported and returns false', () async {
      final h = Harness()..minutes.updateError = const NotFoundFailure('gone');
      expect(await h.actions.setTags('a', []), isFalse);
      expect(h.container.read(minuteActionsProvider).lastError, isA<NotFoundFailure>());
    });
  });
}
