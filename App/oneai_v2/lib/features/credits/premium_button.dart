import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';

enum PremiumButtonState { premium, upgrade }

/// v1 PremiumButton, verbatim: yellow "Premium" or blue "Upgrade".
class PremiumButton extends StatelessWidget {
  const PremiumButton({required this.state, super.key, this.onPressed});
  final PremiumButtonState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (Color bg, String text, String svg) = switch (state) {
      PremiumButtonState.premium => (const Color(0xFFFFBB00), context.l10n.premium, Assets.premiumIcon),
      PremiumButtonState.upgrade => (const Color(0xFF4285F4), context.l10n.upgrade, Assets.flashIcon),
    };
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        disabledBackgroundColor: bg,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.buttonRadius)),
        elevation: 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(svg, width: 16, height: 16),
          gapW4,
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
        ],
      ),
    );
  }
}
