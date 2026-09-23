import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/features/tags/tag_chip.dart';
import 'package:one_ai/features/transcription/language_selector.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// What the sheet edits. Typed instead of v1's `Map<String, dynamic>`.
class PromptSettings {
  const PromptSettings({
    required this.audioLanguage,
    required this.summaryLanguage,
    this.description = '',
    this.keywords = '',
    this.template = MinuteTemplate.auto,
  });
  final TranscriptionLanguage audioLanguage;
  final TranscriptionLanguage summaryLanguage;
  final String description;
  final String keywords;
  final MinuteTemplate template;

  /// "a, b; c" → ["a", "b", "c"], ≤20 as the server allows.
  List<String> get keywordList => keywords.split(RegExp(r'[,;\n]')).map((k) => k.trim()).where((k) => k.isNotEmpty).take(20).toList();

  PromptSettings copyWith({TranscriptionLanguage? audioLanguage, TranscriptionLanguage? summaryLanguage, String? description, String? keywords, MinuteTemplate? template}) =>
      PromptSettings(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        summaryLanguage: summaryLanguage ?? this.summaryLanguage,
        description: description ?? this.description,
        keywords: keywords ?? this.keywords,
        template: template ?? this.template,
      );
}

/// v1 PromptLanguageSheet, verbatim layout. Resolves with the edited settings
/// on Done, null when dismissed.
class PromptLanguageSheet extends StatefulWidget {
  const PromptLanguageSheet({required this.initial, super.key});
  final PromptSettings initial;

  static Future<PromptSettings?> show(BuildContext context, PromptSettings initial) => showModalBottomSheet<PromptSettings>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PromptLanguageSheet(initial: initial),
      );

  @override
  State<PromptLanguageSheet> createState() => _PromptLanguageSheetState();
}

class _PromptLanguageSheetState extends State<PromptLanguageSheet> {
  late MinuteTemplate _template = widget.initial.template;
  late final TextEditingController _description = TextEditingController(text: widget.initial.description);

  static String _templateLabel(AppLocalizations l10n, MinuteTemplate t) => switch (t) {
        MinuteTemplate.auto => l10n.templateAuto,
        MinuteTemplate.standup => l10n.templateStandup,
        MinuteTemplate.oneOnOne => l10n.templateOneOnOne,
        MinuteTemplate.interview => l10n.templateInterview,
        MinuteTemplate.lecture => l10n.templateLecture,
        MinuteTemplate.brainstorm => l10n.templateBrainstorm,
      };
  late final TextEditingController _keywords = TextEditingController(text: widget.initial.keywords);
  late TranscriptionLanguage _audio = widget.initial.audioLanguage;
  late TranscriptionLanguage _summary = widget.initial.summaryLanguage;

  @override
  void dispose() {
    _description.dispose();
    _keywords.dispose();
    super.dispose();
  }

  InputDecoration _filled(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final titleStyle = context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final hintStyle = context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(child: Text(l10n.promptAndLanguage, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).pop(PromptSettings(
                            audioLanguage: _audio,
                            summaryLanguage: _summary,
                            description: _description.text.trim(),
                            keywords: _keywords.text.trim(),
                            template: _template,
                          ));
                        },
                        child: Text(l10n.done, style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.primary)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.whatAreYouRecording, style: titleStyle),
                      gapH8,
                      Text(l10n.recordingContextHint, style: hintStyle),
                      gapH16,
                      // S11-08 template chips: same idle/selected colours as the
                      // Home tag chips so they read as the same control.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in MinuteTemplate.values)
                            TagChip(
                              label: _templateLabel(l10n, t),
                              selected: _template == t,
                              onTap: () { HapticFeedback.selectionClick(); setState(() => _template = t); },
                            ),
                        ],
                      ),
                      gapH16,
                      TextField(controller: _description, maxLength: 500, decoration: _filled(l10n.meetingTypeHint)),
                      gapH24,
                      Text(l10n.keywords, style: titleStyle),
                      gapH8,
                      Text(l10n.keywordsHint, style: hintStyle),
                      gapH16,
                      TextField(controller: _keywords, decoration: _filled(l10n.keywordsPlaceholder)),
                      gapH24,
                      const Divider(color: AppColors.dividerGrey),
                      gapH24,
                      Text(l10n.audioLanguage, style: titleStyle),
                      gapH16,
                      LanguageSelector(
                        selected: _audio,
                        onSelected: (l) => setState(() => _audio = l),
                        trigger: LanguageTriggerButton(label: LanguageSelector.nameOf(context, _audio)),
                      ),
                      gapH24,
                      Text(l10n.summaryLanguage, style: titleStyle),
                      gapH16,
                      LanguageSelector(
                        selected: _summary,
                        choices: TranscriptionLanguage.summaryChoices,
                        onSelected: (l) => setState(() => _summary = l),
                        trigger: LanguageTriggerButton(label: LanguageSelector.nameOf(context, _summary)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
