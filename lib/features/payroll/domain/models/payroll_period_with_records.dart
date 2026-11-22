import 'package:barbershop_management_app/core/utils/collection_equality.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';

/// Aggregate read model pairing a [PayrollPeriod], the [PayrollSetting] applied
/// to it, and its generated per-barber [PayrollRecord] rows.
final class PayrollPeriodWithRecords {
  PayrollPeriodWithRecords({
    required this.period,
    required this.setting,
    required List<PayrollRecord> records,
  }) : records = List<PayrollRecord>.unmodifiable(records);

  final PayrollPeriod period;
  final PayrollSetting setting;
  final List<PayrollRecord> records;

  int get totalHaircuts =>
      records.fold<int>(0, (acc, record) => acc + record.totalHaircuts);

  double get totalGrossSales =>
      MoneyMath.sum(records.map((record) => record.grossSales));

  double get totalOwnerShareAmount =>
      MoneyMath.sum(records.map((record) => record.ownerShareAmount));

  double get totalBarberPayAmount =>
      MoneyMath.sum(records.map((record) => record.barberPayAmount));

  PayrollPeriodWithRecords copyWith({
    PayrollPeriod? period,
    PayrollSetting? setting,
    List<PayrollRecord>? records,
  }) {
    return PayrollPeriodWithRecords(
      period: period ?? this.period,
      setting: setting ?? this.setting,
      records: records ?? this.records,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PayrollPeriodWithRecords &&
            other.period == period &&
            other.setting == setting &&
            listEquals(other.records, records);
  }

  @override
  int get hashCode => Object.hash(period, setting, listHash(records));

  @override
  String toString() =>
      'PayrollPeriodWithRecords(periodId: ${period.periodId}, records: ${records.length}, totalGrossSales: $totalGrossSales)';
}
