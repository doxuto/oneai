import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/features/auth/auth_controller.dart';
import 'package:one_ai/features/auth/auth_models.dart';

/// Port of v1's LoginPage. Layout, colours and copy unchanged; the BLoC is
/// replaced by AuthController. Apple stays iOS-only, as in v1.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(authControllerProvider);
    final previous = ref.watch(lastLoginMethodProvider).valueOrNull;
    final l10n = context.l10n;

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthFailed) {
        AppSnack.failure(context, next.error);
        ref.read(authControllerProvider.notifier).dismissError();
      }
    });

    final busy = flow is AuthBusy ? flow.action : null;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SvgPicture.asset(Assets.circularComplicationIcon, width: 50, height: 50),
                  gapW12,
                  Text(l10n.oneAi, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                ],
              ),
              gapH12,
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 24, color: Colors.black),
                  children: [
                    TextSpan(text: l10n.instantNotesFromAudio),
                    TextSpan(text: l10n.doneWithAi, style: const TextStyle(color: AppColors.brandBlue)),
                  ],
                ),
              ),
              const Spacer(),
              _GoogleButton(
                loading: busy == AuthAction.signInGoogle,
                enabled: busy == null,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(authControllerProvider.notifier).signInWithGoogle();
                },
              ),
              if (Platform.isIOS) ...[
                gapH12,
                _AppleButton(
                  loading: busy == AuthAction.signInApple,
                  enabled: busy == null,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(authControllerProvider.notifier).signInWithApple();
                  },
                ),
              ],
              gapH12,
              if (previous != null)
                Text(
                  switch (previous) {
                    AuthProviderKind.google => l10n.previouslySignedInWithGoogle,
                    AuthProviderKind.apple => l10n.previouslySignedInWithApple,
                  },
                  style: const TextStyle(fontSize: 12, color: Colors.black, fontWeight: FontWeight.w400),
                ),
              gapH24,
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.enabled, required this.onPressed});
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Colors.black),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(Assets.googleIcon, width: 17, height: 17),
            gapW4,
            Text(context.l10n.signInWithGoogle, style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w600)),
            if (loading) ...[
              gapW8,
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
      );
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.loading, required this.enabled, required this.onPressed});
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(Assets.appleIcon, width: 17, height: 17),
            gapW4,
            Text(context.l10n.signInWithApple, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (loading) ...[
              gapW8,
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            ],
          ],
        ),
      );
}
