import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/tag_models.dart';

class TagsRepository {
  TagsRepository({required FunctionsClient functions, required FirebaseFirestore firestore})
      : _fns = functions,
        _db = firestore;

  final FunctionsClient _fns;
  final FirebaseFirestore _db;

  Stream<List<Tag>> watch(String uid) => _db
      .collection('users/$uid/tags')
      .orderBy('nameLower')
      .snapshots()
      .map((s) => s.docs.map((d) {
            final data = d.data();
            final created = data['createdAt'];
            return Tag(
              id: d.id,
              name: readString(data, 'name') ?? '',
              minuteCount: readInt(data, 'minuteCount') ?? 0,
              createdAt: created is Timestamp ? created.toDate() : DateTime.fromMillisecondsSinceEpoch(0),
            );
          }).toList());

  Future<Tag> create(String name) async => Tag.fromJson((await _fns.call('createTag', {'name': name}))['tag'] as Map<String, dynamic>);

  Future<List<Tag>> list() async => readObjectList(await _fns.call('listTags'), 'items').map(Tag.fromJson).toList();

  Future<Tag> rename(String tagId, String name) async =>
      Tag.fromJson((await _fns.call('updateTag', {'tagId': tagId, 'name': name}))['tag'] as Map<String, dynamic>);

  /// Returns how many notes lost the tag.
  Future<int> delete(String tagId) async => readInt(await _fns.call('deleteTag', {'tagId': tagId}), 'affectedMinuteCount') ?? 0;
}
