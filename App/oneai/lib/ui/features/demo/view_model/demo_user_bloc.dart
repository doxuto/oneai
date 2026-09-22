import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/demo/demo_post_repository.dart';
import 'package:codebase_ai/data/repositories/demo/demo_user_repository.dart';
import 'package:codebase_ai/domain/models/demo/demo_post_model.dart';
import 'package:codebase_ai/domain/models/demo/demo_user_model.dart';
import 'package:codebase_ai/utils/loading_manager.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'demo_user_bloc.freezed.dart';

// Loading operations enum
enum DemoUserOperation { fetchUsers, fetchPosts }

// Events
@freezed
sealed class UserEvent with _$UserEvent {
  const factory UserEvent.getUsers() = GetUsersEvent;

  const factory UserEvent.getUserPosts({required int userId}) = GetUserPostsEvent;
}

// State
@freezed
sealed class UserState with _$UserState {
  const factory UserState({
    @Default(false) bool isLoading,
    String? errorMessage,
    @Default([]) List<DemoUserModel> users,
    @Default([]) List<DemoPostModel> posts,
    @Default({}) Map<DemoUserOperation, bool> loadingOperations,
  }) = _UserState;

  // Private constructor for adding methods
  const UserState._();

  // Method to check if a specific operation is loading
  bool isOperationLoading(DemoUserOperation operation) => loadingOperations[operation] ?? false;

  // Method to create a new state with updated loading for a specific operation
  UserState withOperationLoading({
    required DemoUserOperation operation,
    required bool isLoading,
    String? errorMessage,
  }) {
    final newLoadingOperations = Map<DemoUserOperation, bool>.from(loadingOperations);
    newLoadingOperations[operation] = isLoading;

    // Calculate global loading state - true if any operation is loading
    final globalLoading = newLoadingOperations.values.any((loading) => loading);

    return copyWith(isLoading: globalLoading, errorMessage: errorMessage, loadingOperations: newLoadingOperations);
  }
}

// Bloc
class DemoUserBloc extends Bloc<UserEvent, UserState> {
  final DemoUserRepository _userRepository;
  final DemoPostRepository _postRepository;
  final LoadingManager<DemoUserOperation> _loadingManager = LoadingManager<DemoUserOperation>();

  DemoUserBloc({required DemoUserRepository userRepository, required DemoPostRepository postRepository})
    : _userRepository = userRepository,
      _postRepository = postRepository,
      super(const UserState()) {
    on<GetUsersEvent>(_onGetUsers);
    on<GetUserPostsEvent>(_onGetUserPosts);
  }

  // Get the loading manager for direct access from outside
  LoadingManager<DemoUserOperation> get loadingManager => _loadingManager;

  Future<void> _onGetUsers(GetUsersEvent event, Emitter<UserState> emit) async {
    // Create a finish function to mark operation as complete when done
    final completeOperation = _loadingManager.startOperation(DemoUserOperation.fetchUsers);

    // Emit the new loading state
    emit(
      state.copyWith(
        isLoading: _loadingManager.isLoading,
        loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
      ),
    );

    try {
      final result = await _userRepository.getUsers();

      // Mark operation as complete
      completeOperation();

      if (result is Ok<List<DemoUserModel>>) {
        // Emit new state with users and updated loading state
        emit(
          state.copyWith(
            users: result.value,
            isLoading: _loadingManager.isLoading,
            loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
          ),
        );
      } else if (result is Error) {
        // Emit error state with updated loading state
        emit(
          state.copyWith(
            errorMessage: (result as Error).error.toString(),
            isLoading: _loadingManager.isLoading,
            loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
          ),
        );
      }
    } on Exception catch (e) {
      // Mark operation as complete even on error
      completeOperation();

      // Emit error state with updated loading state
      emit(
        state.copyWith(
          errorMessage: e.toString(),
          isLoading: _loadingManager.isLoading,
          loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
        ),
      );
    }
  }

  Future<void> _onGetUserPosts(GetUserPostsEvent event, Emitter<UserState> emit) async {
    // Create a finish function to mark operation as complete when done
    final completeOperation = _loadingManager.startOperation(DemoUserOperation.fetchPosts);

    // Emit the new loading state
    emit(
      state.copyWith(
        isLoading: _loadingManager.isLoading,
        loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
      ),
    );

    try {
      final result = await _postRepository.getPostsByUser(event.userId);

      // Mark operation as complete
      completeOperation();

      if (result is Ok<List<DemoPostModel>>) {
        // Emit new state with posts and updated loading state
        emit(
          state.copyWith(
            posts: result.value,
            isLoading: _loadingManager.isLoading,
            loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
          ),
        );
      } else if (result is Error) {
        // Emit error state with updated loading state
        emit(
          state.copyWith(
            errorMessage: (result as Error).error.toString(),
            isLoading: _loadingManager.isLoading,
            loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
          ),
        );
      }
    } on Exception catch (e) {
      // Mark operation as complete even on error
      completeOperation();

      // Emit error state with updated loading state
      emit(
        state.copyWith(
          errorMessage: e.toString(),
          isLoading: _loadingManager.isLoading,
          loadingOperations: Map<DemoUserOperation, bool>.from(_loadingManager.loadingStates),
        ),
      );
    }
  }

  // Reset all loading states
  void resetLoadingStates() {
    _loadingManager.reset();
    add(const UserEvent.getUsers());
  }
}
