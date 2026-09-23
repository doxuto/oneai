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

  /// Live view of today's quota — updates the moment a transcription is
  /// charged or refunded, so the minutes pill never needs a manual refresh.
  /// `fallback` comes from getMe (plan ceiling + per-recording cap).
  Stream<Quota?> watchQuota(String uid, {required String periodId, required Quota fallback}) =>
      _db.doc('users/$uid/quota/$periodId').snapshots().map((s) {
        final d = s.data();
        if (d == null) return Quota(usedSeconds: 0, limitSeconds: fallback.limitSeconds, maxDurationSeconds: fallback.maxDurationSeconds, resetAt: fallback.resetAt);
        return Quota(
          usedSeconds: readInt(d, 'usedSeconds') ?? 0,
          // The plan's ceiling wins over a doc written under another plan.
          limitSeconds: fallback.isUnlimited ? 0 : (readInt(d, 'limitSeconds') ?? fallback.limitSeconds),
          maxDurationSeconds: fallback.maxDurationSeconds,
          resetAt: fallback.resetAt,
        );
      });

  /// Period id the server uses: the Vietnam calendar day, "yyyy-MM-dd".
  static String periodIdFor(DateTime nowUtc) {
    final vn = nowUtc.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${vn.year}-${two(vn.month)}-${two(vn.day)}';
  }
}
