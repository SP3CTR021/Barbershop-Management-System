import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_with_records.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';

/// Backend-agnostic contract for payroll configuration (`payroll_settings`),
/// 15-day period generation (`payroll_periods`), and barber payout records
/// (`payroll_records`).
abstract interface class PayrollRepository {
  Future<Result<PayrollSetting>> getActivePayrollSetting();

  Future<Result<List<PayrollSetting>>> getPayrollSettingsHistory();

  /// Creates a new active `PayrollSetting` (`ownerSharePct + barberSharePct == 100`)
  /// and closes any previous active setting (`effective_to`). Restricted to `OWNER`.
  Future<Result<PayrollSetting>> createPayrollSetting({
    required String createdByOwnerId,
    required double ownerSharePct,
    required double barberSharePct,
    int periodDays = 15,
    required DateTime effectiveFrom,
  });

  /// Generates a `DRAFT` payroll period and one `PayrollRecord` per barber
  /// using `PAID` haircut sales (`is_haircut = true`) within `[startDate, endDate]`.
  /// Rejects overlapping date ranges (`ConflictFailure`). Restricted to `OWNER`.
  Future<Result<PayrollPeriodWithRecords>> generatePayrollPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required String generatedByUserId,
  });

  Future<Result<PayrollPeriodWithRecords>> getPayrollPeriodWithRecords(
    String periodId,
  );

  Future<Result<List<PayrollPeriod>>> getPayrollPeriods({
    PayrollPeriodStatus? status,
  });

  Stream<Result<List<PayrollPeriod>>> watchPayrollPeriods();

  /// Transitions a `DRAFT` period to `APPROVED`, locking covered `PAID`
  /// transactions against voiding. Restricted to `OWNER`.
  Future<Result<PayrollPeriod>> approvePayrollPeriod({
    required String periodId,
    required String ownerUserId,
  });

  /// Marks an individual barber's `PayrollRecord` as `PAID` (requires parent
  /// period `APPROVED` or `PAID`). Automatically marks the parent `PayrollPeriod`
  /// as `PAID` once all its records are `PAID`. Restricted to `OWNER`.
  Future<Result<PayrollRecord>> markPayrollRecordPaid({
    required String payrollId,
    required String ownerUserId,
    DateTime? paidAt,
  });

  Future<Result<List<PayrollRecord>>> getPayrollRecordsForBarber(
    String barberId,
  );

  /// Returns `true` if [shopDate] falls inside an `APPROVED` or `PAID` payroll
  /// period (used to block voiding finalized `PAID` transactions).
  Future<Result<bool>> isDateLockedByPayroll(DateTime shopDate);
}
