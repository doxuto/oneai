import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:codebase_ai/ui/core/widgets/premium_status_builder.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Screen for uploading files for transcription and note generation
class UploadFileScreen extends StatefulWidget {
  /// Creates a new [UploadFileScreen] instance
  const UploadFileScreen({super.key});

  @override
  State<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends State<UploadFileScreen> {
  final SharedPreferencesService _preferencesService = SharedPreferencesService();
  Language _audioLanguage = Language.autodetect;
  Language _summaryLanguage = Language.autodetect;

  @override
  void initState() {
    super.initState();
    _loadLanguagesFromPreferences();
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
      // centerTitle: true,
      title: Text(
        context.loc.uploadFromFiles,
        style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      // leading: IconButton(
      //   icon: const Icon(Icons.close),
      //   onPressed: () => Navigator.pop(context),
      // ),
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.loc.selectFileDescription, style: context.textTheme.bodyLarge),
          gapH32,
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
          const Spacer(),
          _buildSelectFileButton(),
          gapH16,
        ],
      ),
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
      gapH16,
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
        Text(languageName, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.primary)),
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
                colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
              ),
            ),
            Transform.rotate(
              angle: 1.5 * 3.14159, // Rotate 270 degrees to make it point down
              child: SvgPicture.asset(
                Assets.arrowUpIcon,
                width: 12,
                height: 12,
                colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildSelectFileButton() => SizedBox(
    width: double.infinity,
    height: 56,
    child: PremiumStatusBuilder(
      builder:
          (context, status) => ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              premiumActionWrapper(context, status, () async {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
                );
                if (result != null && result.files.single.path != null) {
                  final audioPath = result.files.single.path!;
                  await context.push(
                    Routes.audioProcessing,
                    extra: {
                      'audioPath': audioPath,
                      'audioLanguage': _audioLanguage.name,
                      'summaryLanguage': _summaryLanguage.name,
                    },
                  );
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colorScheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
            child: Text(
              status != PremiumStatus.nonPremiumNoCredits
                  ? context.loc.selectFile
                  : 'Watch Ad to Transcribe',
              style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
            ),
          )
    ),
  );
}
