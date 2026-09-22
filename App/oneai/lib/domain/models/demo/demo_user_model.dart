import 'package:codebase_ai/data/services/model/demo/demo_user_dto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'demo_user_model.freezed.dart';

/// A domain model representing a user.
@freezed
sealed class DemoUserModel with _$DemoUserModel {
  const factory DemoUserModel({required int id, required String name, required String email}) = _DemoUserModel;

  /// Creates a [DemoUserModel] from a [DemoUserDto].
  factory DemoUserModel.fromDto(DemoUserDto dto) => DemoUserModel(id: dto.id, name: dto.name, email: dto.email);
}
