import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';

/// v1's dialog chrome, used by every dialog in the app: centred title,
/// 16-radius, a hairline divider and two equal-width text buttons split by a
/// vertical rule. Kept as ONE widget so the look cannot drift between screens.
class StyledDialog extends StatelessWidget {
  const StyledDialog({
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.onConfirm,
    super.key,
    this.cancelLabel,
    this.onCancel,
    this.destructive = false,
    this.titleIcon,
  });

  final String title;
  final Widget content;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final bool destructive;
  /// v1 showed an 18×18 icon before some titles (the recording exit warning).
  final Widget? titleIcon;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: titleIcon == null
            ? Text(title, textAlign: TextAlign.center, style: context.textTheme.titleLarge)
            : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                titleIcon!,
                const SizedBox(width: 8),
                Flexible(child: Text(title, textAlign: TextAlign.center, style: context.textTheme.titleLarge)),
              ]),
        content: content,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        actionsPadding: EdgeInsets.zero,
        actions: [
          const Divider(height: 1, color: AppColors.dividerGrey),
          IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      (onCancel ?? () => Navigator.of(context).pop())();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16))),
                    ),
                    child: Text(cancelLabel ?? context.l10n.cancel, style: context.textTheme.labelLarge?.copyWith(color: Colors.blue)),
                  ),
                ),
                const VerticalDivider(width: 1, color: AppColors.dividerGrey),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onConfirm();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(bottomRight: Radius.circular(16))),
                    ),
                    child: Text(
                      confirmLabel,
                      style: context.textTheme.labelLarge?.copyWith(color: destructive ? AppColors.destructiveRed : Colors.blue),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

/// v1's `getDialogWidth`.
double dialogWidth(BuildContext context) {
  final w = MediaQuery.of(context).size.width;
  if (w < 600) return w * 0.9;
  if (w < 1200) return w * 0.8;
  return w * 0.6;
}

/// v1's outlined text field inside dialogs.
InputDecoration dialogFieldDecoration(BuildContext context, {String? hintText, String? errorText, TextStyle? hintStyle}) =>
    InputDecoration(
      hintText: hintText,
      hintStyle: hintStyle,
      errorText: errorText,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: context.colorScheme.primary)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
