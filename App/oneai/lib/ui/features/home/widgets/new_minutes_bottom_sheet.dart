import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// A bottom sheet for creating new minutes with different options
class NewMinutesBottomSheet extends StatefulWidget {
  /// Creates a new instance of [NewMinutesBottomSheet]
  const NewMinutesBottomSheet({super.key});

  @override
  State<NewMinutesBottomSheet> createState() => _NewMinutesBottomSheetState();
}

class _NewMinutesBottomSheetState extends State<NewMinutesBottomSheet> {
  Language _selectedLanguage = Language.autodetect;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        gapH16,
        _buildOptionButton(
          context,
          icon: Assets.voiceIcon,
          label: context.loc.startAudioRecording,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            context.push(Routes.recordAudio);
          },
        ),
        gapH12,
        _buildOptionButton(
          context,
          icon: Assets.galleryIcon,
          label: context.loc.uploadFromFiles,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            context.push(Routes.uploadFile);
          },
        ),
        gapH12,
        _buildOptionButton(
          context,
          icon: Assets.youtubeVideoIcon,
          label: context.loc.youTubeVideo,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
            context.push(Routes.youtubeVideo);
          },
        ),
        gapH24,
      ],
    ),
  );

  Widget _buildHeader(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(context.loc.newNote, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      Row(
        children: [
          // LanguageSelector(
          //   selectedLanguage: _selectedLanguage,
          //   onLanguageSelected: (language) {
          //     setState(() {
          //       _selectedLanguage = language;
          //     });
          //   },
          //   triggerButton: OutlinedButton(
          //     onPressed: null,
          //     style: OutlinedButton.styleFrom(
          //       side: BorderSide(color: context.colorScheme.outline),
          //       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          //       minimumSize: const Size(0, 36),
          //       padding: const EdgeInsets.symmetric(horizontal: 12),
          //     ),
          //     child: Text(LanguageSelector.getLanguageName(context, _selectedLanguage)),
          //   ),
          // ),
          // gapW8,
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SvgPicture.asset(Assets.closeIcon, width: 24, height: 24),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _buildOptionButton(
    BuildContext context, {
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) => Material(
    color: const Color(0xFFEBF3FF),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            SvgPicture.asset(icon, width: 26, height: 26),
            gapW16,
            Text(label, style: context.textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}
