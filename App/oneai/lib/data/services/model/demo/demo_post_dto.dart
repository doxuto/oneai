import 'package:freezed_annotation/freezed_annotation.dart';

part 'demo_post_dto.freezed.dart';
part 'demo_post_dto.g.dart';

@freezed
abstract class DemoPostDto with _$DemoPostDto {
  const factory DemoPostDto({required int id, required int userId, required String title, required String body}) =
      _DemoPostDto;

  factory DemoPostDto.fromJson(Map<String, dynamic> json) => _$DemoPostDtoFromJson(json);
}
