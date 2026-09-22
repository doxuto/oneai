import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Enum defining the different states of the premium button
enum PremiumButtonState { premium, upgrade }

/// A button widget that displays different styles based on the premium status
/// Can show 'Premium' or 'Upgrade' states with appropriate styling
class PremiumButton extends StatelessWidget {
  final PremiumButtonState state;
  final VoidCallback? onPressed;

  const PremiumButton({required this.state, this.onPressed, super.key});

  @override
  Widget build(BuildContext context) => _buildPremiumButton(context);

  Widget _buildPremiumButton(BuildContext context) {
    // Button style based on state
    late final Color backgroundColor;
    late final String text;
    late final String svgAsset;
    late final Color textColor;

    switch (state) {
      case PremiumButtonState.premium:
        backgroundColor = const Color(0xFFFFBB00); // Yellow for Premium
        text = context.loc.premium;
        textColor = Colors.white;
        svgAsset = Assets.premiumIcon;
        break;
      case PremiumButtonState.upgrade:
        backgroundColor = const Color(0xFF4285F4); // Blue for Upgrade
        text = context.loc.upgrade;
        textColor = Colors.white;
        svgAsset = Assets.flashIcon;
        break;
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        disabledBackgroundColor: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.buttonRadius)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            svgAsset,
            width: 16,
            height: 16,
            // colorFilter: ColorFilter.mode(textColor, BlendMode.srcIn),
          ),
          gapW4,
          Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }
}
