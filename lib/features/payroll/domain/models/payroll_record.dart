import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';

const Object _unset = Object();

/// Domain model for `payroll_records` (resolves M:N `payroll_periods <-> barbers`).
///
/// Relationships:
/// - `payroll_periods` (1) -> `payroll_records` (M) via [periodId].
/// - `barbers` (1) -> `payroll_records` (M) via [barberId].
///
/// Uniqueness & history safety:
/// - `UNIQUE (period_id, barber_id)` — one payout record per barber per period.
/// - [ownerSharePct] and [barberSharePct] are snapshotted per Business Rule #6.
final class PayrollRecord {
  PayrollRecord({
    required this.payrollId,
    required this.periodId,
    required this.barberId,
    required this.totalHaircuts,
    required double grossSales,
    required double ownerSharePct,
    required double barberSharePct,
    required double ownerShareAmount,
    required double barberPayAmount,
    required this.status,
    this.paidAt,
  })  : grossSales = MoneyMath.round2(grossSales),
        ownerSharePct = MoneyMath.round2(ownerSharePct),
        barberSharePct = MoneyMath.round2(barberSharePct),
        ownerShareAmount = MoneyMath.round2(ownerShareAmount),
        barberPayAmount = MoneyMath.round2(barberPayAmount);

  final String payrollId;

  /// FK -> `payroll_periods.period_id`.
  final String periodId;

  /// FK -> `barbers.barber_id`.
  final String barberId;

  /// Count of `is_haircut = true` services in `PAID` transactions during the period.
  final int totalHaircuts;

  final double grossSales;

  /// Snapshot of `payroll_settings.owner_share_pct` (Business Rule #6).
  final double ownerSharePct;

  /// Snapshot of `payroll_settings.barber_share_pct` (Business Rule #6).
  final double barberSharePct;

  final double ownerShareAmount;
  final double barberPayAmount;
  final PayrollRecordStatus status;
  final DateTime? paidAt;

  PayrollRecord copyWith({
    String? payrollId,
    String? periodId,
    String? barberId,
    int? totalHaircuts,
    double? grossSales,
    double? ownerSharePct,
    double? barberSharePct,
    double? ownerShareAmount,
    double? barberPayAmount,
    PayrollRecordStatus? status,
    Object? paidAt = _unset,
  }) {
    return PayrollRecord(
      payrollId: payrollId ?? this.payrollId,
      periodId: periodId ?? this.periodId,
      barberId: barberId ?? this.barberId,
      totalHaircuts: totalHaircuts ?? this.totalHaircuts,
      grossSales: grossSales ?? this.grossSales,
      ownerSharePct: ownerSharePct ?? this.ownerSharePct,
      barberSharePct: barberSharePct ?? this.barberSharePct,
      ownerShareAmount: ownerShareAmount ?? this.ownerShareAmount,
      barberPayAmount: barberPayAmount ?? this.barberPayAmount,
      status: status ?? this.status,
      paidAt: identical(paidAt, _unset) ? this.paidAt : paidAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PayrollRecord &&
            other.payrollId == payrollId &&
            other.periodId == periodId &&
            other.barberId == barberId &&
            other.totalHaircuts == totalHaircuts &&
            other.grossSales == grossSales &&
            other.ownerSharePct == ownerSharePct &&
            other.barberSharePct == barberSharePct &&
            other.ownerShareAmount == ownerShareAmount &&
            other.barberPayAmount == barberPayAmount &&
            other.status == status &&
            other.paidAt == paidAt;
  }

  @override
  int get hashCode => Object.hash(
        payrollId,
        periodId,
        barberId,
        totalHaircuts,
        grossSales,
        ownerSharePct,
        barberSharePct,
        ownerShareAmount,
        barberPayAmount,
        status,
        paidAt,
      );

  @override
  String toString() =>
      'PayrollRecord(payrollId: $payrollId, barberId: $barberId, haircuts: $totalHaircuts, barberPayAmount: $barberPayAmount, status: ${status.dbValue})';
}
