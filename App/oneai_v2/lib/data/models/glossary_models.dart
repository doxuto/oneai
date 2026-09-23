import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/json_read.dart';

/// S11-10 — a name / product / piece of jargon the models must spell exactly.
class GlossaryTerm {
  const GlossaryTerm({required this.id, required this.term, required this.hint, required this.createdAt});
  factory GlossaryTerm.fromJson(Map<String, dynamic> j) => GlossaryTerm(
        id: readRequiredString(j, 'id'),
        term: readString(j, 'term') ?? '',
        hint: readString(j, 'hint'),
        createdAt: readDateTime(j, 'createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
  factory GlossaryTerm.fromFirestore(String id, Map<String, dynamic> d) {
    final c = d['createdAt'];
    return GlossaryTerm(id: id, term: readString(d, 'term') ?? '', hint: readString(d, 'hint'), createdAt: c is Timestamp ? c.toDate() : DateTime.fromMillisecondsSinceEpoch(0));
  }
  final String id;
  final String term;
  final String? hint;
  final DateTime createdAt;
}
