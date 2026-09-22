import 'package:flutter/material.dart';

/// Semantic tokens that Material's ColorScheme has no slot for.
/// Values carried over verbatim from v1's AppThemeExtension.
@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.successColor,
    required this.onSuccessColor,
    required this.successContainerColor,
    required this.onSuccessContainerColor,
    required this.warningColor,
    required this.onWarningColor,
    required this.warningContainerColor,
    required this.onWarningContainerColor,
    required this.buttonRadius,
    required this.cardRadius,
    required this.dialogRadius,
    required this.animationFast,
    required this.animationMedium,
    required this.animationSlow,
  });

  final Color successColor;
  final Color onSuccessColor;
  final Color successContainerColor;
  final Color onSuccessContainerColor;
  final Color warningColor;
  final Color onWarningColor;
  final Color warningContainerColor;
  final Color onWarningContainerColor;
  final Radius buttonRadius;
  final Radius cardRadius;
  final Radius dialogRadius;
  final Duration animationFast;
  final Duration animationMedium;
  final Duration animationSlow;

  static const AppThemeExtension light = AppThemeExtension(
    successColor: Color(0xFF00BFA5),
    onSuccessColor: Color(0xFFFFFFFF),
    successContainerColor: Color(0xFFCCF5E9),
    onSuccessContainerColor: Color(0xFF00382D),
    warningColor: Color(0xFFFFC107),
    onWarningColor: Color(0xFF000000),
    warningContainerColor: Color(0xFFFFE082),
    onWarningContainerColor: Color(0xFF332800),
    buttonRadius: Radius.circular(8),
    cardRadius: Radius.circular(12),
    dialogRadius: Radius.circular(16),
    animationFast: Duration(milliseconds: 200),
    animationMedium: Duration(milliseconds: 300),
    animationSlow: Duration(milliseconds: 500),
  );

  static const AppThemeExtension dark = AppThemeExtension(
    successColor: Color(0xFF00C897),
    onSuccessColor: Color(0xFF000000),
    successContainerColor: Color(0xFF00513C),
    onSuccessContainerColor: Color(0xFF7AEBC3),
    warningColor: Color(0xFFFFA000),
    onWarningColor: Color(0xFF000000),
    warningContainerColor: Color(0xFF653A00),
    onWarningContainerColor: Color(0xFFFFDDB3),
    buttonRadius: Radius.circular(8),
    cardRadius: Radius.circular(12),
    dialogRadius: Radius.circular(16),
    animationFast: Duration(milliseconds: 200),
    animationMedium: Duration(milliseconds: 300),
    animationSlow: Duration(milliseconds: 500),
  );

  @override
  AppThemeExtension copyWith({
    Color? successColor,
    Color? onSuccessColor,
    Color? successContainerColor,
    Color? onSuccessContainerColor,
    Color? warningColor,
    Color? onWarningColor,
    Color? warningContainerColor,
    Color? onWarningContainerColor,
    Radius? buttonRadius,
    Radius? cardRadius,
    Radius? dialogRadius,
    Duration? animationFast,
    Duration? animationMedium,
    Duration? animationSlow,
  }) {
    return AppThemeExtension(
      successColor: successColor ?? this.successColor,
      onSuccessColor: onSuccessColor ?? this.onSuccessColor,
      successContainerColor: successContainerColor ?? this.successContainerColor,
      onSuccessContainerColor: onSuccessContainerColor ?? this.onSuccessContainerColor,
      warningColor: warningColor ?? this.warningColor,
      onWarningColor: onWarningColor ?? this.onWarningColor,
      warningContainerColor: warningContainerColor ?? this.warningContainerColor,
      onWarningContainerColor: onWarningContainerColor ?? this.onWarningContainerColor,
      buttonRadius: buttonRadius ?? this.buttonRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      dialogRadius: dialogRadius ?? this.dialogRadius,
      animationFast: animationFast ?? this.animationFast,
      animationMedium: animationMedium ?? this.animationMedium,
      animationSlow: animationSlow ?? this.animationSlow,
    );
  }

  @override
  AppThemeExtension lerp(covariant ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      successColor: Color.lerp(successColor, other.successColor, t)!,
      onSuccessColor: Color.lerp(onSuccessColor, other.onSuccessColor, t)!,
      successContainerColor: Color.lerp(successContainerColor, other.successContainerColor, t)!,
      onSuccessContainerColor:
          Color.lerp(onSuccessContainerColor, other.onSuccessContainerColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      onWarningColor: Color.lerp(onWarningColor, other.onWarningColor, t)!,
      warningContainerColor: Color.lerp(warningContainerColor, other.warningContainerColor, t)!,
      onWarningContainerColor:
          Color.lerp(onWarningContainerColor, other.onWarningContainerColor, t)!,
      buttonRadius: t < 0.5 ? buttonRadius : other.buttonRadius,
      cardRadius: t < 0.5 ? cardRadius : other.cardRadius,
      dialogRadius: t < 0.5 ? dialogRadius : other.dialogRadius,
      animationFast: t < 0.5 ? animationFast : other.animationFast,
      animationMedium: t < 0.5 ? animationMedium : other.animationMedium,
      animationSlow: t < 0.5 ? animationSlow : other.animationSlow,
    );
  }
}

extension AppThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colors => Theme.of(this).colorScheme;
  AppThemeExtension get appTheme =>
      Theme.of(this).extension<AppThemeExtension>() ?? AppThemeExtension.light;
}
