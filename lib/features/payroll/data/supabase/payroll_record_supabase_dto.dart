import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';

/// Supabase DTO mapping `public.payroll_records` snake_case rows to domain [PayrollRecord].
final class PayrollRecordSupabaseDto {
  const PayrollRecordSupabaseDto({
    required this.payrollId,
    required this.periodId,
    required this.barberId,
    required this.totalHaircuts,
    required this.grossSales,
    required this.ownerSharePct,
    required this.barberSharePct,
    required this.ownerShareAmount,
    required this.barberPayAmount,
    required this.status,
    this.paidAt,
  });

  factory PayrollRecordSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return PayrollRecordSupabaseDto(
      payrollId: map['payroll_id'] as String,
      periodId: map['period_id'] as String,
      barberId: map['barber_id'] as String,
      totalHaircuts: SupabaseParseUtils.parseInt(map['total_haircuts']),
      grossSales: SupabaseParseUtils.parseDecimal(map['gross_sales']),
      ownerSharePct: SupabaseParseUtils.parseDecimal(map['owner_share_pct']),
      barberSharePct: SupabaseParseUtils.parseDecimal(map['barber_share_pct']),
      ownerShareAmount:
          SupabaseParseUtils.parseDecimal(map['owner_share_amount']),
      barberPayAmount:
          SupabaseParseUtils.parseDecimal(map['barber_pay_amount']),
      status: map['status'] as String,
      paidAt: SupabaseParseUtils.parseNullableTimestamp(map['paid_at']),
    );
  }

  factory PayrollRecordSupabaseDto.fromDomain(PayrollRecord record) {
    return PayrollRecordSupabaseDto(
      payrollId: record.payrollId,
      periodId: record.periodId,
      barberId: record.barberId,
      totalHaircuts: record.totalHaircuts,
      grossSales: record.grossSales,
      ownerSharePct: record.ownerSharePct,
      barberSharePct: record.barberSharePct,
      ownerShareAmount: record.ownerShareAmount,
      barberPayAmount: record.barberPayAmount,
      status: record.status.dbValue,
      paidAt: record.paidAt,
    );
  }

  final String payrollId;
  final String periodId;
  final String barberId;
  final int totalHaircuts;
  final double grossSales;
  final double ownerSharePct;
  final double barberSharePct;
  final double ownerShareAmount;
  final double barberPayAmount;
  final String status;
  final DateTime? paidAt;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'payroll_id': payrollId,
      'period_id': periodId,
      'barber_id': barberId,
      'total_haircuts': totalHaircuts,
      'gross_sales': MoneyMath.round2(grossSales),
      'owner_share_pct': MoneyMath.round2(ownerSharePct),
      'barber_share_pct': MoneyMath.round2(barberSharePct),
      'owner_share_amount': MoneyMath.round2(ownerShareAmount),
      'barber_pay_amount': MoneyMath.round2(barberPayAmount),
      'status': status,
      'paid_at': paidAt?.toUtc().toIso8601String(),
    };
  }

  PayrollRecord toDomain() {
    return PayrollRecord(
      payrollId: payrollId,
      periodId: periodId,
      barberId: barberId,
      totalHaircuts: totalHaircuts,
      grossSales: grossSales,
      ownerSharePct: ownerSharePct,
      barberSharePct: barberSharePct,
      ownerShareAmount: ownerShareAmount,
      barberPayAmount: barberPayAmount,
      status: PayrollRecordStatus.fromDbValue(status),
      paidAt: paidAt,
    );
  }
}
