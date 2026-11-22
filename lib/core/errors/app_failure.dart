/// Typed domain failure hierarchy shared across Supabase, Firestore, and
/// in-memory repositories so upper layers never handle backend-specific exceptions.
sealed class AppFailure implements Exception {
  const AppFailure({
    required this.message,
    this.code,
    this.cause,
  });

  final String message;
  final String? code;
  final Object? cause;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other.runtimeType == runtimeType &&
            other is AppFailure &&
            other.message == message &&
            other.code == code &&
            other.cause == cause;
  }

  @override
  int get hashCode => Object.hash(runtimeType, message, code, cause);

  @override
  String toString() {
    final codePart = code == null ? '' : ' (code: $code)';
    return '$runtimeType: $message$codePart';
  }
}

/// Returned when a requested entity or parent reference does not exist.
final class NotFoundFailure extends AppFailure {
  const NotFoundFailure({
    required super.message,
    this.entityName,
    this.entityId,
    super.code,
    super.cause,
  });

  final String? entityName;
  final String? entityId;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is NotFoundFailure &&
            super == other &&
            other.entityName == entityName &&
            other.entityId == entityId;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, entityName, entityId);
}

/// Returned when the acting user's role or security rule forbids the operation.
final class PermissionDeniedFailure extends AppFailure {
  const PermissionDeniedFailure({
    super.message = 'You do not have permission to perform this action.',
    super.code,
    super.cause,
  });
}

/// Returned when no signed-in user session is available for a protected operation.
final class UnauthenticatedFailure extends AppFailure {
  const UnauthenticatedFailure({
    super.message = 'Authentication is required.',
    super.code,
    super.cause,
  });
}

/// Returned when a unique constraint (e.g., username, email, service_name,
/// attendance per day, payroll record per period) is violated.
final class DuplicateEntryFailure extends AppFailure {
  const DuplicateEntryFailure({
    required super.message,
    this.field,
    this.value,
    super.code,
    super.cause,
  });

  final String? field;
  final String? value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DuplicateEntryFailure &&
            super == other &&
            other.field == field &&
            other.value == value;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, field, value);
}

/// Returned when domain invariants or business rules are violated
/// (e.g., barber not PRESENT today, voiding a transaction in an approved payroll).
final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    required super.message,
    this.field,
    super.code,
    super.cause,
  });

  final String? field;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ValidationFailure &&
            super == other &&
            other.field == field;
  }

  @override
  int get hashCode => Object.hash(super.hashCode, field);
}

/// Returned when an optimistic concurrency or state transition conflict occurs
/// (e.g., overlapping payroll period or already paid payroll record).
final class ConflictFailure extends AppFailure {
  const ConflictFailure({
    required super.message,
    super.code,
    super.cause,
  });
}

/// Returned when the backend is unreachable or a transport timeout occurs.
final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.message = 'Network error occurred.',
    super.code,
    super.cause,
  });
}

/// Fallback failure when an unexpected backend or runtime error is caught.
final class UnknownFailure extends AppFailure {
  const UnknownFailure({
    super.message = 'An unexpected error occurred.',
    super.code,
    super.cause,
  });
}
