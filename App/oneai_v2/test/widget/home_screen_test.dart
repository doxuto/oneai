import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';
import 'package:one_ai/features/minutes/home/home_screen.dart';
import 'package:one_ai/features/transcription/upload_queue.dart';

import 'harness.dart';

MinuteSummary m(String id, {String? title, bool pinned = false, MinuteStatus status = MinuteStatus.ready}) => MinuteSummary(
      id: id, title: title ?? id, iconEmoji: null, sourceType: SourceType.audio, contentKind: null, status: status,
      durationSeconds: 95, tagIds: const [], createdAt: DateTime(2026, 9, 1), updatedAt: DateTime(2026, 9, 1), pinned: pinned,
    );

List<Override> homeOverrides({required List<MinuteSummary> minutes, List<Tag> tags = const [], bool premium = false}) => [
      currentUidProvider.overrideWithValue('u1'),
      minutesListProvider.overrideWith((_) => Stream.value(minutes)),
      tagsListProvider.overrideWith((_) => Stream.value(tags)),
      isPremiumProvider.overrideWith((_) => Stream.value(premium)),
      quotaProvider.overrideWith((_) => Stream.value(null)),
      onlineProvider.overrideWith((_) => Stream.value(true)),
      // The queue talks to storage + flows; an empty, inert one is enough here.
      uploadQueueProvider.overrideWith(() => _EmptyQueue()),
    ];

class _EmptyQueue extends UploadQueue {
  @override
  List<Never> build() => const [];
}

void main() {
  testWidgets('empty state when there are no notes', (tester) async {
    await pumpScreen(tester, const HomeScreen(), overrides: homeOverrides(minutes: const []));
    await tester.pumpAndSettle();
    expect(find.text('My Notes'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await expectAccessible(tester);
  });

  testWidgets('renders one card per note, pinned first, and the pin icon', (tester) async {
    await pumpScreen(tester, const HomeScreen(), overrides: homeOverrides(minutes: [m('a', title: 'Alpha'), m('b', title: 'Beta', pinned: true)]));
    await tester.pumpAndSettle();
    final alpha = tester.getTopLeft(find.text('Alpha'));
    final beta = tester.getTopLeft(find.text('Beta'));
    expect(beta.dy, lessThan(alpha.dy), reason: 'pinned note sorts first');
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    await expectAccessible(tester);
  });

  testWidgets('search narrows the list and shows the no-results state', (tester) async {
    await pumpScreen(tester, const HomeScreen(), overrides: homeOverrides(minutes: [m('a', title: 'Họp sprint'), m('b', title: 'Lecture 3')]));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hop');
    await tester.pumpAndSettle();
    expect(find.text('Họp sprint'), findsOneWidget);
    expect(find.text('Lecture 3'), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No notes match your search.'), findsOneWidget);
  });

  testWidgets('a processing note shows its status, not a duration', (tester) async {
    await pumpScreen(tester, const HomeScreen(), overrides: homeOverrides(minutes: [m('p', title: 'Pending', status: MinuteStatus.transcribing)]));
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('01:35'), findsNothing);
  });
}
