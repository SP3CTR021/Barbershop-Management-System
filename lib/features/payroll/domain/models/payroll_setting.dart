import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';

const Object _unset = Object();

/// Domain model for `payroll_settings` storing configurable split percentages
/// (default 60% owner / 40% barber) and period cadence (15 days).
///
/// Relationships:
/// - `users` (`OWNER`, 1) -> `payroll_settings` (M) via [createdBy].
/// - `payroll_settings` (1) -> `payroll_periods` (M).
final class PayrollSetting {
  PayrollSetting({
    required this.settingId,
    required this.createdBy,
    required double ownerSharePct,
    required double barberSharePct,
    required this.periodDays,
    required DateTime effectiveFrom,
    DateTime? effectiveTo,
  })  : ownerSharePct = MoneyMath.round2(ownerSharePct),
        barberSharePct = MoneyMath.round2(barberSharePct),
        effectiveFrom = ShopDateUtils.normalizeDate(effectiveFrom),
        effectiveTo = effectiveTo == null
            ? null
            : ShopDateUtils.normalizeDate(effectiveTo);

  final String settingId;

  /// FK -> `users.user_id` (`OWNER` who configured this split).
  final String createdBy;

  final double ownerSharePct;
  final double barberSharePct;
  final int periodDays;
  final DateTime effectiveFrom;

  /// Null indicates this setting is currently active (`effective_to IS NULL`).
  final DateTime? effectiveTo;

  bool get isActive => effectiveTo == null;

  PayrollSetting copyWith({
    String? settingId,
    String? createdBy,
    double? ownerSharePct,
    double? barberSharePct,
    int? periodDays,
    DateTime? effectiveFrom,
    Object? effectiveTo = _unset,
  }) {
    return PayrollSetting(
      settingId: settingId ?? this.settingId,
      createdBy: createdBy ?? this.createdBy,
      ownerSharePct: ownerSharePct ?? this.ownerSharePct,
      barberSharePct: barberSharePct ?? this.barberSharePct,
      periodDays: periodDays ?? this.periodDays,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveTo: identical(effectiveTo, _unset)
          ? this.effectiveTo
          : effectiveTo as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PayrollSetting &&
            other.settingId == settingId &&
            other.createdBy == createdBy &&
            other.ownerSharePct == ownerSharePct &&
            other.barberSharePct == barberSharePct &&
            other.periodDays == periodDays &&
            other.effectiveFrom == effectiveFrom &&
            other.effectiveTo == effectiveTo;
  }

  @override
  int get hashCode => Object.hash(
        settingId,
        createdBy,
        ownerSharePct,
        barberSharePct,
        periodDays,
        effectiveFrom,
        effectiveTo,
      );

  @override
  String toString() =>
      'PayrollSetting(settingId: $settingId, split: $ownerSharePct/$barberSharePct, isActive: $isActive)';
}
