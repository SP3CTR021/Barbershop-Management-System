import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';

/// Domain model for `payroll_periods` (15-day payroll cycle header).
///
/// Relationships:
/// - `payroll_settings` (1) -> `payroll_periods` (M) via [settingId].
/// - `users` (1) -> `payroll_periods` (M) via [generatedBy].
/// - `payroll_periods` (1) -> `payroll_records` (1..M) (`ON DELETE CASCADE` for `DRAFT`).
final class PayrollPeriod {
  PayrollPeriod({
    required this.periodId,
    required this.settingId,
    required this.generatedBy,
    required DateTime startDate,
    required DateTime endDate,
    required this.status,
    required this.generatedAt,
  })  : startDate = ShopDateUtils.normalizeDate(startDate),
        endDate = ShopDateUtils.normalizeDate(endDate);

  final String periodId;

  /// FK -> `payroll_settings.setting_id`.
  final String settingId;

  /// FK -> `users.user_id`.
  final String generatedBy;

  final DateTime startDate;
  final DateTime endDate;
  final PayrollPeriodStatus status;
  final DateTime generatedAt;

  PayrollPeriod copyWith({
    String? periodId,
    String? settingId,
    String? generatedBy,
    DateTime? startDate,
    DateTime? endDate,
    PayrollPeriodStatus? status,
    DateTime? generatedAt,
  }) {
    return PayrollPeriod(
      periodId: periodId ?? this.periodId,
      settingId: settingId ?? this.settingId,
      generatedBy: generatedBy ?? this.generatedBy,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PayrollPeriod &&
            other.periodId == periodId &&
            other.settingId == settingId &&
            other.generatedBy == generatedBy &&
            other.startDate == startDate &&
            other.endDate == endDate &&
            other.status == status &&
            other.generatedAt == generatedAt;
  }

  @override
  int get hashCode => Object.hash(
        periodId,
        settingId,
        generatedBy,
        startDate,
        endDate,
        status,
        generatedAt,
      );

  @override
  String toString() =>
      'PayrollPeriod(periodId: $periodId, range: ${ShopDateUtils.formatIsoDate(startDate)}..${ShopDateUtils.formatIsoDate(endDate)}, status: ${status.dbValue})';
}
