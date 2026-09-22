import 'package:one_ai/data/firebase/json_read.dart';

enum Plan {
  free,
  premium;

  static Plan from(Map<String, dynamic> j, String k) =>
      readEnum(j, k, const {'free': Plan.free, 'premium': Plan.premium}, Plan.free);
}

class Quota {
  const Quota({required this.used, required this.limit, required this.rewardBonus, required this.resetAt});
  factory Quota.fromJson(Map<String, dynamic> j) => Quota(
        used: readInt(j, 'used') ?? 0,
        limit: readInt(j, 'limit') ?? 0,
        rewardBonus: readInt(j, 'rewardBonus') ?? 0,
        resetAt: readDateTime(j, 'resetAt') ?? DateTime.now(),
      );
  final int used;
  final int limit;
  final int rewardBonus;
  final DateTime resetAt;

  int get remaining => (limit - used).clamp(0, 1 << 30);
  bool get hasCredits => remaining > 0;
}

class OneAiUser {
  const OneAiUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.plan,
    required this.planExpiresAt,
    required this.minuteCount,
    required this.createdAt,
  });
  factory OneAiUser.fromJson(Map<String, dynamic> j) => OneAiUser(
        id: readRequiredString(j, 'id'),
        email: readString(j, 'email'),
        displayName: readString(j, 'displayName'),
        photoUrl: readString(j, 'photoUrl'),
        plan: Plan.from(j, 'plan'),
        planExpiresAt: readDateTime(j, 'planExpiresAt'),
        minuteCount: readInt(j, 'minuteCount') ?? 0,
        createdAt: readDateTime(j, 'createdAt'),
      );
  final String id;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final Plan plan;
  final DateTime? planExpiresAt;
  final int minuteCount;
  final DateTime? createdAt;

  bool get isPremium => plan == Plan.premium;
}

class Me {
  const Me({required this.user, required this.quota});
  factory Me.fromJson(Map<String, dynamic> j) => Me(
        user: OneAiUser.fromJson(readObject(j, 'user') ?? const <String, dynamic>{'id': ''}),
        quota: Quota.fromJson(readObject(j, 'quota') ?? const <String, dynamic>{}),
      );
  final OneAiUser user;
  final Quota quota;
}
