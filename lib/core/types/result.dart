import 'package:barbershop_management_app/core/errors/app_failure.dart';

/// Backend-agnostic result wrapper separating expected domain failures from
/// thrown programming errors.
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  AppFailure? get failureOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final failure) => failure,
      };

  /// Returns the wrapped value or throws the underlying [AppFailure].
  T getOrThrow() => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>(:final failure) => throw failure,
      };

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppFailure failure) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final value) => onSuccess(value),
      Failure<T>(:final failure) => onFailure(failure),
    };
  }

  Result<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      Success<T>(:final value) => Success<R>(transform(value)),
      Failure<T>(:final failure) => Failure<R>(failure),
    };
  }
}

/// Successful outcome carrying a [value].
final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Success<T> && other.value == value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// Failed outcome carrying a typed [AppFailure].
final class Failure<T> extends Result<T> {
  const Failure(this.failure);

  final AppFailure failure;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Failure<T> && other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'Failure($failure)';
}
