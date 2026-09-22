import 'package:codebase_ai/data/services/model/demo/demo_post_dto.dart';
import 'package:codebase_ai/data/services/model/demo/demo_user_dto.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:dio/dio.dart';

/// Service to make API requests to the JSONPlaceholder demo API
///
/// Provides methods for fetching users, posts, and user-specific posts
class DemoApiService {
  final Dio _dio;

  /// Creates a DemoApiService instance with a Dio client configured for JSONPlaceholder API
  DemoApiService() : _dio = Dio(BaseOptions(baseUrl: 'https://jsonplaceholder.typicode.com'));

  /// Fetches all users from the API
  ///
  /// Returns a Result containing either a list of DemoUserDto objects or an error
  Future<Result<List<DemoUserDto>>> getUsers() async {
    try {
      final response = await _dio.get('/users');

      if (response.data == null) {
        return Result.error(Exception('Failed to load users: No data received'));
      }

      final List<DemoUserDto> users =
          (response.data as List).map((item) => DemoUserDto.fromJson(item as Map<String, dynamic>)).toList();

      return Result.ok(users);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to load users: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to load users: $e'));
    }
  }

  /// Fetches all posts from the API
  ///
  /// Returns a Result containing either a list of DemoPostDto objects or an error
  Future<Result<List<DemoPostDto>>> getPosts() async {
    try {
      final response = await _dio.get('/posts');

      if (response.data == null) {
        return Result.error(Exception('Failed to load posts: No data received'));
      }

      final List<DemoPostDto> posts =
          (response.data as List).map((item) => DemoPostDto.fromJson(item as Map<String, dynamic>)).toList();

      return Result.ok(posts);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to load posts: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to load posts: $e'));
    }
  }

  /// Fetches all posts for a specific user ID
  ///
  /// [userId] - The ID of the user whose posts should be retrieved
  ///
  /// Returns a Result containing either a list of DemoPostDto objects or an error
  Future<Result<List<DemoPostDto>>> getPostsByUser(int userId) async {
    try {
      final response = await _dio.get('/posts', queryParameters: {'userId': userId});

      if (response.data == null) {
        return Result.error(Exception('Failed to load user posts: No data received'));
      }

      final List<DemoPostDto> posts =
          (response.data as List).map((item) => DemoPostDto.fromJson(item as Map<String, dynamic>)).toList();

      return Result.ok(posts);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to load user posts: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to load user posts: $e'));
    }
  }
}
