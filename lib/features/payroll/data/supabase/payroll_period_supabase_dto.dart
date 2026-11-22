import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';

/// Supabase DTO mapping `public.payroll_periods` snake_case rows to domain [PayrollPeriod].
final class PayrollPeriodSupabaseDto {
  const PayrollPeriodSupabaseDto({
    required this.periodId,
    required this.settingId,
    required this.generatedBy,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.generatedAt,
  });

  factory PayrollPeriodSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return PayrollPeriodSupabaseDto(
      periodId: map['period_id'] as String,
      settingId: map['setting_id'] as String,
      generatedBy: map['generated_by'] as String,
      startDate: SupabaseParseUtils.parseDate(map['start_date']),
      endDate: SupabaseParseUtils.parseDate(map['end_date']),
      status: map['status'] as String,
      generatedAt: SupabaseParseUtils.parseTimestamp(map['generated_at']),
    );
  }

  factory PayrollPeriodSupabaseDto.fromDomain(PayrollPeriod period) {
    return PayrollPeriodSupabaseDto(
      periodId: period.periodId,
      settingId: period.settingId,
      generatedBy: period.generatedBy,
      startDate: period.startDate,
      endDate: period.endDate,
      status: period.status.dbValue,
      generatedAt: period.generatedAt,
    );
  }

  final String periodId;
  final String settingId;
  final String generatedBy;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final DateTime generatedAt;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'period_id': periodId,
      'setting_id': settingId,
      'generated_by': generatedBy,
      'start_date': ShopDateUtils.formatIsoDate(startDate),
      'end_date': ShopDateUtils.formatIsoDate(endDate),
      'status': status,
      'generated_at': generatedAt.toUtc().toIso8601String(),
    };
  }

  PayrollPeriod toDomain() {
    return PayrollPeriod(
      periodId: periodId,
      settingId: settingId,
      generatedBy: generatedBy,
      startDate: startDate,
      endDate: endDate,
      status: PayrollPeriodStatus.fromDbValue(status),
      generatedAt: generatedAt,
    );
  }
}
