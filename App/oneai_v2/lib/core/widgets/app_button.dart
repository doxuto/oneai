import 'package:flutter/material.dart';
import 'package:one_ai/core/theme/theme_context.dart';

/// v1's AppButton, unchanged in look; `loading` disables and shows a spinner
/// beside the child instead of replacing it (the button keeps its width).
class AppButton extends StatelessWidget {
  const AppButton({
    required this.child,
    super.key,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    this.loading = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double borderRadius;
  final EdgeInsets padding;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? context.colorScheme.onPrimary;
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? context.colorScheme.primary,
        foregroundColor: fg,
        disabledBackgroundColor: (backgroundColor ?? context.colorScheme.primary).withValues(alpha: 0.6),
        disabledForegroundColor: fg,
        padding: padding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          if (loading) ...[
            const SizedBox(width: 8),
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
          ],
        ],
      ),
    );
  }
}
