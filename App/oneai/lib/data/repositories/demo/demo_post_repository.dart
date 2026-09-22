import 'package:codebase_ai/data/services/api/demo/demo_api_service.dart';
import 'package:codebase_ai/domain/models/demo/demo_post_model.dart';
import 'package:codebase_ai/utils/result.dart';

class DemoPostRepository {
  final DemoApiService _apiService;

  DemoPostRepository({required DemoApiService apiService}) : _apiService = apiService;

  /// Fetches all posts from the API.
  ///
  /// Returns a [Result] containing either a list of [DemoPostModel] on success,
  /// or an [Exception] on failure.
  Future<Result<List<DemoPostModel>>> getPosts() async {
    final result = await _apiService.getPosts();

    return switch (result) {
      Ok(value: final posts) => Result.ok(posts.map(DemoPostModel.fromDto).toList()),
      Error(error: final error) => Result.error(error),
    };
  }

  /// Fetches all posts from a specific user.
  ///
  /// Returns a [Result] containing either a list of [DemoPostModel] on success,
  /// or an [Exception] on failure.
  Future<Result<List<DemoPostModel>>> getPostsByUser(int userId) async {
    final result = await _apiService.getPostsByUser(userId);

    return switch (result) {
      Ok(value: final posts) => Result.ok(posts.map(DemoPostModel.fromDto).toList()),
      Error(error: final error) => Result.error(error),
    };
  }
}
