import 'package:cloud_functions/cloud_functions.dart';

/// One sealed hierarchy for every backend failure, in ONE file — sealed classes
/// require that, and it is what makes the switch exhaustive without a `default`.
///
/// Maps the HttpsError codes the server throws (docs/05-API-CONTRACT-V2.md §1).
sealed class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;

  /// Only these three may be retried automatically, and never for a
  /// non-idempotent call that carries no requestId.
  bool get isRetryable => switch (this) {
        TransientFailure() || ServerFailure() || ConflictFailure() => true,
        _ => false,
      };

  static ApiFailure fromFunctions(FirebaseFunctionsException e) {
    final details = e.details is Map ? Map<String, Object?>.from(e.details as Map) : null;
    final message = e.message ?? 'Something went wrong';
    return switch (e.code) {
      'invalid-argument' => ValidationFailure(message, _issuesOf(details)),
      'unauthenticated' => AuthFailure(message),
      'permission-denied' => PermissionFailure(message, details?['reason'] as String?),
      'not-found' => NotFoundFailure(message),
      'already-exists' => ConflictFailure(message),
      'aborted' => ConflictFailure(message),
      'resource-exhausted' => QuotaFailure(message, _dateOf(details?['resetAt']), reason: details?['reason'] as String?),
      'failed-precondition' => PreconditionFailure(
          message,
          details?['reason'] as String?,
          details?['minVersion'] as String?,
          limitSeconds: (details?['limitSeconds'] as num?)?.toInt(),
        ),
      'unavailable' || 'deadline-exceeded' => TransientFailure(message),
      'internal' || 'data-loss' || 'unknown' => ServerFailure(message),
      _ => ServerFailure(message),
    };
  }

  static List<ValidationIssue> _issuesOf(Map<String, Object?>? details) {
    final raw = details?['issues'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (m) => ValidationIssue(
            path: m['path']?.toString() ?? '',
            message: m['message']?.toString() ?? '',
          ),
        )
        .toList();
  }

  static DateTime? _dateOf(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}

class ValidationIssue {
  const ValidationIssue({required this.path, required this.message});
  final String path;
  final String message;
}

final class AuthFailure extends ApiFailure {
  const AuthFailure(super.message);
}

final class PermissionFailure extends ApiFailure {
  const PermissionFailure(super.message, this.reason);
  final String? reason;
  bool get isAnonymous => reason == 'anonymous';
}

final class NotFoundFailure extends ApiFailure {
  const NotFoundFailure(super.message);
}

final class ValidationFailure extends ApiFailure {
  const ValidationFailure(super.message, this.issues);
  final List<ValidationIssue> issues;
}

/// The paywall trigger. v1 keyed the "Premium Required" dialog off HTTP 402 —
/// the v2 equivalent is THIS type. Missing it makes the paywall silently vanish.
final class QuotaFailure extends ApiFailure {
  const QuotaFailure(super.message, this.resetAt, {this.reason});
  final DateTime? resetAt;

  /// `quota` (or null from older servers) = daily minutes; `aiDailyLimit` = AI calls; `tooManyActiveJobs`.
  final String? reason;
  bool get isCredits => reason == null || reason == 'quota';
}

final class PreconditionFailure extends ApiFailure {
  const PreconditionFailure(super.message, this.reason, this.minVersion, {this.limitSeconds});
  final String? reason;
  final String? minVersion;

  /// Set for `durationLimit`.
  final int? limitSeconds;
  bool get needsAppUpdate => minVersion != null;
  bool get isSafetyBlocked => reason == 'safety';
  bool get isDurationLimit => reason == 'durationLimit';
}

final class ConflictFailure extends ApiFailure {
  const ConflictFailure(super.message);
}

final class TransientFailure extends ApiFailure {
  const TransientFailure(super.message);
}

final class ServerFailure extends ApiFailure {
  const ServerFailure(super.message);
}

/// Only from a connectivity pre-flight. The Flutter plugin folds real transport
/// errors into unavailable/deadline-exceeded, so do NOT branch on a separate
/// network error domain (flutter-firebase-contract/error-mapping).
final class NetworkFailure extends ApiFailure {
  const NetworkFailure(super.message);
}
