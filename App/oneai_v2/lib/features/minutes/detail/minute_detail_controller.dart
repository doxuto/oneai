import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/settings/language_settings.dart';

// ---- Detail ----

final minuteDetailProvider =
    AsyncNotifierProvider.autoDispose.family<MinuteDetailController, MinuteDetail, String>(MinuteDetailController.new);

class MinuteDetailController extends AsyncNotifier<MinuteDetail> {
  MinuteDetailController(this.minuteId);
  final String minuteId;

  @override
  Future<MinuteDetail> build() => ref.read(minutesRepositoryProvider).get(minuteId);

  Future<void> refresh() async {
    state = AsyncValue<MinuteDetail>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => ref.read(minutesRepositoryProvider).get(minuteId));
  }

  /// Applies the server's speaker list to the loaded detail so every
  /// transcript segment re-labels at once.
  void applySpeakers(List<Speaker> speakers) {
    final d = state.valueOrNull;
    if (d == null) return;
    state = AsyncData(
      MinuteDetail(
        summaryInfo: d.summaryInfo,
        summary: d.summary,
        transcript: d.transcript,
        sourcePath: d.sourcePath,
        speakers: speakers,
        failure: d.failure,
        description: d.description,
        keywords: d.keywords,
        summaryLanguage: d.summaryLanguage,
      ),
    );
  }
}

// ---- Generated artifacts (short questions, quiz, flashcards, mind map, speakers) ----

/// One lazily generated, server-cached artifact. `build` asks without `force`
/// (a cache hit costs no LLM call); [regenerate] forces a fresh generation and
/// keeps the previous data visible while it runs.
abstract class ArtifactController<T> extends AsyncNotifier<Generated<T>> {
  ArtifactController(this.minuteId);
  final String minuteId;

  AiRepository get ai => ref.read(aiRepositoryProvider);
  String get languageCode => ref.read(aiLanguageCodeProvider);

  Future<Generated<T>> fetch({required bool force});

  @override
  Future<Generated<T>> build() => fetch(force: false);

  Future<void> regenerate() async {
    if (state.isLoading) return;
    state = AsyncValue<Generated<T>>.loading().copyWithPrevious(state);
    state = await AsyncValue.guard(() => fetch(force: true));
  }
}

class ShortQuestionsController extends ArtifactController<ShortQuestions> {
  ShortQuestionsController(super.minuteId);
  @override
  Future<Generated<ShortQuestions>> fetch({required bool force}) =>
      ai.shortQuestions(minuteId, languageCode: languageCode, force: force);
}

class QuizController extends ArtifactController<Quiz> {
  QuizController(super.minuteId);
  @override
  Future<Generated<Quiz>> fetch({required bool force}) => ai.quiz(minuteId, languageCode: languageCode, force: force);
}

class FlashcardsController extends ArtifactController<Flashcards> {
  FlashcardsController(super.minuteId);
  @override
  Future<Generated<Flashcards>> fetch({required bool force}) =>
      ai.flashcards(minuteId, languageCode: languageCode, force: force);
}

class MindmapController extends ArtifactController<Mindmap> {
  MindmapController(super.minuteId);
  @override
  Future<Generated<Mindmap>> fetch({required bool force}) => ai.mindmap(minuteId, languageCode: languageCode, force: force);
}

/// Speaker names: LLM-guessed once, then user-renamed. Renames go to the
/// server (no LLM call) and are pushed into the loaded detail too.
class SpeakersController extends ArtifactController<Speakers> {
  SpeakersController(super.minuteId);

  @override
  Future<Generated<Speakers>> fetch({required bool force}) => ai.mapSpeakers(minuteId, force: force);

  Future<bool> rename(String speakerId, String name) async {
    final n = name.trim();
    if (n.isEmpty) return false;
    try {
      final updated = await ai.renameSpeaker(minuteId, speakerId: speakerId, name: n);
      state = AsyncData(Generated(data: updated, cached: true));
      ref.read(minuteDetailProvider(minuteId).notifier).applySpeakers(updated.speakers);
      return true;
    } on Object catch (e, st) {
      state = AsyncError<Generated<Speakers>>(e, st).copyWithPrevious(state);
      return false;
    }
  }
}

final shortQuestionsProvider =
    AsyncNotifierProvider.autoDispose.family<ShortQuestionsController, Generated<ShortQuestions>, String>(ShortQuestionsController.new);
final quizProvider = AsyncNotifierProvider.autoDispose.family<QuizController, Generated<Quiz>, String>(QuizController.new);
final flashcardsProvider =
    AsyncNotifierProvider.autoDispose.family<FlashcardsController, Generated<Flashcards>, String>(FlashcardsController.new);
final mindmapProvider = AsyncNotifierProvider.autoDispose.family<MindmapController, Generated<Mindmap>, String>(MindmapController.new);
final speakersProvider = AsyncNotifierProvider.autoDispose.family<SpeakersController, Generated<Speakers>, String>(SpeakersController.new);
