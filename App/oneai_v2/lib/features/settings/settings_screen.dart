import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:one_ai/bootstrap.dart' show appConfigProvider;
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/firebase/client_info.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/auth/auth_controller.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/minutes/detail/feedback_dialog.dart';
import 'package:one_ai/features/notifications/notification_prefs.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/tags/tag_manager_sheet.dart';
import 'package:one_ai/features/transcription/language_selector.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';
import 'package:url_launcher/url_launcher.dart';

/// Port of v1 SettingsScreen: the same five sections and rows, plus a
/// Notifications toggle and a Tags row. Exit shows the `settings_exit`
/// interstitial as v1 did.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _exit(BuildContext context, WidgetRef ref) async {
    await HapticFeedback.lightImpact();
    await ref.read(interstitialHookProvider).maybeShow(AdPlacement.settingsExit);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = ref.watch(languageSettingsProvider);
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final quota = ref.watch(quotaProvider).valueOrNull;
    final user = ref.watch(authUserProvider).valueOrNull;
    final config = ref.watch(appConfigProvider);
    final auth = ref.watch(authControllerProvider);

    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthFailed) {
        AppSnack.failure(context, next.error);
        ref.read(authControllerProvider.notifier).dismissError();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _exit(context, ref); },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => _exit(context, ref)),
          title: Text(l10n.settings),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
        ),
        backgroundColor: const Color(0xFFFFFFFF),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _SectionLabel(l10n.sectionNotes),
                _Card([
                  _LanguageRow(label: l10n.audioLanguage, selected: lang.audioLanguage, onChanged: (v) => ref.read(languageSettingsProvider.notifier).setAudioLanguage(v)),
                  const _RowDivider(),
                  _LanguageRow(label: l10n.summaryLanguage, selected: lang.summaryLanguage, choices: TranscriptionLanguage.summaryChoices, onChanged: (v) => ref.read(languageSettingsProvider.notifier).setSummaryLanguage(v)),
                  const _RowDivider(),
                  _IconRow(icon: Assets.tagsIcon, text: l10n.manageTags, onTap: () => TagManagerSheet.show(context)),
                  const _RowDivider(),
                  _IconRow(icon: Assets.editIcon, text: l10n.glossary, onTap: () => context.push(Routes.glossary)),
                  const _RowDivider(),
                  const _NotificationsRow(),
                ]),
                _SectionLabel(l10n.sectionSupport),
                _Card([
                  _IconRow(icon: Assets.feedbackIcon, text: l10n.giveFeedback, onTap: () => showFeedbackDialog(context)),
                  const _RowDivider(),
                  _IconRow(icon: Assets.contactIcon, text: l10n.contactUs, onTap: () => _contact(context, config.supportEmail, user)),
                  const _RowDivider(),
                  _IconRow(icon: Assets.reviewIcon, text: l10n.leaveReview, onTap: () async {
                    final review = InAppReview.instance;
                    if (await review.isAvailable()) {
                      await review.requestReview();
                    } else {
                      await review.openStoreListing();
                    }
                  }),
                ]),
                _SectionLabel(l10n.sectionLegal),
                _Card([
                  _IconRow(icon: Assets.policyIcon, text: l10n.privacyPolicy, onTap: () => _open(context, config.privacyUrl)),
                  const _RowDivider(),
                  _IconRow(icon: Assets.termsIcon, text: l10n.termsOfService, onTap: () => _open(context, config.termsUrl)),
                  if (ref.watch(privacyOptionsRequiredProvider).valueOrNull ?? false) ...[
                    const _RowDivider(),
                    _IconRow(icon: Assets.policyIcon, text: l10n.privacyOptions, onTap: () => ref.read(privacyOptionsHookProvider)(context)),
                  ],
                ]),
                _SectionLabel(l10n.sectionAccount),
                _Card([
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Align(alignment: Alignment.centerLeft, child: Text(l10n.emailLabel(user?.email ?? ''), style: const TextStyle(fontSize: 15, color: Colors.black87))),
                  ),
                  const _RowDivider(),
                  _IconRow(icon: Assets.subscriptionIcon, text: l10n.manageSubscription, onTap: () => premium ? ref.read(paywallProvider).customerCenter() : ref.read(paywallProvider).present()),
                  const _RowDivider(),
                  _CreditsRow(icon: Assets.freeIcon, title: l10n.freeMinutesToday, value: premium ? l10n.unlimited : '${quota?.remainingMinutes ?? 0}/${quota?.limitMinutes ?? 10}'),
                  const _RowDivider(),
                  _IconRow(icon: Assets.signoutIcon, text: l10n.signOut, onTap: () => ref.read(authControllerProvider.notifier).signOut()),
                ]),
                _SectionLabel(l10n.sectionDangerZone, color: const Color(0xFFFFB300)),
                _Card([
                  _IconRow(icon: Assets.deleteAccountIcon, text: l10n.deleteAccount, onTap: () => _deleteAccount(context, ref)),
                ]),
              ],
            ),
            if (auth is AuthBusy) const Positioned.fill(child: ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator()))),
          ],
        ),
      ),
    );
  }

  Future<void> _contact(BuildContext context, String email, User? user) async {
    try {
      final info = await ClientInfo.current();
      const subject = 'Support Request';
      final body = 'Send us an email to share your thoughts...\n\n-----\nTo help us assist you better, please do not delete the information below.\nMy ID: ${user?.uid}\nApp version: ${info.appVersion}';
      await launchUrl(Uri(scheme: 'mailto', path: email, queryParameters: {'subject': subject, 'body': body}));
    } on Object catch (_) {
      if (context.mounted) AppSnack.show(context, context.l10n.somethingWentWrong);
    }
  }

  Future<void> _open(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object catch (_) {
      if (context.mounted) AppSnack.show(context, context.l10n.somethingWentWrong);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.deleteAccount,
        confirmLabel: ctx.l10n.delete,
        destructive: true,
        content: Text(ctx.l10n.deleteAccountConfirm, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).deleteAccount();
    if (context.mounted && ref.read(authControllerProvider) is AuthIdle) AppSnack.show(context, context.l10n.accountDeleted);
  }
}

/// UMP privacy options form; A6 provides the real one.

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.color = const Color(0xFFBDBDBD)});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
        child: Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600, letterSpacing: 1)),
      );
}

class _Card extends StatelessWidget {
  const _Card(this.children);
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]),
        child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: Column(children: children)),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();
  @override
  Widget build(BuildContext context) => const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0), indent: 16, endIndent: 16);
}

class _IconRow extends StatelessWidget {
  const _IconRow({required this.icon, required this.text, this.onTap});
  final String icon;
  final String text;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap == null ? null : () { HapticFeedback.lightImpact(); onTap!(); },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            SvgPicture.asset(icon, width: 30, height: 30),
            const SizedBox(width: 16),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400))),
            const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
          ]),
        ),
      );
}

class _CreditsRow extends StatelessWidget {
  const _CreditsRow({required this.icon, required this.title, required this.value});
  final String icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          SvgPicture.asset(icon, width: 30, height: 30),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400))),
          Text(value, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400)),
          const SizedBox(width: 6),
        ]),
      );
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.label, required this.selected, required this.onChanged, this.choices});
  final String label;
  final TranscriptionLanguage selected;
  final ValueChanged<TranscriptionLanguage> onChanged;
  final List<TranscriptionLanguage>? choices;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400))),
          LanguageSelector(
            selected: selected,
            choices: choices,
            onSelected: onChanged,
            trigger: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Text(LanguageSelector.nameOf(context, selected), style: const TextStyle(color: AppColors.brandBlue)),
                const SizedBox(width: 8),
                Icon(Icons.expand_more, color: Colors.grey[600], size: 20),
              ]),
            ),
          ),
        ]),
      );
}

class _NotificationsRow extends ConsumerWidget {
  const _NotificationsRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Expanded(child: Text(context.l10n.notifyWhenReady, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400))),
        Switch.adaptive(
          value: prefs.valueOrNull?.transcriptionDone ?? true,
          activeColor: AppColors.brandBlue,
          onChanged: (v) => ref.read(notificationPrefsProvider.notifier).setTranscriptionDone(v),
        ),
      ]),
    );
  }
}
