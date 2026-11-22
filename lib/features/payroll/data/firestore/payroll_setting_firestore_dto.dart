import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';

/// Firestore DTO mapping `payroll_settings/{settingId}` documents to [PayrollSetting].
final class PayrollSettingFirestoreDto {
  const PayrollSettingFirestoreDto({
    required this.settingId,
    required this.createdBy,
    required this.ownerSharePct,
    required this.barberSharePct,
    required this.periodDays,
    required this.effectiveFrom,
    this.effectiveTo,
  });

  factory PayrollSettingFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PayrollSettingFirestoreDto(
      settingId: (data['settingId'] as String?) ?? id,
      createdBy: data['createdBy'] as String,
      ownerSharePct: FirestoreParseUtils.parseDecimal(data['ownerSharePct']),
      barberSharePct: FirestoreParseUtils.parseDecimal(data['barberSharePct']),
      periodDays: FirestoreParseUtils.parseInt(data['periodDays']),
      effectiveFrom: FirestoreParseUtils.parseDate(data['effectiveFrom']),
      effectiveTo: FirestoreParseUtils.parseNullableDate(data['effectiveTo']),
    );
  }

  factory PayrollSettingFirestoreDto.fromDomain(PayrollSetting setting) {
    return PayrollSettingFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'settingId': settingId,
      'createdBy': createdBy,
      'ownerSharePct': MoneyMath.round2(ownerSharePct),
      'barberSharePct': MoneyMath.round2(barberSharePct),
      'periodDays': periodDays,
      'effectiveFrom': ShopDateUtils.formatIsoDate(effectiveFrom),
      'effectiveTo':
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
