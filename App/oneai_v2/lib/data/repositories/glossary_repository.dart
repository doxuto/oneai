import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/models/glossary_models.dart';

class GlossaryRepository {
  GlossaryRepository({required FunctionsClient functions, required FirebaseFirestore firestore})
      : _fns = functions,
        _db = firestore;
  final FunctionsClient _fns;
  final FirebaseFirestore _db;

  /// Live, oldest first — the order the server hands terms to the models.
  Stream<List<GlossaryTerm>> watch(String uid) => _db
      .collection('users/$uid/glossary')
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map((d) => GlossaryTerm.fromFirestore(d.id, d.data())).toList());

  /// Same term in any casing updates the existing entry (server derives the id).
  Future<GlossaryTerm> upsert(String term, {String? hint}) async =>
      GlossaryTerm.fromJson((await _fns.call('upsertGlossaryTerm', {'term': term, if (hint != null && hint.isNotEmpty) 'hint': hint}))['term'] as Map<String, dynamic>);

  Future<void> delete(String termId) => _fns.call('deleteGlossaryTerm', {'termId': termId});
}
