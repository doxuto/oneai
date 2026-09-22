import 'package:freezed_annotation/freezed_annotation.dart';

part 'demo_user_dto.freezed.dart';
part 'demo_user_dto.g.dart';

@freezed
abstract class DemoUserDto with _$DemoUserDto {
  const factory DemoUserDto({required int id, required String name, required String email}) = _DemoUserDto;

  factory DemoUserDto.fromJson(Map<String, dynamic> json) => _$DemoUserDtoFromJson(json);
}
