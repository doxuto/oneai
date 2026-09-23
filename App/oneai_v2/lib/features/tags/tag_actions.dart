import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/tag_models.dart';

class TagActionsState {
  const TagActionsState({this.busy = false, this.lastError});
  final bool busy;
  final Object? lastError;
}

final tagActionsProvider = NotifierProvider<TagActions, TagActionsState>(TagActions.new);

/// Tag mutations. The live list (`tagsListProvider`) updates itself through
/// Firestore, so nothing here touches local state beyond busy/error.
class TagActions extends Notifier<TagActionsState> {
  @override
  TagActionsState build() => const TagActionsState();

  Future<Tag?> create(String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    return _run(() => ref.read(tagsRepositoryProvider).create(n));
  }

  Future<Tag?> rename(String tagId, String name) async {
    final n = name.trim();
    if (n.isEmpty) return null;
    return _run(() => ref.read(tagsRepositoryProvider).rename(tagId, n));
  }

  /// Returns how many notes lost the tag, or null on failure.
  Future<int?> delete(String tagId) => _run(() => ref.read(tagsRepositoryProvider).delete(tagId));

  void clearError() => state = const TagActionsState();

  Future<T?> _run<T>(Future<T> Function() op) async {
    state = const TagActionsState(busy: true);
    try {
      final r = await op();
      state = const TagActionsState();
      return r;
    } on Object catch (e) {
      dev.log('tag action failed', name: 'tags', error: e);
      state = TagActionsState(lastError: e);
      return null;
    }
  }
}
