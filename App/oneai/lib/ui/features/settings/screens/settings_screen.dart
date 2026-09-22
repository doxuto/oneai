import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_bloc.dart';
import 'package:codebase_ai/domain/bloc/auth/auth_event.dart';
import 'package:codebase_ai/domain/use_cases/credit_usecase.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:codebase_ai/ui/features/home/widgets/sentry_feedback_dialog.dart';
import 'package:codebase_ai/ui/features/settings/view_model/settings_bloc.dart';
import 'package:codebase_ai/ui/features/settings/view_model/settings_event.dart';
import 'package:codebase_ai/ui/features/settings/view_model/settings_state.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _log = Logger('SettingsScreen');
  final SharedPreferencesService _preferencesService = SharedPreferencesService();
  Language _audioLanguage = Language.autodetect;
  Language _summaryLanguage = Language.autodetect;

  final _termsOfServiceUrl = 'https://doxutostudio.top/terms';
  final _privacyPolicyUrl = 'https://doxutostudio.top/privacy';
  final _contactUsEmail = 'contact@doxutostudio.top';

  bool _isPremium = false;

  String _credits = '0';

  /// Function to execute before navigating back (BackButton or gesture)
  Future<bool> _onWillPop() async {
    // Place any logic you want to execute before popping here
    _log.info('Back navigation intercepted in SettingsScreen');
    // Return true to allow pop, false to prevent
    await context.read<InterstitialAdService>().showBeforeSettingsExit(context: context);
    return true;
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _hideLoadingDialog() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLanguagesFromPreferences();
    _checkEntitlement();
    Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_customerInfoListener);
    super.dispose();
  }

  Future<void> _checkEntitlement() async {
    final info = await Purchases.getCustomerInfo();
    setState(() {
      _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
      _checkCredits();
    });
  }

  void _customerInfoListener(CustomerInfo info) {
    if (mounted) {
      setState(() {
        _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
        _checkCredits();
      });
    }
  }

  Future<void> _checkCredits() async {
    setState(() {
      _credits =
          context.read<CreditUseCase>().credit >= 888 ? 'Unlimited' : context.read<CreditUseCase>().credit.toString();
    });

    final userCredits = await context.read<CreditUseCase>().getUserCredit();

    if (!mounted) return;
    setState(() {
      _credits = userCredits >= 888 ? 'Unlimited' : userCredits.toString();
      _log.severe('User credits: $userCredits');
    });
  }

  Future<void> _onPremiumButtonPressed() async {
    await HapticFeedback.lightImpact();
    if (!_isPremium) {
      await RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId);
    } else {
      await RevenueCatUI.presentCustomerCenter();
    }
  }

  Future<void> _loadLanguagesFromPreferences() async {
    final audioResult = await _preferencesService.getAudioLanguage();
    final summaryResult = await _preferencesService.getSummaryLanguage();
    setState(() {
      if (audioResult != null) {
        _audioLanguage = Language.values.byName(audioResult);
      }
      if (summaryResult != null) {
        _summaryLanguage = Language.values.byName(summaryResult);
      }
    });
  }

  Future<void> _saveAudioLanguage(Language lang) async {
    setState(() => _audioLanguage = lang);
    await _preferencesService.setAudioLanguage(lang.name);
  }

  Future<void> _saveSummaryLanguage(Language lang) async {
    setState(() => _summaryLanguage = lang);
    await _preferencesService.setSummaryLanguage(lang.name);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) {
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      }
    },
    child: BlocListener<SettingsBloc, SettingsState>(
      listener: (context, state) {
        switch (state) {
          case SettingsInitial():
            _log.info('State: Initial');
            break;
          case SettingsLoading():
            _log.info('State: Loading');
            _showLoadingDialog();
            break;
          case SettingsDeleteAccountSuccess():
            _log.info('State: DeleteAccountSuccess');
            _hideLoadingDialog();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted successfully.')));
            // Navigator.of(context).pop();
            break;
          case SettingsError(:final message):
            _log.severe('State: Error - Message: $message');
            _hideLoadingDialog();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
            break;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
            onPressed: () async {
              await HapticFeedback.lightImpact();
              final shouldPop = await _onWillPop();
              if (shouldPop) {
                if (!context.mounted) return;
                context.pop();
              }
            },
          ),
          title: const Text('Settings'),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black,
        ),
        backgroundColor: const Color(0xFFFFFFFF),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            _sectionLabel('NOTES'),
            _card([
              _languageRow('Audio Language', _audioLanguage, _saveAudioLanguage),
              _divider(),
              _languageRow('Summary Language', _summaryLanguage, _saveSummaryLanguage),
            ]),
            _sectionLabel('SUPPORT'),
            _card([
              _iconRow(
                Assets.feedbackIcon,
                'Give feedback',
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  if (!context.mounted) return;
                  await showDialog(context: context, builder: (_) => const SentryFeedbackDialog());
                },
              ),
              _divider(),
              _iconRow(
                Assets.contactIcon,
                'Contact us',
                onTap: () async {
                  try {
                    await HapticFeedback.lightImpact();
                    final appVersion = (await PackageInfo.fromPlatform()).version;
                    final userId = FirebaseAuth.instance.currentUser?.uid;
                    const subject = 'Support Request';
                    final body =
                        'Send us an email to share your thoughts...\n\n-----\nTo help us assist you better, please do not delete the information below.\nMy ID: $userId\nApp version: $appVersion';
                    await launchUrl(Uri.parse('mailto:$_contactUsEmail?subject=$subject&body=$body'));
                  } catch (e) {
                    _log.severe('Error sending email: $e');
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Failed to send email. Please try again later.')));
                  }
                },
              ),
              _divider(),
              _iconRow(
                Assets.reviewIcon,
                'Leave a review',
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  final inAppReview = InAppReview.instance;
                  if (await inAppReview.isAvailable()) {
                    await inAppReview.requestReview();
                  } else {
                    await inAppReview.openStoreListing();
                  }
                },
              ),
            ]),
            _sectionLabel('LEGAL'),
            _card([
              _iconRow(
                Assets.policyIcon,
                'Privacy policy',
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  try {
                    await launchUrl(Uri.parse(_privacyPolicyUrl));
                  } catch (e) {
                    _log.severe('Error opening privacy policy: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to open privacy policy. Please try again later.')),
                    );
                  }
                },
              ),
              _divider(),
              _iconRow(
                Assets.termsIcon,
                'Terms of service',
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  try {
                    await launchUrl(Uri.parse(_termsOfServiceUrl));
                  } catch (e) {
                    _log.severe('Error opening terms of service: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to open terms of service. Please try again later.')),
                    );
                  }
                },
              ),
            ]),
            _sectionLabel('ACCOUNT'),
            _card([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Email: ${FirebaseAuth.instance.currentUser?.email}',
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ),
              ),
              _divider(),
              _iconRow(Assets.subscriptionIcon, 'Manage subscription', onTap: _onPremiumButtonPressed),
              _divider(),
              _creditsRow(Assets.freeIcon, 'Free credits', _credits),
              _divider(),
              _iconRow(
                Assets.signoutIcon,
                'Sign out',
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.read<AuthBloc>().add(const AuthEvent.signOut());
                },
              ),
            ]),
            _sectionLabel('DANGER ZONE', color: const Color(0xFFFFB300)),
            _card([
              _iconRow(
                Assets.deleteAccountIcon,
                'Delete account',
                onTap: () async {
                  await HapticFeedback.lightImpact();
                  if (!context.mounted) return;
                  final confirm = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (ctx) => AlertDialog(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Text('Delete Account', style: context.textTheme.titleLarge)],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Are you sure you want to delete your account? This action cannot be undone.',
                                textAlign: TextAlign.center,
                                style: context.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                          actionsPadding: EdgeInsets.zero,
                          actions: [
                            const Divider(height: 1, color: Color(0xFFBDBDBD)),
                            IntrinsicHeight(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.of(ctx).pop(false);
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                                        ),
                                      ),
                                      child: Text(
                                        context.loc.cancel,
                                        style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                                      ),
                                    ),
                                  ),
                                  const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () {
                                        HapticFeedback.lightImpact();
                                        Navigator.of(ctx).pop(true);
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                                        ),
                                      ),
                                      child: Text(
                                        'Delete',
                                        style: context.textTheme.labelLarge?.copyWith(color: const Color(0xFFE41919)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                  );
                  if (confirm ?? false) {
                    if (!context.mounted) {
                      return;
                    }
                    context.read<SettingsBloc>().add(const SettingsEvent.deleteAccount());
                  }
                },
              ),
            ]),
          ],
        ),
      ),
    ),
  );

  Widget _sectionLabel(String text, {Color color = const Color(0xFFBDBDBD)}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
    child: Text(text, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600, letterSpacing: 1)),
  );

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Material(color: Colors.white, borderRadius: BorderRadius.circular(14), child: Column(children: children)),
  );

  Widget _divider() => const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0), indent: 16, endIndent: 16);

  Widget _iconRow(String icon, String text, {VoidCallback? onTap}) => InkWell(
    onTap:
        onTap == null
            ? null
            : () {
              HapticFeedback.lightImpact();
              onTap();
            },
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SvgPicture.asset(icon, width: 30, height: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400)),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
        ],
      ),
    ),
  );

  Widget _creditsRow(String icon, String title, String credits) => InkWell(
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SvgPicture.asset(icon, width: 30, height: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400)),
          ),
          Text(credits, style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400)),
          const SizedBox(width: 6),
        ],
      ),
    ),
  );

  Widget _languageRow(String label, Language selected, ValueChanged<Language> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400))),
        LanguageSelector(
          selectedLanguage: selected,
          onLanguageSelected: onChanged,
          triggerButton: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Text(
                  LanguageSelector.getLanguageName(context, selected),
                  style: const TextStyle(color: Color(0xFF0767F8)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.expand_more, color: Colors.grey[600], size: 20),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
