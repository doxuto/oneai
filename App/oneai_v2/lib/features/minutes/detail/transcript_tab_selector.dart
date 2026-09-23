import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';

enum TranscriptTab { minutes, transcript, chat }

/// v1 TranscriptTabSelector, verbatim.
class TranscriptTabSelector extends StatelessWidget {
  const TranscriptTabSelector({required this.selected, required this.onSelected, super.key});
  final TranscriptTab selected;
  final ValueChanged<TranscriptTab> onSelected;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _button(context, TranscriptTab.minutes, context.l10n.summaryTab, Assets.listIcon),
          _button(context, TranscriptTab.transcript, context.l10n.transcriptTab, Assets.commentIcon),
          _button(context, TranscriptTab.chat, context.l10n.chatTab, Assets.commentLightIcon),
        ],
      );

  Widget _button(BuildContext context, TranscriptTab tab, String label, String icon) {
    final isSelected = selected == tab;
    final bg = isSelected ? AppColors.brandBlueAlt : const Color(0xFFE6F0FF);
    final fg = isSelected ? Colors.white : AppColors.brandBlueAlt;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: () { HapticFeedback.lightImpact(); onSelected(tab); },
          style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)), elevation: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(icon, width: 16, height: 16, colorFilter: ColorFilter.mode(fg, BlendMode.srcIn)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
