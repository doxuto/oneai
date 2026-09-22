import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bottom sheet for configuring prompt and language settings
class PromptLanguageSheet extends StatefulWidget {
  /// Creates a new [PromptLanguageSheet] instance
  const PromptLanguageSheet({
    super.key,
    this.initialAudioLanguage,
    this.initialSummaryLanguage,
    this.initialRecordingContext,
    this.initialKeywords,
  });

  final Language? initialAudioLanguage;
  final Language? initialSummaryLanguage;
  final String? initialRecordingContext;
  final String? initialKeywords;

  @override
  State<PromptLanguageSheet> createState() => _PromptLanguageSheetState();
}

class _PromptLanguageSheetState extends State<PromptLanguageSheet> {
  late final TextEditingController _recordingContextController;
  late final TextEditingController _keywordsController;
  late Language _audioLanguage;
  late Language _summaryLanguage;

  @override
  void initState() {
    super.initState();
    _audioLanguage = widget.initialAudioLanguage ?? Language.autodetect;
    _summaryLanguage = widget.initialSummaryLanguage ?? Language.autodetect;
    _recordingContextController = TextEditingController(text: widget.initialRecordingContext ?? '');
    _keywordsController = TextEditingController(text: widget.initialKeywords ?? '');
  }

  @override
  void dispose() {
    _recordingContextController.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.of(context).size.height * 0.9,
    child: Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: true,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRecordingContext(context),
                    gapH24,
                    _buildKeywords(context),
                    gapH24,
                    const Divider(color: Color(0xFFBDBDBD)),
                    gapH24,
                    _buildAudioLanguageSelector(context),
                    gapH24,
                    _buildSummaryLanguageSelector(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Stack(
      alignment: Alignment.center,
      children: [
        Align(
          child: Text(
            context.loc.promptAndLanguage,
            style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop({
                'audioLanguage': _audioLanguage,
                'summaryLanguage': _summaryLanguage,
                'recordingContext': _recordingContextController.text,
                'keywords': _keywordsController.text,
              });
            },
            child: Text(
              context.loc.done,
              style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.primary),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildRecordingContext(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.loc.whatAreYouRecording,
        style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      gapH8,
      Text(context.loc.recordingContextHint, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
      gapH16,
      TextField(
        controller: _recordingContextController,
        decoration: InputDecoration(
          hintText: context.loc.meetingTypeHint,
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    ],
  );

  Widget _buildKeywords(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.loc.keywords, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      gapH8,
      Text(context.loc.keywordsHint, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
      gapH16,
      TextField(
        controller: _keywordsController,
        decoration: InputDecoration(
          hintText: context.loc.keywordsPlaceholder,
          filled: true,
          fillColor: const Color(0xFFF5F5F5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    ],
  );

  Widget _buildLanguageSelectorButton(BuildContext context, String languageName) => Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(languageName, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.primary)),
        gapW8,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: 0.5 * 3.14159, // Rotate 90 degrees to make it point up
              child: SvgPicture.asset(Assets.arrowUpIcon, width: 12, height: 12),
            ),
            Transform.rotate(
              angle: 1.5 * 3.14159, // Rotate 270 degrees to make it point down
              child: SvgPicture.asset(Assets.arrowUpIcon, width: 12, height: 12),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildAudioLanguageSelector(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.loc.audioLanguage, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      gapH16,
      LanguageSelector(
        selectedLanguage: _audioLanguage,
        onLanguageSelected: (language) {
          setState(() {
            _audioLanguage = language;
          });
        },
        triggerButton: _buildLanguageSelectorButton(context, LanguageSelector.getLanguageName(context, _audioLanguage)),
      ),
    ],
  );

  Widget _buildSummaryLanguageSelector(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.loc.summaryLanguage, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      gapH16,
      LanguageSelector(
        selectedLanguage: _summaryLanguage,
        onLanguageSelected: (language) {
          setState(() {
            _summaryLanguage = language;
          });
        },
        triggerButton: _buildLanguageSelectorButton(
          context,
          LanguageSelector.getLanguageName(context, _summaryLanguage),
        ),
      ),
    ],
  );
}
