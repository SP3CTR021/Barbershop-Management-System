import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Shared conversion helpers, deterministic document/lock IDs (Firestore
/// workaround for relational composite `UNIQUE` constraints), and role checks.
abstract final class FirestoreParseUtils {
  static const String uniqueConstraintsCollection = '_unique_constraints';
  static const String activePayrollSettingLockId = 'active_payroll_setting';
  static const String bootstrapOwnerLockId = 'bootstrap_owner';

  static String roleDocId(RoleName roleName) =>
      'role_${roleName.dbValue.toLowerCase()}';

  /// Enforces `UNIQUE (barber_id, work_date)` via deterministic document ID.
  static String attendanceDocId(String barberId, DateTime workDate) =>
      '${barberId}_${ShopDateUtils.formatIsoDate(workDate)}';

  /// Enforces `UNIQUE (period_id, barber_id)` via deterministic document ID.
  static String payrollRecordDocId(String periodId, String barberId) =>
      '${periodId}_$barberId';

  static String usernameLockId(String username) =>
      'username_${_sanitizeLockKey(username)}';

  static String emailLockId(String email) =>
      'email_${_sanitizeLockKey(email)}';

  static String serviceNameLockId(String name) =>
      'service_name_${_sanitizeLockKey(name)}';

  /// Enforces 1:1 `users <-> barbers` via `_unique_constraints` lock document.
  static String barberUserLockId(String userId) => 'barber_user_$userId';

  static String _sanitizeLockKey(String raw) =>
      raw.trim().toLowerCase().replaceAll('/', '_');

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
    if (value is fs.Timestamp) {
      return ShopDateUtils.normalizeDate(value.toDate().toUtc());
    }
    if (value is DateTime) return ShopDateUtils.normalizeDate(value);
    if (value is String) return ShopDateUtils.parseIsoDate(value);
    throw FormatException('Expected date value, got "$value".');
  }

  static DateTime? parseNullableDate(Object? value) {
    if (value == null) return null;
    return parseDate(value);
  }

  static DateTime parseTimestamp(Object? value) {
    if (value is fs.Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.parse(value.trim()).toUtc();
    throw FormatException('Expected timestamp value, got "$value".');
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

  static String? cleanNullableText(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Resolves an acting user's role inside or outside a Firestore transaction.
  /// Checks denormalized `users.roleName` first and falls back to `roles/{roleId}`.
  static Future<RoleName> assertActiveUserRole(
    fs.FirebaseFirestore firestore, {
    required String actingUserId,
    required List<RoleName> allowedRoles,
    fs.Transaction? tx,
  }) async {
    final userRef = firestore.collection('users').doc(actingUserId);
    final userSnap = tx != null ? await tx.get(userRef) : await userRef.get();

    if (!userSnap.exists || userSnap.data() == null) {
      throw NotFoundFailure(
        message: 'Acting user $actingUserId not found.',
        entityName: 'User',
        entityId: actingUserId,
      );
    }

    final userData = userSnap.data()!;
    final isActive = userData['isActive'] as bool? ?? false;
    if (!isActive) {
      throw PermissionDeniedFailure(
        message: 'User $actingUserId is inactive.',
      );
    }

    RoleName roleName;
    final denormalizedRole = userData['roleName'] as String?;
    if (denormalizedRole != null && denormalizedRole.isNotEmpty) {
      roleName = RoleName.fromDbValue(denormalizedRole);
    } else {
      final roleId = userData['roleId'] as String;
      final roleRef = firestore.collection('roles').doc(roleId);
      final roleSnap = tx != null ? await tx.get(roleRef) : await roleRef.get();
      if (!roleSnap.exists || roleSnap.data() == null) {
        throw NotFoundFailure(
          message: 'Role $roleId for user $actingUserId not found.',
          entityName: 'Role',
          entityId: roleId,
        );
      }
      roleName = RoleName.fromDbValue(roleSnap.data()!['roleName'] as String);
    }

    if (!allowedRoles.contains(roleName)) {
      throw PermissionDeniedFailure(
        message:
            'Role ${roleName.dbValue} is not allowed to perform this action.',
      );
    }
    return roleName;
  }
}
