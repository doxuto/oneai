import 'package:freezed_annotation/freezed_annotation.dart';

part 'result.freezed.dart';

/// Utility class to wrap result data
///
/// Evaluate the result using a switch statement:
/// ```dart
/// switch (result) {
///   case Ok(:final value): {
///     print(value);
///   }
///   case Error(:final error): {
///     print(error);
///   }
/// }
/// ```
@freezed
sealed class Result<T> with _$Result<T> {
  const Result._();

  /// Creates a successful [Result], completed with the specified [value].
  const factory Result.ok(T value) = Ok;

  /// Creates an error [Result], completed with the specified [error].
  const factory Result.error(Exception error) = Error;
}
