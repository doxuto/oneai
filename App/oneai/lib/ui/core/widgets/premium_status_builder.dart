
import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/data/services/admob/reward_ad_service.dart';
import 'package:codebase_ai/domain/use_cases/credit_usecase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// A widget that rebuilds when the user's premium status changes.
class PremiumStatusBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, PremiumStatus status) builder;
  const PremiumStatusBuilder({required this.builder, super.key});

  @override
  State<PremiumStatusBuilder> createState() => _PremiumStatusBuilderState();
}

class _PremiumStatusBuilderState extends State<PremiumStatusBuilder> {
  bool _isPremium = false;
  bool _hasCredits = false;
  final _log = Logger('PremiumStatusBuilder');

  @override
  void initState() {
    super.initState();
    _checkEntitlement();
    Purchases.addCustomerInfoUpdateListener(_customerInfoListener);
    context.read<CreditUseCase>()
      ..creditStream.listen((credit) {
        if (!mounted) return;
        _log.fine('Credit updated: $credit');
        setState(() {
          _hasCredits = credit > 0;
        });
      })
      ..getUserCredit();
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_customerInfoListener);
    super.dispose();
  }

  Future<void> _checkEntitlement() async {
    final info = await Purchases.getCustomerInfo();
    if (!mounted) return;
    setState(() {
      _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
    });
  }

  void _customerInfoListener(CustomerInfo info) {
    if (!mounted) return;
    setState(() {
      _isPremium = info.entitlements.active.containsKey(Constants.entitlementId);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _premiumStatus());

  PremiumStatus _premiumStatus() {
    if (_isPremium) {
      return PremiumStatus.premium;
    } else if (_hasCredits) {
      return PremiumStatus.nonPremiumHasCredits;
    } else {
      return PremiumStatus.nonPremiumNoCredits;
    }
  }
}

enum PremiumStatus { premium, nonPremiumHasCredits, nonPremiumNoCredits }

Future<void> premiumActionWrapper(BuildContext context, PremiumStatus status, Future<void> Function() action) async {
  if (status != PremiumStatus.nonPremiumNoCredits) {
    await action();
    if (!context.mounted) return;
    await context.read<CreditUseCase>().getUserCredit();
    return;
  } else {
    final amount = await context.read<RewardAdService>().showBeforeTranscribeProcess(context: context);
    // User received credits from the ad
    if (amount != null && amount > 0) {
      await action();
      if (!context.mounted) return;
      await context.read<CreditUseCase>().getUserCredit();
    }
  }
}
