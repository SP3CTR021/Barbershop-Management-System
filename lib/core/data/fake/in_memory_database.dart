import 'dart:async';

import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:uuid/uuid.dart';

/// Shared in-memory store backing all `InMemory*Repository` fakes for fast
/// contract tests without requiring network or emulator setup.
final class InMemoryDatabase {
  InMemoryDatabase({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  final Map<String, Role> roles = <String, Role>{};
  final Map<String, User> users = <String, User>{};
  final Map<String, String> authPasswordsByEmailLower = <String, String>{};
  final Map<String, String> authUserIdByEmailLower = <String, String>{};
  String? currentAuthenticatedUserId;

  final Map<String, Barber> barbers = <String, Barber>{};
  final Map<String, Customer> customers = <String, Customer>{};
  final Map<String, Service> services = <String, Service>{};
  final Map<String, Attendance> attendance = <String, Attendance>{};
  final Map<String, Transaction> transactions = <String, Transaction>{};
  final Map<String, List<TransactionItem>> transactionItemsByTxId =
      <String, List<TransactionItem>>{};
  final Map<String, Payment> payments = <String, Payment>{};
  final Map<String, PayrollSetting> payrollSettings =
      <String, PayrollSetting>{};
  final Map<String, PayrollPeriod> payrollPeriods = <String, PayrollPeriod>{};
  final Map<String, PayrollRecord> payrollRecords = <String, PayrollRecord>{};

  String nextId() => _uuid.v4();

  String roleDocId(RoleName roleName) =>
      'role_${roleName.dbValue.toLowerCase()}';

  String attendanceKey(String barberId, DateTime workDate) =>
      '${barberId}_${ShopDateUtils.formatIsoDate(workDate)}';

  Future<Result<T>> guard<T>(FutureOr<T> Function() action) async {
    try {
      return Success<T>(await action());
    } on AppFailure catch (failure) {
      return Failure<T>(failure);
    } on FormatException catch (error) {
      return Failure<T>(ValidationFailure(message: error.message, cause: error));
    } catch (error) {
      return Failure<T>(UnknownFailure(message: error.toString(), cause: error));
    }
  }

  void notifyChanged() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  Stream<Result<T>> watchQuery<T>(T Function() evaluate) {
    return Stream<Result<T>>.multi((controller) {
      void emitSnapshot() {
        if (controller.isClosed) return;
        try {
          controller.add(Success<T>(evaluate()));
        } on AppFailure catch (failure) {
          controller.add(Failure<T>(failure));
        } catch (error) {
          controller.add(
            Failure<T>(UnknownFailure(message: error.toString(), cause: error)),
          );
        }
      }

      emitSnapshot();
      final sub = _changes.stream.listen((_) => emitSnapshot());
      controller.onCancel = sub.cancel;
    });
  }

  Stream<User?> watchAuth(User? Function() evaluate) {
    return Stream<User?>.multi((controller) {
      void emitUser() {
        if (!controller.isClosed) {
          controller.add(evaluate());
        }
      }

      emitUser();
      final sub = _changes.stream.listen((_) => emitUser());
      controller.onCancel = sub.cancel;
    });
  }

  RoleName assertActiveUserRole({
    required String actingUserId,
    required List<RoleName> allowedRoles,
  }) {
    final user = users[actingUserId];
    if (user == null) {
      throw NotFoundFailure(
        message: 'Acting user $actingUserId not found.',
        entityName: 'User',
        entityId: actingUserId,
      );
    }
    if (!user.isActive) {
      throw PermissionDeniedFailure(
        message: 'User $actingUserId is inactive.',
      );
    }
    final role = roles[user.roleId];
    if (role == null) {
      throw NotFoundFailure(
        message: 'Role ${user.roleId} not found.',
        entityName: 'Role',
        entityId: user.roleId,
      );
    }
    if (!allowedRoles.contains(role.roleName)) {
      throw PermissionDeniedFailure(
        message:
            'Role ${role.roleName.dbValue} is not allowed to perform this action.',
      );
    }
    return role.roleName;
  }

  bool isDateLockedByPayroll(DateTime shopDate) {
    final normalized = ShopDateUtils.normalizeDate(shopDate);
    for (final period in payrollPeriods.values) {
      if (period.status != PayrollPeriodStatus.approved &&
          period.status != PayrollPeriodStatus.paid) {
        continue;
      }
      if (!normalized.isBefore(period.startDate) &&
          !normalized.isAfter(period.endDate)) {
        return true;
      }
    }
    return false;
  }

  Future<void> dispose() async {
    if (!_changes.isClosed) {
      await _changes.close();
    }
  }
}
