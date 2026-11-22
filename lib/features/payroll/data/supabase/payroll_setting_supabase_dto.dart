import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';

/// Supabase DTO mapping `public.payroll_settings` snake_case rows to domain [PayrollSetting].
final class PayrollSettingSupabaseDto {
  const PayrollSettingSupabaseDto({
    required this.settingId,
    required this.createdBy,
    required this.ownerSharePct,
    required this.barberSharePct,
    required this.periodDays,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  factory PayrollSettingSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return PayrollSettingSupabaseDto(
      settingId: map['setting_id'] as String,
      createdBy: map['created_by'] as String,
      ownerSharePct: SupabaseParseUtils.parseDecimal(map['owner_share_pct']),
      barberSharePct: SupabaseParseUtils.parseDecimal(map['barber_share_pct']),
      periodDays: SupabaseParseUtils.parseInt(map['period_days']),
      effectiveFrom: SupabaseParseUtils.parseDate(map['effective_from']),
      effectiveTo: SupabaseParseUtils.parseNullableDate(map['effective_to']),
    );
  }

  factory PayrollSettingSupabaseDto.fromDomain(PayrollSetting setting) {
    return PayrollSettingSupabaseDto(
      settingId: setting.settingId,
      createdBy: setting.createdBy,
      ownerSharePct: setting.ownerSharePct,
      barberSharePct: setting.barberSharePct,
      periodDays: setting.periodDays,
      effectiveFrom: setting.effectiveFrom,
      effectiveTo: setting.effectiveTo,
    );
  }

  final String settingId;
  final String createdBy;
  final double ownerSharePct;
  final double barberSharePct;
  final int periodDays;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'setting_id': settingId,
      'created_by': createdBy,
      'owner_share_pct': MoneyMath.round2(ownerSharePct),
      'barber_share_pct': MoneyMath.round2(barberSharePct),
      'period_days': periodDays,
      'effective_from': ShopDateUtils.formatIsoDate(effectiveFrom),
      'effective_to':
          effectiveTo == null ? null : ShopDateUtils.formatIsoDate(effectiveTo!),
    };
  }

  PayrollSetting toDomain() {
    return PayrollSetting(
      settingId: settingId,
      createdBy: createdBy,
      ownerSharePct: ownerSharePct,
      barberSharePct: barberSharePct,
      periodDays: periodDays,
      effectiveFrom: effectiveFrom,
      effectiveTo: effectiveTo,
    );
  }
}
