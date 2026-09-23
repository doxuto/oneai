import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/tag_models.dart';

// ---- Live data ----

/// Newest first, live. A note created on another device or a status change
/// from the worker appears without a refresh (v1 polled and paginated).
final minutesListProvider = StreamProvider<List<MinuteSummary>>(
  (ref) => ref.watch(minutesRepositoryProvider).watchList(ref.watch(currentUidProvider)),
);

final tagsListProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagsRepositoryProvider).watch(ref.watch(currentUidProvider)),
);

// ---- Tag filter (v1 semantics: multi-select, AND) ----

final selectedTagIdsProvider = NotifierProvider<SelectedTagIds, Set<String>>(SelectedTagIds.new);

class SelectedTagIds extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    // A tag deleted on the server must not keep filtering everything out.
    ref.listen(tagsListProvider, (_, next) {
      final live = next.valueOrNull;
      if (live == null) return;
      final ids = live.map((t) => t.id).toSet();
      final kept = state.where(ids.contains).toSet();
      if (kept.length != state.length) state = kept;
    });
    return const {};
  }

  void toggle(String tagId) =>
      state = state.contains(tagId) ? (state.toSet()..remove(tagId)) : (state.toSet()..add(tagId));

  void clear() => state = const {};
}

/// Pure so it can be tested and reused by the tag sheet.
List<MinuteSummary> filterMinutes(List<MinuteSummary> all, Set<String> selected, {Set<String> hidden = const {}}) {
  if (selected.isEmpty && hidden.isEmpty) return all;
  return [
    for (final m in all)
      if (!hidden.contains(m.id) && selected.every(m.tagIds.contains)) m,
  ];
}

/// What the list renders: live minutes, tag filter applied, minus rows whose
/// deletion is in flight (so a tap on "delete" removes the card instantly).
final visibleMinutesProvider = Provider<AsyncValue<List<MinuteSummary>>>((ref) {
  final selected = ref.watch(selectedTagIdsProvider);
  final hidden = ref.watch(minuteActionsProvider).deleting;
  return ref.watch(minutesListProvider).whenData((all) => filterMinutes(all, selected, hidden: hidden));
});

// ---- Mutations ----

class MinuteActionsState {
  const MinuteActionsState({this.deleting = const {}, this.lastError});
  final Set<String> deleting;
  final Object? lastError;

  MinuteActionsState copyWith({Set<String>? deleting, Object? lastError = _keep}) => MinuteActionsState(
        deleting: deleting ?? this.deleting,
        lastError: identical(lastError, _keep) ? this.lastError : lastError,
      );
}

const Object _keep = Object();

final minuteActionsProvider = NotifierProvider<MinuteActions, MinuteActionsState>(MinuteActions.new);

class MinuteActions extends Notifier<MinuteActionsState> {
  @override
  MinuteActionsState build() => const MinuteActionsState();

  /// Optimistic: the row disappears now; on failure it comes back with an
  /// error to show. Returns whether the server confirmed.
  Future<bool> delete(String minuteId) async {
    if (state.deleting.contains(minuteId)) return false;
    state = state.copyWith(deleting: {...state.deleting, minuteId}, lastError: null);
    try {
      await ref.read(minutesRepositoryProvider).delete(minuteId);
      // Keep it hidden: the Firestore stream drops the doc a moment later and
      // the id can stay in `deleting` harmlessly — but release it so a note
      // re-created with the same id (never happens; ids are random) is not
      // masked forever.
      state = state.copyWith(deleting: state.deleting.difference({minuteId}));
      return true;
    } on Object catch (e) {
      dev.log('deleteMinute failed', name: 'minutes', error: e);
      state = state.copyWith(deleting: state.deleting.difference({minuteId}), lastError: e);
      return false;
    }
  }

  Future<bool> rename(String minuteId, String title) => _mutate(() async {
        final t = title.trim();
        if (t.isEmpty) throw ArgumentError('title is empty');
        await ref.read(minutesRepositoryProvider).update(minuteId, title: t);
      });

  Future<bool> setTags(String minuteId, List<String> tagIds) =>
      _mutate(() => ref.read(minutesRepositoryProvider).update(minuteId, tagIds: tagIds));

  Future<bool> setIcon(String minuteId, String? emoji) => _mutate(
        () => ref.read(minutesRepositoryProvider).update(minuteId, iconEmoji: emoji, clearIconEmoji: emoji == null),
      );

  void clearError() => state = state.copyWith(lastError: null);

  Future<bool> _mutate(Future<void> Function() op) async {
    state = state.copyWith(lastError: null);
    try {
      await op();
      return true;
    } on Object catch (e) {
      dev.log('minute mutation failed', name: 'minutes', error: e);
      state = state.copyWith(lastError: e);
      return false;
    }
  }
}
