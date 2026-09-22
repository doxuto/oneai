import 'package:codebase_ai/data/services/model/demo/demo_post_dto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'demo_post_model.freezed.dart';

/// A domain model representing a post.
@freezed
sealed class DemoPostModel with _$DemoPostModel {
  const factory DemoPostModel({required int id, required int userId, required String title, required String body}) =
      _DemoPostModel;

  /// Creates a [DemoPostModel] from a [DemoPostDto].
  factory DemoPostModel.fromDto(DemoPostDto dto) =>
      DemoPostModel(id: dto.id, userId: dto.userId, title: dto.title, body: dto.body);
}
