import 'package:flutter/material.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';

/// A custom button component used throughout the application
class AppButton extends StatelessWidget {
  /// Creates a new app button
  const AppButton({
    super.key,
    required this.child,
    this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 8.0,
    this.padding = const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
  });

  /// The child widget to display inside the button
  final Widget child;

  /// Function called when the button is pressed
  final VoidCallback? onPressed;

  /// Background color of the button
  final Color? backgroundColor;

  /// Foreground color of the button (text and icons)
  final Color? foregroundColor;

  /// Border radius of the button
  final double borderRadius;

  /// Padding inside the button
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? context.colorScheme.primary,
        foregroundColor: foregroundColor ?? context.colorScheme.onPrimary,
        padding: padding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
      ),
      child: child,
    );
  }
}
