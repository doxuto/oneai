import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/failure_text.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/translation_sheet.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/tags/tag_chip.dart';
import 'package:one_ai/features/transcription/language_selector.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// A7-04 / S11-11 — bilingual reading. The chosen target language is
/// remembered per note for the session (both tabs share it), so a student
/// can flip "Original ↔ Vietnamese" on the transcript and the notes alike.
final translateToProvider = NotifierProvider.autoDispose.family<TranslateTo, TranscriptionLanguage?, String>(TranslateTo.new);

class TranslateTo extends Notifier<TranscriptionLanguage?> {
  TranslateTo(this.minuteId);
  final String minuteId;
  @override
  TranscriptionLanguage? build() => null;
  void set(TranscriptionLanguage? l) => state = l;
}

/// Chip row: "Original" · "<Language> ▾". When a language is picked the
/// caller renders [TranslatedBody] instead of its native widgets.
class TranslateToggle extends ConsumerWidget {
  const TranslateToggle({required this.minuteId, super.key});
  final String minuteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final target = ref.watch(translateToProvider(minuteId));
    final defaultTarget = () {
      final s = ref.read(languageSettingsProvider).summaryLanguage;
      return s == TranscriptionLanguage.auto ? TranscriptionLanguage.english : s;
    }();
    return Row(
      children: [
        TagChip(label: l10n.original, selected: target == null, onTap: () { HapticFeedback.selectionClick(); ref.read(translateToProvider(minuteId).notifier).set(null); }),
        gapW8,
        LanguageSelector(
          selected: target ?? defaultTarget,
          choices: TranscriptionLanguage.summaryChoices,
          onSelected: (l) { HapticFeedback.selectionClick(); ref.read(translateToProvider(minuteId).notifier).set(l); },
          trigger: TagChip(
            label: '${(target ?? defaultTarget).englishName} ▾',
            selected: target != null,
            onTap: () { HapticFeedback.selectionClick(); ref.read(translateToProvider(minuteId).notifier).set(target ?? defaultTarget); },
          ),
        ),
      ],
    );
  }
}

/// Streams the translation of [part] into the chosen language. Reuses the
/// cached server translation, so flipping back and forth costs nothing.
class TranslatedBody extends ConsumerWidget {
  const TranslatedBody({required this.minuteId, required this.part, required this.language, super.key});
  final String minuteId;
  final TranslatePart part;
  final TranscriptionLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (minuteId: minuteId, part: part, languageCode: language.code);
    final st = ref.watch(translationProvider(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (st.error != null) ...[
          Text(failureText(context, st.error), style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
          TextButton(onPressed: () => ref.read(translationProvider(key).notifier).start(), child: Text(context.l10n.retry, style: const TextStyle(color: AppColors.brandBlueAlt))),
        ],
        if (st.text.isEmpty && st.streaming) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2))),
        SelectableText(st.text, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black, height: 1.5)),
        if (st.streaming && st.text.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      ],
    );
  }
}
