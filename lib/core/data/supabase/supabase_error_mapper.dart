import 'dart:async';

import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Translates Supabase PostgREST, Auth, RPC prefix, and transport exceptions
/// into backend-agnostic [AppFailure] subtypes.
abstract final class SupabaseErrorMapper {
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Success<T>(await action());
    } catch (error) {
      return Failure<T>(map(error));
    }
  }

  /// Wraps a raw Supabase realtime/postgrest stream so data events become
  /// [Success] and stream errors become [Failure] with mapped [AppFailure].
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

    if (error is sb.PostgrestException) {
      return _mapPostgrest(error);
    }

    if (error is sb.AuthRetryableFetchException || error is TimeoutException) {
      return NetworkFailure(
        message: 'Network error while communicating with Supabase.',
        cause: error,
      );
    }

    if (error is sb.AuthException) {
      return _mapAuth(error);
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
        message: 'Unable to reach Supabase server.',
        cause: error,
      );
    }

    return UnknownFailure(
      message: text,
      cause: error,
    );
  }

  static AppFailure _mapPostgrest(sb.PostgrestException error) {
    final msg = error.message;

    // 1. Structured exceptions raised by our PL/pgSQL RPCs.
    if (msg.startsWith('NOT_FOUND:')) {
      return NotFoundFailure(
        message: msg.substring('NOT_FOUND:'.length).trim(),
        code: error.code,
        cause: error,
      );
    }
    if (msg.startsWith('PERMISSION_DENIED:')) {
      return PermissionDeniedFailure(
        message: msg.substring('PERMISSION_DENIED:'.length).trim(),
        code: error.code,
        cause: error,
      );
    }
    if (msg.startsWith('DUPLICATE_ENTRY:')) {
      return DuplicateEntryFailure(
        message: msg.substring('DUPLICATE_ENTRY:'.length).trim(),
        code: error.code,
        cause: error,
      );
    }
    if (msg.startsWith('VALIDATION_ERROR:')) {
      return ValidationFailure(
        message: msg.substring('VALIDATION_ERROR:'.length).trim(),
        code: error.code,
        cause: error,
      );
    }
    if (msg.startsWith('CONFLICT:')) {
      return ConflictFailure(
        message: msg.substring('CONFLICT:'.length).trim(),
        code: error.code,
        cause: error,
      );
    }

    // 2. Standard PostgreSQL / PostgREST SQLSTATE error codes.
    switch (error.code) {
      case '23505':
        return DuplicateEntryFailure(
          message: _duplicateMessage(error),
          code: error.code,
          cause: error,
        );
      case '23503':
        return NotFoundFailure(
          message: 'Referenced record does not exist or cannot be removed.',
          code: error.code,
          cause: error,
        );
      case '23514':
        return ValidationFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case '23P01':
        return ConflictFailure(
          message: 'Operation conflicts with an existing range or constraint.',
          code: error.code,
          cause: error,
        );
      case '42501':
        return PermissionDeniedFailure(
          message: msg,
          code: error.code,
          cause: error,
        );
      case 'PGRST116':
        return NotFoundFailure(
          message: 'Requested record was not found.',
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

  static AppFailure _mapAuth(sb.AuthException error) {
    final lower = error.message.toLowerCase();
    final code = error.code;

    if (code == 'user_already_exists' ||
        lower.contains('already registered') ||
        lower.contains('already exists')) {
      return DuplicateEntryFailure(
        message: error.message,
        field: 'email',
        code: code,
        cause: error,
      );
    }
    if (code == 'invalid_credentials' ||
        lower.contains('invalid login credentials')) {
      return UnauthenticatedFailure(
        message: 'Invalid username/email or password.',
        code: code,
        cause: error,
      );
    }
    if (error.statusCode == '401' || code == 'session_expired') {
      return UnauthenticatedFailure(
        message: error.message,
        code: code,
        cause: error,
      );
    }
    if (error.statusCode == '403') {
      return PermissionDeniedFailure(
        message: error.message,
        code: code,
        cause: error,
      );
    }
    return ValidationFailure(
      message: error.message,
      code: code,
      cause: error,
    );
  }

  static String _duplicateMessage(sb.PostgrestException error) {
    final details = error.details?.toString() ?? '';
    if (details.isNotEmpty) return 'Duplicate value: $details';
    return 'A record with the same unique value already exists.';
  }

  static bool _looksLikeNetworkError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('timed out');
  }
}
