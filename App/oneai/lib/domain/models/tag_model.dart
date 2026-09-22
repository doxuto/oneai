import 'package:freezed_annotation/freezed_annotation.dart';

part 'tag_model.freezed.dart';

part 'tag_model.g.dart';

@freezed
sealed class Tag with _$Tag {
  const factory Tag({required String id, required String name}) = _Tag;

  factory Tag.fromJson(Map<String, dynamic> json) => _$TagFromJson(json);
}
