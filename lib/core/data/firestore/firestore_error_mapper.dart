import 'dart:async';

import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Translates Cloud Firestore and Firebase Auth exceptions into backend-agnostic
/// [AppFailure] subtypes matching the Supabase error contract.
abstract final class FirestoreErrorMapper {
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error) {
      return Failure<T>(map(error));
    }
  }

  /// Wraps a Firestore snapshot stream so data events become [Success] and
  /// errors become [Failure] with mapped [AppFailure].
  static Stream<Result<T>> guardStream<T>(Stream<T> source) {
    return source.transform(
      StreamTransformer<T, Result<T>>.fromHandlers(
        handleData: (data, sink) => sink.add(Success<T>(data)),
        handleError: (error, _, sink) => sink.add(Failure<T>(map(error))),
      ),
    );
  }

  static AppFailure map(Object error) {
    if (error is AppFailure) return error;

    if (error is fs.FirebaseException) {
      return _mapFirebaseException(error);
    }

    if (error is TimeoutException) {
      return NetworkFailure(
        message: 'Network timeout while communicating with Firebase.',
        cause: error,
      );
    }

    if (error is FormatException) {
      return ValidationFailure(
        message: error.message,
        cause: error,
      );
    }

    final text = error.toString();
    if (_looksLikeNetworkError(text)) {
      return NetworkFailure(
        message: 'Unable to reach Firebase services.',
        cause: error,
      );
    }

    return UnknownFailure(
      message: text,
      cause: error,
    );
  }

  static AppFailure _mapFirebaseException(fs.FirebaseException error) {
    final code = error.code.toLowerCase();
    final msg = error.message ?? error.code;

    switch (code) {
      // Cloud Firestore error codes
      case 'permission-denied':
        return PermissionDeniedFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'not-found':
        return NotFoundFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'already-exists':
        return DuplicateEntryFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'aborted':
      case 'failed-precondition':
        return ConflictFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return NetworkFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'unauthenticated':
        return UnauthenticatedFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'invalid-argument':
        return ValidationFailure(
          message: msg,
          code: error.code,
          cause: error,
        );

      // Firebase Auth error codes (both inherit `FirebaseException`)
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return UnauthenticatedFailure(
          message: 'Invalid username/email or password.',
          code: error.code,
          cause: error,
        );
      case 'user-disabled':
        return PermissionDeniedFailure(
          message: 'This user account has been disabled.',
          code: error.code,
          cause: error,
        );
      case 'email-already-in-use':
        return DuplicateEntryFailure(
          message: 'An account with that email already exists.',
          field: 'email',
          code: error.code,
          cause: error,
        );
      case 'invalid-email':
      case 'weak-password':
        return ValidationFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'network-request-failed':
      case 'too-many-requests':
        return NetworkFailure(
          message: msg,
          code: error.code,
          cause: error,
        );

      default:
        if (_looksLikeNetworkError(msg)) {
          return NetworkFailure(
            message: msg,
            code: error.code,
            cause: error,
          );
        }
        return UnknownFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
    }
  }

  static bool _looksLikeNetworkError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('network') ||
        lower.contains('socketexception') ||
        lower.contains('unavailable') ||
        lower.contains('timed out') ||
        lower.contains('failed host lookup');
  }
}
