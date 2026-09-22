import 'package:freezed_annotation/freezed_annotation.dart';

part 'loading_manager.freezed.dart';

// A model to represent the loading state of a specific operation
@freezed
abstract class OperationLoadingState<T> with _$OperationLoadingState<T> {
  const factory OperationLoadingState({
    required T operation,
    @Default(false) bool isLoading,
    DateTime? startTime,
    DateTime? endTime,
    @Default(0) int attemptCount,
  }) = _OperationLoadingState;

  const OperationLoadingState._();

  // Calculate duration of loading if applicable
  Duration? get duration {
    if (startTime != null) {
      final end = endTime ?? DateTime.now();
      return end.difference(startTime!);
    }
    return null;
  }
}

// State for the LoadingManager
@Freezed(genericArgumentFactories: true)
abstract class LoadingManagerState<T> with _$LoadingManagerState<T> {
  const factory LoadingManagerState({
    @Default({}) Map<T, OperationLoadingState<T>> operationStates,
    @Default(false) bool globalLoading,
  }) = _LoadingManagerState;
}

class LoadingManager<T> {
  LoadingManagerState<T> _state = LoadingManagerState<T>();

  /// Set the loading state for a specific operation
  void setLoading(T operation, {required bool isLoading}) {
    final now = DateTime.now();
    final currentState = _state.operationStates[operation] ?? OperationLoadingState<T>(operation: operation);

    final newState =
        isLoading
            ? currentState.copyWith(isLoading: true, startTime: now, attemptCount: currentState.attemptCount + 1)
            : currentState.copyWith(isLoading: false, endTime: now);

    final updatedStates = Map<T, OperationLoadingState<T>>.from(_state.operationStates);
    updatedStates[operation] = newState;

    _state = _state.copyWith(
      operationStates: updatedStates,
      globalLoading: updatedStates.values.any((state) => state.isLoading),
    );
  }

  /// Check if a specific operation is loading
  bool isOperationLoading(T operation) => _state.operationStates[operation]?.isLoading ?? false;

  /// Get loading state for a specific operation
  OperationLoadingState<T>? getOperationState(T operation) => _state.operationStates[operation];

  /// Check if any operation is loading
  bool get isLoading => _state.globalLoading;

  /// Get the map of all loading states (simplified boolean map)
  Map<T, bool> get loadingStates {
    final result = <T, bool>{};
    for (final entry in _state.operationStates.entries) {
      result[entry.key] = entry.value.isLoading;
    }
    return result;
  }

  /// Get all operation loading states (detailed states)
  Map<T, OperationLoadingState<T>> get operationStates => Map<T, OperationLoadingState<T>>.from(_state.operationStates);

  /// Start a new operation and return a function to mark it as completed
  Function() startOperation(T operation) {
    setLoading(operation, isLoading: true);
    return () => setLoading(operation, isLoading: false);
  }

  /// Get the total number of operations that have been started
  int get operationCount => _state.operationStates.length;

  /// Get statistics about loading operations
  Map<String, dynamic> getStatistics() {
    int completed = 0;
    int inProgress = 0;
    Duration totalDuration = Duration.zero;

    for (final state in _state.operationStates.values) {
      if (state.isLoading) {
        inProgress++;
      } else if (state.endTime != null) {
        completed++;
        final duration = state.duration;
        if (duration != null) {
          totalDuration += duration;
        }
      }
    }

    return {
      'total': operationCount,
      'completed': completed,
      'inProgress': inProgress,
      'averageDurationMs': completed > 0 ? totalDuration.inMilliseconds ~/ completed : 0,
    };
  }

  /// Clear all loading states
  void reset() {
    _state = LoadingManagerState<T>();
  }
}
