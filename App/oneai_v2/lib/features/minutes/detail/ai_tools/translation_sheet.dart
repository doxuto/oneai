import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/failure_text.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/tags/tag_chip.dart';
import 'package:one_ai/features/transcription/language_selector.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// Key for one translation: which part of which note into which language.
typedef TranslationKey = ({String minuteId, TranslatePart part, String languageCode});

class TranslationState {
  const TranslationState({this.text = '', this.streaming = false, this.done = false, this.error});
  final String text;
  final bool streaming;
  final bool done;
  final Object? error;
  TranslationState copyWith({String? text, bool? streaming, bool? done, Object? error = _keep}) => TranslationState(
        text: text ?? this.text,
        streaming: streaming ?? this.streaming,
        done: done ?? this.done,
        error: identical(error, _keep) ? this.error : error,
      );
  static const _keep = Object();
}

/// Streams a translation into [TranslationState.text]; the server caches the
/// full text, so re-opening the same (part, language) returns at once.
class TranslationController extends Notifier<TranslationState> {
  TranslationController(this.key);
  final TranslationKey key;
  StreamSubscription<TranslateEvent>? _sub;

  @override
  TranslationState build() {
    ref.onDispose(() => _sub?.cancel());
    Future<void>.microtask(() => start());
    return const TranslationState();
  }

  Future<void> start({bool force = false}) async {
    await _sub?.cancel();
    state = const TranslationState(streaming: true);
    _sub = ref
        .read(aiRepositoryProvider)
        .translate(minuteId: key.minuteId, part: key.part, languageCode: key.languageCode, force: force)
        .listen(
      (ev) {
        switch (ev) {
          case TranslateDelta(:final text):
            state = state.copyWith(text: state.text + text);
          case TranslateDone(:final translation):
            state = state.copyWith(text: translation.text, streaming: false, done: true);
        }
      },
      onError: (Object e) => state = state.copyWith(streaming: false, error: e),
      onDone: () { if (!state.done) state = state.copyWith(streaming: false); },
    );
  }
}

final translationProvider = NotifierProvider.autoDispose.family<TranslationController, TranslationState, TranslationKey>(TranslationController.new);

/// S11-04 sheet: part toggle (Summary / Transcript), target language picker
/// (same list as the summary language), streaming text, copy.
class TranslationSheet extends ConsumerStatefulWidget {
  const TranslationSheet({required this.minuteId, super.key});
  final String minuteId;

  static Future<void> show(BuildContext context, String minuteId) => ToolSheet.present(context, TranslationSheet(minuteId: minuteId));

  @override
  ConsumerState<TranslationSheet> createState() => _TranslationSheetState();
}

class _TranslationSheetState extends ConsumerState<TranslationSheet> {
  TranslatePart _part = TranslatePart.summary;
  late TranscriptionLanguage _lang = _initialLanguage();

  TranscriptionLanguage _initialLanguage() {
    final s = ref.read(languageSettingsProvider).summaryLanguage;
    return s == TranscriptionLanguage.auto ? TranscriptionLanguage.english : s;
  }

  TranslationKey get _key => (minuteId: widget.minuteId, part: _part, languageCode: _lang.code);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final st = ref.watch(translationProvider(_key));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.translate, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                  if (st.done)
                    IconButton(
                      icon: const Icon(Icons.copy, color: AppColors.brandBlueAlt),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: st.text));
                        if (context.mounted) AppSnack.show(context, l10n.copied);
                      },
                    ),
                  InkWell(onTap: () => Navigator.pop(context), borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(Assets.closeIcon, width: 24, height: 24))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TagChip(label: l10n.summaryTab, selected: _part == TranslatePart.summary, onTap: () => setState(() => _part = TranslatePart.summary)),
                  gapW8,
                  TagChip(label: l10n.transcript, selected: _part == TranslatePart.transcript, onTap: () => setState(() => _part = TranslatePart.transcript)),
                  const Spacer(),
                  LanguageSelector(
                    selected: _lang,
                    choices: TranscriptionLanguage.summaryChoices,
                    onSelected: (l) => setState(() => _lang = l),
                    trigger: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_lang.englishName, style: const TextStyle(color: AppColors.brandBlueAlt, fontWeight: FontWeight.w500)),
                      const Icon(Icons.arrow_drop_down, color: AppColors.brandBlueAlt),
                    ]),
                  ),
                ],
              ),
            ),
            gapH12,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (st.error != null) ...[
                      Text(failureText(context, st.error), style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
                      TextButton(onPressed: () => ref.read(translationProvider(_key).notifier).start(), child: Text(l10n.retry, style: const TextStyle(color: AppColors.brandBlueAlt))),
                    ],
                    if (st.text.isEmpty && st.streaming) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 2))),
                    SelectableText(st.text, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black, height: 1.5)),
                    if (st.streaming && st.text.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
