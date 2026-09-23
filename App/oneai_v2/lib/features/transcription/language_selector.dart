import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// v1 LanguageSelector: a popup menu over the language list with dividers,
/// "(Selected)" on the current one, and whatever trigger the caller passes.
class LanguageSelector extends StatelessWidget {
  const LanguageSelector({
    required this.selected,
    required this.onSelected,
    required this.trigger,
    super.key,
    this.choices,
  });
  final TranscriptionLanguage selected;
  final ValueChanged<TranscriptionLanguage> onSelected;
  final Widget trigger;
  /// Defaults to every language; summary pickers pass `summaryChoices`.
  final List<TranscriptionLanguage>? choices;

  static String nameOf(BuildContext context, TranscriptionLanguage l) =>
      l == TranscriptionLanguage.auto ? context.l10n.autoDetect : l.englishName;

  @override
  Widget build(BuildContext context) {
    final list = choices ?? TranscriptionLanguage.values;
    return PopupMenuButton<TranscriptionLanguage>(
      initialValue: selected,
      onSelected: onSelected,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (context) => [
        for (final (i, l) in list.indexed) ...[
          PopupMenuItem<TranscriptionLanguage>(
            value: l,
            height: 42,
            child: Row(children: [Text(nameOf(context, l)), if (selected == l) ...[const Spacer(), Text(' (${context.l10n.selected})')]]),
          ),
          if (i < list.length - 1)
            const PopupMenuItem<TranscriptionLanguage>(height: 1, enabled: false, padding: EdgeInsets.zero, child: Divider(color: AppColors.dividerGrey, height: 1)),
        ],
      ],
      child: trigger,
    );
  }
}

/// v1's grey pill trigger with the up/down chevrons.
class LanguageTriggerButton extends StatelessWidget {
  const LanguageTriggerButton({required this.label, super.key, this.tintArrows = false});
  final String label;
  final bool tintArrows;

  @override
  Widget build(BuildContext context) {
    final tint = tintArrows ? ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn) : null;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.primary)),
          gapW8,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.rotate(angle: 0.5 * 3.14159, child: SvgPicture.asset(Assets.arrowUpIcon, width: 12, height: 12, colorFilter: tint)),
              Transform.rotate(angle: 1.5 * 3.14159, child: SvgPicture.asset(Assets.arrowUpIcon, width: 12, height: 12, colorFilter: tint)),
            ],
          ),
        ],
      ),
    );
  }
}
