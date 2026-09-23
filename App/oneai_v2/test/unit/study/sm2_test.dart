import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/study/sm2.dart';

void main() {
  final now = DateTime(2026, 9, 24, 15);
  DateTime day(int d) => DateTime(2026, 9, 24).add(Duration(days: d));

  test('first two good reviews go 1 day then 6 days, then ease-scaled', () {
    var s = Sm2.review(const CardSchedule(), ReviewGrade.good, now);
    expect((s.repetitions, s.intervalDays, s.due), (1, 1, day(1)));
    s = Sm2.review(s, ReviewGrade.good, now);
    expect((s.repetitions, s.intervalDays), (2, 6));
    s = Sm2.review(s, ReviewGrade.good, now);
    expect(s.repetitions, 3);
    expect(s.intervalDays, (6 * s.ease).round());
    expect(s.due, day(s.intervalDays));
  });

  test('again resets repetitions to a 1-day interval and lowers ease, never below 1.3', () {
    var s = const CardSchedule(repetitions: 4, intervalDays: 30, ease: 1.35);
    s = Sm2.review(s, ReviewGrade.again, now);
    expect((s.repetitions, s.intervalDays, s.ease), (0, 1, 1.3));
    expect(s.isDue(now), isFalse, reason: 'not shown again today by the schedule (the session re-queues it itself)');
    expect(s.isDue(day(1)), isTrue);
  });

  test('easy stretches the interval and raises ease; hard shortens it', () {
    final base = const CardSchedule(repetitions: 3, intervalDays: 10, ease: 2.5);
    final easy = Sm2.review(base, ReviewGrade.easy, now);
    final good = Sm2.review(base, ReviewGrade.good, now);
    final hard = Sm2.review(base, ReviewGrade.hard, now);
    expect(easy.intervalDays, greaterThan(good.intervalDays));
    expect(hard.intervalDays, lessThan(good.intervalDays));
    expect(easy.ease, greaterThan(base.ease));
    expect(hard.ease, lessThan(base.ease));
  });

  test('dueOrder: unreviewed first, then most overdue; future cards excluded', () {
    final cards = <CardSchedule?>[
      CardSchedule(due: day(-3)), // overdue
      null, // never reviewed
      CardSchedule(due: day(2)), // not yet
      CardSchedule(due: day(-1)),
    ];
    expect(Sm2.dueOrder(cards, now), [1, 0, 3]);
  });

  test('schedule JSON round-trips', () {
    final s = CardSchedule(repetitions: 2, intervalDays: 6, ease: 2.36, due: day(6));
    expect(CardSchedule.fromJson(Map<String, dynamic>.from(s.toJson())).toJson(), s.toJson());
    expect(CardSchedule.fromJson(const {}).ease, 2.5);
  });
}
