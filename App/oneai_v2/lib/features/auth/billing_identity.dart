import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat identity, hidden behind an interface so auth logic is testable
/// and so the SDK is touched from exactly one place.
abstract interface class BillingIdentity {
  /// Binds purchases to the Firebase uid. Idempotent: no-op when already bound.
  Future<void> logIn(String uid);

  /// Back to an anonymous RevenueCat id. Safe to call when already anonymous.
  Future<void> logOut();
}

class RevenueCatIdentity implements BillingIdentity {
  const RevenueCatIdentity();

  @override
  Future<void> logIn(String uid) async {
    if (await Purchases.appUserID == uid) return;
    await Purchases.logIn(uid);
  }

  @override
  Future<void> logOut() async {
    if (await Purchases.isAnonymous) return;
    await Purchases.logOut();
  }
}

class NoopBillingIdentity implements BillingIdentity {
  const NoopBillingIdentity();
  @override
  Future<void> logIn(String uid) async {}
  @override
  Future<void> logOut() async {}
}
