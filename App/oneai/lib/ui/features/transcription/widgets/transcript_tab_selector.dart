import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Enum for the different tabs in the transcript screen
enum TranscriptTab { minutes, transcript, chat }

/// Widget for selecting between different tabs in the transcript screen
class TranscriptTabSelector extends StatelessWidget {
  final TranscriptTab selectedTab;
  final ValueChanged<TranscriptTab> onTabSelected;

  const TranscriptTabSelector({required this.selectedTab, required this.onTabSelected, super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _buildTabButton(context, TranscriptTab.minutes, 'Summary', Assets.listIcon),
      _buildTabButton(context, TranscriptTab.transcript, context.loc.transcript, Assets.commentIcon),
      _buildTabButton(context, TranscriptTab.chat, context.loc.chat, Assets.commentLightIcon),
    ],
  );

  Widget _buildTabButton(BuildContext context, TranscriptTab tab, String label, String icon) {
    final bool isSelected = selectedTab == tab;
    final Color backgroundColor = isSelected ? const Color(0xFF2C7DF7) : const Color(0xFFE6F0FF);
    final Color textColor = isSelected ? Colors.white : const Color(0xFF2C7DF7);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            onTabSelected(tab);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: textColor,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(icon, width: 16, height: 16, colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn)),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
