import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';

class TagChip extends StatelessWidget {
  final Tag tag;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TagChip({super.key, required this.tag, this.selected = false, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: IntrinsicWidth(
        child: GestureDetector(
          onTap:
              onTap == null
                  ? null
                  : () {
                    HapticFeedback.lightImpact();
                    onTap!();
                  },
          onLongPress:
              onLongPress == null
                  ? null
                  : () {
                    HapticFeedback.lightImpact();
                    onLongPress!();
                  },
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF0767F8) : const Color(0xFFEDF4FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: Text(
                  tag.name,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF0767F8),
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
