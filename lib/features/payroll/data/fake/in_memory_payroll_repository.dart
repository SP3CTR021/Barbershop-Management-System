import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_with_records.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/payroll/domain/services/payroll_calculator.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// In-memory fake implementation of [PayrollRepository].
final class InMemoryPayrollRepository implements PayrollRepository {
  InMemoryPayrollRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<PayrollSetting>> getActivePayrollSetting() {
    return _db.guard(() {
      final active = _findActiveSetting();
      if (active == null) {
        throw const NotFoundFailure(
          message: 'No active payroll setting is configured.',
          entityName: 'PayrollSetting',
        );
      }
      return active;
    });
  }

  @override
  Future<Result<List<PayrollSetting>>> getPayrollSettingsHistory() {
    return _db.guard(() {
      final list = _db.payrollSettings.values.toList(growable: false)
        ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
      return list;
    });
  }

  @override
  Future<Result<PayrollSetting>> createPayrollSetting({
    required String createdByOwnerId,
    required double ownerSharePct,
    required double barberSharePct,
    int periodDays = 15,
    required DateTime effectiveFrom,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: createdByOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final roundedOwner = MoneyMath.round2(ownerSharePct);
      final roundedBarber = MoneyMath.round2(barberSharePct);
      if (roundedOwner < 0 ||
          roundedBarber < 0 ||
          !MoneyMath.sharesSumTo100(roundedOwner, roundedBarber)) {
        throw const ValidationFailure(
          message: 'Owner and barber share percentages must sum to 100.00.',
        );
      }
      if (periodDays <= 0) {
        throw const ValidationFailure(
          message: 'periodDays must be greater than zero.',
          field: 'periodDays',
        );
      }

      final normalizedFrom = ShopDateUtils.normalizeDate(effectiveFrom);
      final prev = _findActiveSetting();
      if (prev != null) {
        final dayBefore = normalizedFrom.subtract(const Duration(days: 1));
        final closedTo =
            dayBefore.isBefore(prev.effectiveFrom) ? prev.effectiveFrom : dayBefore;
        _db.payrollSettings[prev.settingId] = prev.copyWith(effectiveTo: closedTo);
      }

      final created = PayrollSetting(
        settingId: _db.nextId(),
        createdBy: createdByOwnerId,
        ownerSharePct: roundedOwner,
        barberSharePct: roundedBarber,
        periodDays: periodDays,
        effectiveFrom: normalizedFrom,
        effectiveTo: null,
      );
      _db.payrollSettings[created.settingId] = created;
      _db.notifyChanged();
      return created;
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> generatePayrollPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required String generatedByUserId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: generatedByUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final normalizedStart = ShopDateUtils.normalizeDate(startDate);
      final normalizedEnd = ShopDateUtils.normalizeDate(endDate);
      if (normalizedEnd.isBefore(normalizedStart)) {
        throw const ValidationFailure(
          message: 'endDate cannot precede startDate.',
        );
      }

      final activeSetting = _findActiveSetting();
      if (activeSetting == null) {
        throw const NotFoundFailure(
          message: 'No active payroll setting is configured.',
          entityName: 'PayrollSetting',
        );
      }

      for (final existing in _db.payrollPeriods.values) {
        final overlaps = !normalizedEnd.isBefore(existing.startDate) &&
            !normalizedStart.isAfter(existing.endDate);
        if (overlaps) {
          throw ConflictFailure(
            message:
                'Payroll period ${ShopDateUtils.formatIsoDate(normalizedStart)}..${ShopDateUtils.formatIsoDate(normalizedEnd)} overlaps an existing period.',
          );
        }
      }

      final activeBarberIds = _db.barbers.values
          .where((b) => b.status == BarberStatus.active)
          .map((b) => b.barberId)
          .toSet();

      final details = _db.transactions.values.map((tx) {
        final items =
            _db.transactionItemsByTxId[tx.transactionId] ??
                const <TransactionItem>[];
        final payments = _db.payments.values
            .where((p) => p.transactionId == tx.transactionId)
            .toList(growable: false);
        return TransactionWithDetails(
          transaction: tx,
          items: items,
          payments: payments,
        );
      });

      final periodId = _db.nextId();
      final period = PayrollPeriod(
        periodId: periodId,
        settingId: activeSetting.settingId,
        generatedBy: generatedByUserId,
        startDate: normalizedStart,
        endDate: normalizedEnd,
        status: PayrollPeriodStatus.draft,
        generatedAt: DateTime.now().toUtc(),
      );

      final records = PayrollCalculator.computeFromDetails(
        periodId: periodId,
        setting: activeSetting,
        startDate: normalizedStart,
        endDate: normalizedEnd,
        transactions: details,
        barberIdsToInclude: activeBarberIds,
        payrollIdGenerator: (barberId) => '${periodId}_$barberId',
      );

      _db.payrollPeriods[periodId] = period;
      for (final record in records) {
        _db.payrollRecords[record.payrollId] = record;
      }
      _db.notifyChanged();

      return PayrollPeriodWithRecords(
        period: period,
        setting: activeSetting,
        records: records,
      );
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> getPayrollPeriodWithRecords(
    String periodId,
  ) {
    return _db.guard(() {
      final period = _db.payrollPeriods[periodId];
      if (period == null) {
        throw NotFoundFailure(
          message: 'Payroll period $periodId not found.',
          entityName: 'PayrollPeriod',
          entityId: periodId,
        );
      }
      final setting = _db.payrollSettings[period.settingId];
      if (setting == null) {
        throw NotFoundFailure(
          message: 'Payroll setting ${period.settingId} not found.',
          entityName: 'PayrollSetting',
          entityId: period.settingId,
        );
      }
      final records = _db.payrollRecords.values
          .where((r) => r.periodId == periodId)
          .toList(growable: false)
        ..sort((a, b) => a.barberId.compareTo(b.barberId));

      return PayrollPeriodWithRecords(
        period: period,
        setting: setting,
        records: records,
      );
    });
  }

  @override
  Future<Result<List<PayrollPeriod>>> getPayrollPeriods({
    PayrollPeriodStatus? status,
  }) {
    return _db.guard(() => _listPeriods(status: status));
  }

  @override
  Stream<Result<List<PayrollPeriod>>> watchPayrollPeriods() {
    return _db.watchQuery(() => _listPeriods());
  }

  @override
  Future<Result<PayrollPeriod>> approvePayrollPeriod({
    required String periodId,
    required String ownerUserId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: ownerUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existing = _db.payrollPeriods[periodId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Payroll period $periodId not found.',
          entityName: 'PayrollPeriod',
          entityId: periodId,
        );
      }
      if (existing.status != PayrollPeriodStatus.draft) {
        throw ConflictFailure(
          message:
              'Only DRAFT payroll periods can be approved (current: ${existing.status.dbValue}).',
        );
      }

      final updated = existing.copyWith(status: PayrollPeriodStatus.approved);
      _db.payrollPeriods[periodId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }

  @override
  Future<Result<PayrollRecord>> markPayrollRecordPaid({
    required String payrollId,
    required String ownerUserId,
    DateTime? paidAt,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: ownerUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existing = _db.payrollRecords[payrollId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Payroll record $payrollId not found.',
          entityName: 'PayrollRecord',
          entityId: payrollId,
        );
      }
      final period = _db.payrollPeriods[existing.periodId];
      if (period == null) {
        throw NotFoundFailure(
          message: 'Payroll period ${existing.periodId} not found.',
          entityName: 'PayrollPeriod',
          entityId: existing.periodId,
        );
      }
      if (period.status != PayrollPeriodStatus.approved &&
          period.status != PayrollPeriodStatus.paid) {
        throw const ValidationFailure(
          message: 'Payroll period must be APPROVED before paying barbers.',
        );
      }
      if (existing.status == PayrollRecordStatus.paid) {
        throw ConflictFailure(
          message: 'Payroll record $payrollId is already marked PAID.',
        );
      }

      final updated = existing.copyWith(
        status: PayrollRecordStatus.paid,
        paidAt: (paidAt ?? DateTime.now()).toUtc(),
      );
      _db.payrollRecords[payrollId] = updated;

      final anyPendingLeft = _db.payrollRecords.values.any(
        (r) =>
            r.periodId == existing.periodId &&
            r.status != PayrollRecordStatus.paid,
      );
      if (!anyPendingLeft) {
        _db.payrollPeriods[period.periodId] =
            period.copyWith(status: PayrollPeriodStatus.paid);
      }
      _db.notifyChanged();
      return updated;
    });
  }

  @override
  Future<Result<List<PayrollRecord>>> getPayrollRecordsForBarber(
    String barberId,
  ) {
    return _db.guard(() {
      final list = _db.payrollRecords.values
          .where((r) => r.barberId == barberId)
          .toList(growable: false)
        ..sort((a, b) {
          final aStart = _db.payrollPeriods[a.periodId]?.startDate ??
              DateTime.utc(1970);
          final bStart = _db.payrollPeriods[b.periodId]?.startDate ??
              DateTime.utc(1970);
          return bStart.compareTo(aStart);
        });
      return list;
    });
  }

  @override
  Future<Result<bool>> isDateLockedByPayroll(DateTime shopDate) {
    return _db.guard(() => _db.isDateLockedByPayroll(shopDate));
  }

  PayrollSetting? _findActiveSetting() {
    final active = _db.payrollSettings.values
        .where((s) => s.isActive)
        .toList(growable: false)
      ..sort((a, b) => b.effectiveFrom.compareTo(a.effectiveFrom));
    return active.isEmpty ? null : active.first;
  }

  List<PayrollPeriod> _listPeriods({PayrollPeriodStatus? status}) {
    final list = _db.payrollPeriods.values.where((p) {
      if (status != null && p.status != status) return false;
      return true;
    }).toList(growable: false)
      ..sort((a, b) => b.startDate.compareTo(a.startDate));
    return list;
  }
}
