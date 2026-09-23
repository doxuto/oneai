import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/notifications/push_registrar.dart';

final notificationPrefsProvider = AsyncNotifierProvider<NotificationPrefsController, NotificationPrefs>(NotificationPrefsController.new);

/// Server-side preference (`users/{uid}.notifications`), seeded from getMe.
class NotificationPrefsController extends AsyncNotifier<NotificationPrefs> {
  @override
  Future<NotificationPrefs> build() async => (await ref.watch(meProvider.future)).user.notifications;

  Future<void> setTranscriptionDone(bool on) async {
    final previous = state.valueOrNull ?? const NotificationPrefs();
    state = AsyncData(NotificationPrefs(transcriptionDone: on));
    try {
      final saved = await ref.read(pushRepositoryProvider).updatePrefs(transcriptionDone: on);
      state = AsyncData(saved);
      // Turning it on is the natural moment to ask the OS, if never asked.
      if (on) await ref.read(pushRegistrarProvider.notifier).requestPermission();
    } on Object catch (e, st) {
      state = AsyncError<NotificationPrefs>(e, st).copyWithPrevious(AsyncData(previous));
    }
  }
}
