import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Conversion and query helpers for Supabase PostgREST JSON payloads
/// (`NUMERIC` strings/numbers, `DATE`, `TIME`, `TIMESTAMPTZ`) and shared
/// acting-user role verification.
abstract final class SupabaseParseUtils {
  static double parseDecimal(Object? value) {
    if (value is num) return MoneyMath.round2(value.toDouble());
    if (value is String) {
      return MoneyMath.round2(double.parse(value.trim()));
    }
    throw FormatException('Expected numeric value, got "$value".');
  }

  static int parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value.trim());
    throw FormatException('Expected integer value, got "$value".');
  }

  static DateTime parseDate(Object? value) {
    if (value is DateTime) return ShopDateUtils.normalizeDate(value);
    if (value is String) return ShopDateUtils.parseIsoDate(value);
    throw FormatException('Expected ISO date value, got "$value".');
  }

  static DateTime? parseNullableDate(Object? value) {
    if (value == null) return null;
    return parseDate(value);
  }

  static DateTime parseTimestamp(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value.trim()).toUtc();
    throw FormatException('Expected ISO timestamp value, got "$value".');
  }

  static DateTime? parseNullableTimestamp(Object? value) {
    if (value == null) return null;
    return parseTimestamp(value);
  }

  static ShopTime parseTime(Object? value) {
    if (value is ShopTime) return value;
    if (value is String) return ShopTime.parse(value);
    throw FormatException('Expected ISO time value, got "$value".');
  }

  static ShopTime? parseNullableTime(Object? value) {
    if (value == null) return null;
    return parseTime(value);
  }

  /// Normalizes optional string inputs so empty/whitespace strings map to null.
  static String? cleanNullableText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Verifies that [actingUserId] exists, `is_active = true`, and holds one of
  /// [allowedRoles] before running direct PostgREST mutations.
  static Future<RoleName> assertActiveUserRole(
    sb.SupabaseClient client, {
    required String actingUserId,
    required List<RoleName> allowedRoles,
  }) async {
    final row = await client
        .from('users')
        .select('is_active, roles!inner(role_name)')
        .eq('user_id', actingUserId)
        .maybeSingle();

    if (row == null) {
      throw NotFoundFailure(
        message: 'Acting user $actingUserId not found.',
        entityName: 'User',
        entityId: actingUserId,
      );
    }

    final isActive = row['is_active'] as bool? ?? false;
    if (!isActive) {
      throw PermissionDeniedFailure(
        message: 'User $actingUserId is inactive.',
      );
    }

    final roleData = row['roles'] as Map<String, dynamic>;
    final roleName = RoleName.fromDbValue(roleData['role_name'] as String);
    if (!allowedRoles.contains(roleName)) {
      throw PermissionDeniedFailure(
        message:
            'Role ${roleName.dbValue} is not allowed to perform this action.',
      );
    }
    return roleName;
  }
}
