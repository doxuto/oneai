// PURE spaced repetition (SM-2, the Anki family). No clock, no storage —
// both are passed in, which keeps every scheduling rule testable.

/// How well the learner recalled a card. Maps to SM-2 quality 1 / 3 / 4 / 5.
enum ReviewGrade { again, hard, good, easy }

class CardSchedule {
  const CardSchedule({this.repetitions = 0, this.intervalDays = 0, this.ease = 2.5, this.due});

  /// Consecutive successful reviews.
  final int repetitions;
  final int intervalDays;
  /// Easiness factor, never below 1.3.
  final double ease;
  /// Next review moment; null = never reviewed (due now).
  final DateTime? due;

  bool isDue(DateTime now) => due == null || !due!.isAfter(now);

  Map<String, Object?> toJson() => {'r': repetitions, 'i': intervalDays, 'e': ease, 'd': due?.toIso8601String()};

  static CardSchedule fromJson(Map<String, dynamic> j) => CardSchedule(
        repetitions: (j['r'] as num?)?.toInt() ?? 0,
        intervalDays: (j['i'] as num?)?.toInt() ?? 0,
        ease: (j['e'] as num?)?.toDouble() ?? 2.5,
        due: j['d'] is String ? DateTime.tryParse(j['d'] as String) : null,
      );
}

abstract final class Sm2 {
  static int qualityOf(ReviewGrade g) => switch (g) { ReviewGrade.again => 1, ReviewGrade.hard => 3, ReviewGrade.good => 4, ReviewGrade.easy => 5 };

  /// SM-2 with the usual practical tweaks: a lapse restarts at 1 day (not
  /// today) so a card is never shown twice in one session, and "easy"
  /// adds a small bonus on top of the ease factor.
  static CardSchedule review(CardSchedule s, ReviewGrade g, DateTime now) {
    final q = qualityOf(g);
    var ease = s.ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (ease < 1.3) ease = 1.3;
    int reps;
    int interval;
    if (q < 3) {
      reps = 0;
      interval = 1;
    } else {
      reps = s.repetitions + 1;
      interval = switch (reps) { 1 => 1, 2 => 6, _ => (s.intervalDays * ease).round().clamp(1, 3650) };
      if (g == ReviewGrade.easy) interval = (interval * 1.3).round();
      if (g == ReviewGrade.hard && reps > 2) interval = (s.intervalDays * 1.2).round().clamp(1, 3650);
    }
    final day = DateTime(now.year, now.month, now.day);
    return CardSchedule(repetitions: reps, intervalDays: interval, ease: ease, due: day.add(Duration(days: interval)));
  }

  /// Indices due now, unreviewed first (they are the freshest material),
  /// then by how overdue they are.
  static List<int> dueOrder(List<CardSchedule?> cards, DateTime now) {
    final due = <int>[
      for (var i = 0; i < cards.length; i++)
        if (cards[i] == null || cards[i]!.isDue(now)) i,
    ];
    due.sort((a, b) {
      final da = cards[a]?.due;
      final db = cards[b]?.due;
      if (da == null && db == null) return a.compareTo(b);
      if (da == null) return -1;
      if (db == null) return 1;
      return da.compareTo(db);
    });
    return due;
  }
}
