import 'package:one_ai/data/firebase/json_read.dart';

class Tag {
  const Tag({required this.id, required this.name, required this.minuteCount, required this.createdAt});
  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
        id: readRequiredString(j, 'id'),
        name: readString(j, 'name') ?? '',
        minuteCount: readInt(j, 'minuteCount') ?? 0,
        createdAt: readDateTime(j, 'createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
  final String id;
  final String name;
  final int minuteCount;
  final DateTime createdAt;
}
