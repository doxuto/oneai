import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/features/study/sm2.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device review schedule for one note's flashcards, keyed by the card's
/// question text (stable across regenerations that keep a card; a reworded
/// card simply starts fresh). Server sync is a later step.
class ReviewStore {
  static String keyFor(String minuteId) => 'FLASHCARD_REVIEW_V2_$minuteId';

  Future<Map<String, CardSchedule>> load(String minuteId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(keyFor(minuteId));
      if (raw == null) return {};
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {for (final e in j.entries) if (e.value is Map) e.key.toString(): CardSchedule.fromJson(Map<String, dynamic>.from(e.value as Map))};
    } on Object catch (_) {
      return {};
    }
  }

  Future<void> save(String minuteId, Map<String, CardSchedule> m) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(keyFor(minuteId), jsonEncode({for (final e in m.entries) e.key: e.value.toJson()}));
    } on Object catch (_) {}
  }
}

final reviewStoreProvider = Provider<ReviewStore>((_) => ReviewStore());
final clockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Schedules for one note, loaded once; [grade] persists after each answer.
class ReviewSchedules extends AsyncNotifier<Map<String, CardSchedule>> {
  ReviewSchedules(this.minuteId);
  final String minuteId;

  @override
  Future<Map<String, CardSchedule>> build() => ref.read(reviewStoreProvider).load(minuteId);

  Future<void> grade(String question, ReviewGrade g) async {
    final cur = Map<String, CardSchedule>.from(state.valueOrNull ?? const {});
    cur[question] = Sm2.review(cur[question] ?? const CardSchedule(), g, ref.read(clockProvider)());
    state = AsyncData(cur);
    await ref.read(reviewStoreProvider).save(minuteId, cur);
  }

  Future<void> reset() async {
    state = const AsyncData({});
    await ref.read(reviewStoreProvider).save(minuteId, const {});
  }
}

final reviewSchedulesProvider = AsyncNotifierProvider.autoDispose.family<ReviewSchedules, Map<String, CardSchedule>, String>(ReviewSchedules.new);
