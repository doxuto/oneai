import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:codebase_ai/ui/core/widgets/premium_status_builder.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Screen for uploading YouTube videos for transcription and note generation
class YouTubeVideoScreen extends StatefulWidget {
  /// Creates a new [YouTubeVideoScreen] instance
  const YouTubeVideoScreen({super.key});

  @override
  State<YouTubeVideoScreen> createState() => _YouTubeVideoScreenState();
}

class _YouTubeVideoScreenState extends State<YouTubeVideoScreen> {
  final SharedPreferencesService _preferencesService = SharedPreferencesService();
  Language _audioLanguage = Language.autodetect;
  Language _summaryLanguage = Language.autodetect;
  final TextEditingController _linkController = TextEditingController();
  bool get _canTranscribe => _linkController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLanguagesFromPreferences();
    _linkController.addListener(() {
      if (mounted) {
        setState(() {
          // This empty setState will rebuild the UI when text changes
        });
      }
    });
  }

  Future<void> _loadLanguagesFromPreferences() async {
    final audioResult = await _preferencesService.getAudioLanguage();
    final summaryResult = await _preferencesService.getSummaryLanguage();
    setState(() {
      if (audioResult != null) {
        _audioLanguage = Language.values.byName(audioResult);
      }
      if (summaryResult != null) {
        _summaryLanguage = Language.values.byName(summaryResult);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Text(
        context.loc.youtubeVideoNotes,
        style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste a YouTube link for transcript & notes:',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: Colors.black87,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    gapH16,
                    _buildLinkInputField(),
                    gapH24,
                    _buildLanguageSection(
                      title: context.loc.audioLanguage,
                      language: _audioLanguage,
                      onLanguageSelected: (language) {
                        setState(() {
                          _audioLanguage = language;
                        });
                      },
                    ),
                    gapH24,
                    _buildLanguageSection(
                      title: context.loc.summaryLanguage,
                      language: _summaryLanguage,
                      onLanguageSelected: (language) {
                        setState(() {
                          _summaryLanguage = language;
                        });
                      },
                    ),
                    gapH48,
                  ],
                ),
              ),
            ),
            _buildUnsupportedFormatsNote(),
            gapH24,
            _buildTranscribeButton(),
          ],
        ),
      ),
    ),
  );

  Widget _buildLinkInputField() => Container(
    height: 56,
    decoration: BoxDecoration(color: const Color(0xFFF6F6F6), borderRadius: BorderRadius.circular(8)),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _linkController,
            decoration: InputDecoration(
              hintText: 'https://...',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              hintStyle: context.textTheme.bodyMedium?.copyWith(color: Colors.grey),
              fillColor: const Color(0xFFF6F6F6),
              filled: true,
            ),
          ),
        ),
        Container(
          height: 56,
          padding: const EdgeInsets.all(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: InkWell(
              onTap: () async {
                await HapticFeedback.lightImpact();
                // Implement paste functionality
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                if (data != null && data.text != null) {
                  setState(() {
                    _linkController.text = data.text!;
                  });
                }
              },
              child: Row(
                children: [
                  SvgPicture.asset(
                    Assets.pasteOutlineIcon,
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
                  ),
                  gapW8,
                  Text(
                    context.loc.tapToPaste,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: context.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildLanguageSection({
    required String title,
    required Language language,
    required ValueChanged<Language> onLanguageSelected,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      gapH12,
      LanguageSelector(
        selectedLanguage: language,
        onLanguageSelected: onLanguageSelected,
        triggerButton: _buildLanguageSelectorButton(context, LanguageSelector.getLanguageName(context, language)),
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
        Text(languageName, style: context.textTheme.bodyMedium?.copyWith(color: Colors.blue)),
        gapW8,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: 0.5 * 3.14159, // Rotate 90 degrees to make it point up
              child: SvgPicture.asset(
                Assets.arrowUpIcon,
                width: 12,
                height: 12,
                colorFilter: const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
              ),
            ),
            Transform.rotate(
              angle: 1.5 * 3.14159, // Rotate 270 degrees to make it point down
              child: SvgPicture.asset(
                Assets.arrowUpIcon,
                width: 12,
                height: 12,
                colorFilter: const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildUnsupportedFormatsNote() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          children: [
            TextSpan(
              text: context.loc.youtubeShortsPrefixText,
              style: context.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            TextSpan(
              text: context.loc.youtubeUnsupportedFormatsLinkText,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
              recognizer:
                  TapGestureRecognizer()
                    ..onTap = () {
                      HapticFeedback.lightImpact();
                      context.push(Routes.uploadFile);
                    },
            ),
            TextSpan(
              text: context.loc.youtubeUnsupportedFormatsPeriod,
              style: context.textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildTranscribeButton() => SizedBox(
    width: double.infinity,
    height: 56,
    child: PremiumStatusBuilder(
      builder:
          (context, status) => ElevatedButton(
            onPressed:
                _canTranscribe
                    ? () async {
                      await HapticFeedback.lightImpact();
                      await premiumActionWrapper(context, status, () async {
                        await context.push(
                          Routes.audioProcessing,
                          extra: {
                            'youtubeLink': _linkController.text.trim(),
                            'audioLanguage': _audioLanguage.name,
                            'summaryLanguage': _summaryLanguage.name,
                          },
                        );
                      });
                    }
                    : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(
              status != PremiumStatus.nonPremiumNoCredits
                  ? context.loc.transcribeAndSummarize
                  : 'Watch Ad to Transcribe',
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          )
    ),
  );
}
