import 'package:codebase_ai/data/services/api/demo/demo_api_service.dart';
import 'package:codebase_ai/domain/models/demo/demo_user_model.dart';
import 'package:codebase_ai/utils/result.dart';

class DemoUserRepository {
  final DemoApiService _apiService;

  DemoUserRepository({required DemoApiService apiService}) : _apiService = apiService;

  /// Fetches all users from the API.
  ///
  /// Returns a [Result] containing either a list of [DemoUserModel] on success,
  /// or an [Exception] on failure.
  Future<Result<List<DemoUserModel>>> getUsers() async {
    final result = await _apiService.getUsers();

    return switch (result) {
      Ok(value: final users) => Result.ok(users.map(DemoUserModel.fromDto).toList()),
      Error(error: final error) => Result.error(error),
    };
  }
}
