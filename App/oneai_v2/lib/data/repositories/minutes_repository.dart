import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/models/minute_models.dart';

/// Reads that must be live come from Firestore (snapshots); everything that
/// mutates goes through a callable. The client never writes Firestore.
class MinutesRepository {
  MinutesRepository({required FunctionsClient functions, required FirebaseFirestore firestore})
      : _fns = functions,
        _db = firestore;

  final FunctionsClient _fns;
  final FirebaseFirestore _db;

  CollectionReference<MinuteSummary> _col(String uid) =>
      _db.collection('users/$uid/minutes').withConverter<MinuteSummary>(
            fromFirestore: (snap, _) => MinuteSummary.fromFirestore(snap.id, snap.data() ?? const {}),
            toFirestore: (_, __) => throw UnsupportedError('client never writes minutes'),
          );

  /// Newest first. Firestore keeps this list live — a note created on another
  /// device, or a status change from the worker, shows up without a refresh.
  Stream<List<MinuteSummary>> watchList(String uid, {int limit = 100}) => _col(uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());

  /// Just the processing state of one note.
  Stream<MinuteProgress> watchProgress(String uid, String minuteId) => _db
      .doc('users/$uid/minutes/$minuteId')
      .snapshots()
      .where((s) => s.exists)
      .map((s) => MinuteProgress.fromFirestore(s.id, s.data() ?? const {}));

  Future<CreateMinuteResult> create({
    required SourceType sourceType,
    required String fileName,
    required int sizeBytes,
    required String contentType,
  }) async =>
      CreateMinuteResult.fromJson(await _fns.call('createMinute', {
        'sourceType': sourceType.name,
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        'contentType': contentType,
      }));

  /// Cursor pagination through the callable — for tag filters and title sort,
  /// which the live stream does not do.
  Future<MinutePage> list({int limit = 20, String? cursor, List<String>? tagIds, ListSort sort = ListSort.createdAtDesc}) async =>
      MinutePage.fromJson(await _fns.call('listMinutes', {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
        if (tagIds != null && tagIds.isNotEmpty) 'tagIds': tagIds,
        'sort': sort.name,
      }));

  Future<MinuteDetail> get(String minuteId) async =>
      MinuteDetail.fromJson((await _fns.call('getMinute', {'minuteId': minuteId}))['minute'] as Map<String, dynamic>);

  Future<MinuteSummary> update(String minuteId, {String? title, String? iconEmoji, bool clearIconEmoji = false, List<String>? tagIds, bool? pinned}) async =>
      MinuteSummary.fromJson((await _fns.call('updateMinute', {
        'minuteId': minuteId,
        if (title != null) 'title': title,
        if (clearIconEmoji) 'iconEmoji': null else if (iconEmoji != null) 'iconEmoji': iconEmoji,
        if (tagIds != null) 'tagIds': tagIds,
        if (pinned != null) 'pinned': pinned,
      }))['minute'] as Map<String, dynamic>);

  Future<void> delete(String minuteId) => _fns.call('deleteMinute', {'minuteId': minuteId});
}
