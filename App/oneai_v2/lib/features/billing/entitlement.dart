import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Whether the user holds the `pro` entitlement. RevenueCat is the source of
/// truth; the server mirrors it into `users/{uid}.plan` via the webhook, but
/// the UI follows RevenueCat so a purchase shows instantly.
abstract interface class EntitlementSource {
  /// Emits the current value first, then every change.
  Stream<bool> watchPremium();

  /// Forces a fetch (after a purchase or restore).
  Future<bool> refresh();
}

class RevenueCatEntitlements implements EntitlementSource {
  RevenueCatEntitlements({required this.entitlementId});
  final String entitlementId;

  bool _isPro(CustomerInfo info) => info.entitlements.active.containsKey(entitlementId);

  @override
  Stream<bool> watchPremium() {
    late StreamController<bool> ctl;
    void listener(CustomerInfo info) {
      if (!ctl.isClosed) ctl.add(_isPro(info));
    }

    ctl = StreamController<bool>(
      onListen: () async {
        Purchases.addCustomerInfoUpdateListener(listener);
        try {
          ctl.add(_isPro(await Purchases.getCustomerInfo()));
        } on Object catch (e, st) {
          ctl.addError(e, st);
        }
      },
      onCancel: () => Purchases.removeCustomerInfoUpdateListener(listener),
    );
    return ctl.stream;
  }

  @override
  Future<bool> refresh() async => _isPro(await Purchases.getCustomerInfo());
}

final entitlementSourceProvider = Provider<EntitlementSource>(
  (ref) => RevenueCatEntitlements(entitlementId: ref.watch(appConfigProvider).entitlementId),
);

/// `AsyncValue<bool>`; treat loading/error as *not* premium so a RevenueCat
/// hiccup never hides ads-free UI behind a spinner — but also never grants
/// premium by accident.
final isPremiumProvider = StreamProvider<bool>((ref) => ref.watch(entitlementSourceProvider).watchPremium());
