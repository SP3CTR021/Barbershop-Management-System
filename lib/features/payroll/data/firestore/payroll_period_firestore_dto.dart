import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping `payroll_periods/{periodId}` documents to [PayrollPeriod].
final class PayrollPeriodFirestoreDto {
  const PayrollPeriodFirestoreDto({
    required this.periodId,
    required this.settingId,
    required this.generatedBy,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.generatedAt,
  });

  factory PayrollPeriodFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PayrollPeriodFirestoreDto(
      periodId: (data['periodId'] as String?) ?? id,
      settingId: data['settingId'] as String,
      generatedBy: data['generatedBy'] as String,
      startDate: FirestoreParseUtils.parseDate(data['startDate']),
      endDate: FirestoreParseUtils.parseDate(data['endDate']),
      status: data['status'] as String,
      generatedAt: FirestoreParseUtils.parseTimestamp(data['generatedAt']),
    );
  }

  factory PayrollPeriodFirestoreDto.fromDomain(PayrollPeriod period) {
    return PayrollPeriodFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'periodId': periodId,
      'settingId': settingId,
      'generatedBy': generatedBy,
      'startDate': ShopDateUtils.formatIsoDate(startDate),
      'endDate': ShopDateUtils.formatIsoDate(endDate),
      'status': status,
      'generatedAt': fs.Timestamp.fromDate(generatedAt.toUtc()),
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
