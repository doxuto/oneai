import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/data/repositories/user_repository.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/credits/credit_gate.dart';

/// `getMe` once per sign-in: profile + today's quota with the server's resetAt.
final meProvider = FutureProvider<Me>((ref) {
  ref.watch(currentUidProvider); // refetch on account change
  return ref.watch(userRepositoryProvider).me();
});

/// Live quota for today — the credits pill and the credit gate read this.
/// Falls back to `getMe`'s numbers until the Firestore doc exists.
final quotaProvider = StreamProvider<Quota?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final me = ref.watch(meProvider).valueOrNull;
  final now = DateTime.now().toUtc();
  return ref.watch(userRepositoryProvider).watchQuota(
        uid,
        periodId: UserRepository.periodIdFor(now),
        fallbackLimit: me?.quota.limit ?? 1,
        resetAt: me?.quota.resetAt ?? now.add(const Duration(days: 1)),
      );
});

final premiumStatusProvider = Provider<PremiumStatus>((ref) {
  final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
  final quota = ref.watch(quotaProvider).valueOrNull;
  return premiumStatusOf(isPremium: premium, quota: quota);
});
