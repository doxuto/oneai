import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/bootstrap.dart' show appConfigProvider;
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

/// The four v1 paywall entry points call this. RevenueCat's own UI is the
/// paywall; we only decide "paywall or customer center" and refresh the
/// entitlement afterwards so the header flips without a restart.
class Paywall {
  Paywall(this._ref);
  final Ref _ref;

  /// Returns whether the user is premium when the sheet closes.
  Future<bool> present() async {
    final id = _ref.read(appConfigProvider).entitlementId;
    try {
      await RevenueCatUI.presentPaywallIfNeeded(id);
    } on Object catch (e) {
      dev.log('paywall failed', name: 'billing', error: e);
    }
    return _ref.read(entitlementSourceProvider).refresh();
  }

  Future<void> customerCenter() async {
    try {
      await RevenueCatUI.presentCustomerCenter();
    } on Object catch (e) {
      dev.log('customer center failed', name: 'billing', error: e);
    }
  }
}

final paywallProvider = Provider<Paywall>(Paywall.new);
