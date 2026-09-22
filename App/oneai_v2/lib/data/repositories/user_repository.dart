import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/user_models.dart';

class UserRepository {
  UserRepository({required FunctionsClient functions, required FirebaseFirestore firestore})
      : _fns = functions,
        _db = firestore;

  final FunctionsClient _fns;
  final FirebaseFirestore _db;

  Future<Me> me() async => Me.fromJson(await _fns.call('getMe'));

  /// Irreversible. The server deletes the Auth user; `onUserDeleted` then wipes
  /// Firestore + Storage. `confirm` is a literal `true` in the schema so a
  /// mis-wired button cannot delete anything by accident.
  Future<void> deleteAccount() => _fns.call('deleteAccount', {'confirm': true});

  /// Live view of today's quota — updates the moment an SSV reward lands or a
  /// transcription is charged, so the credits pill never needs a manual refresh.
  Stream<Quota?> watchQuota(String uid, {required String periodId, required int fallbackLimit, required DateTime resetAt}) =>
      _db.doc('users/$uid/quota/$periodId').snapshots().map((s) {
        final d = s.data();
        if (d == null) return Quota(used: 0, limit: fallbackLimit, rewardBonus: 0, resetAt: resetAt);
        final base = readInt(d, 'baseLimit') ?? fallbackLimit;
        final bonus = readInt(d, 'rewardBonus') ?? 0;
        return Quota(used: readInt(d, 'used') ?? 0, limit: base + bonus, rewardBonus: bonus, resetAt: resetAt);
      });

  /// Period id the server uses: the Vietnam calendar day, "yyyy-MM-dd".
  static String periodIdFor(DateTime nowUtc) {
    final vn = nowUtc.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${vn.year}-${two(vn.month)}-${two(vn.day)}';
  }
}
