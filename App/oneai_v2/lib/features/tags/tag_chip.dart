import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_ai/core/theme/app_colors.dart';

/// v1 TagChip: 40pt pill, brand blue when selected, pale blue otherwise.
class TagChip extends StatelessWidget {
  const TagChip({required this.label, super.key, this.selected = false, this.onTap, this.onLongPress});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static const Color selectedColor = AppColors.brandBlue;
  static const Color idleColor = Color(0xFFEDF4FF);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: IntrinsicWidth(
          child: GestureDetector(
            onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap!(); },
            onLongPress: onLongPress == null ? null : () { HapticFeedback.lightImpact(); onLongPress!(); },
            child: Container(
              height: 40,
              decoration: BoxDecoration(color: selected ? selectedColor : idleColor, borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: Text(label, style: TextStyle(color: selected ? Colors.white : selectedColor, fontWeight: FontWeight.w500, fontSize: 15)),
                ),
              ),
            ),
          ),
        ),
      );
}
