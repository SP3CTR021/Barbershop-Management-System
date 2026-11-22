import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping top-level join collection
/// `payroll_records/{periodId}_{barberId}` documents to [PayrollRecord].
///
/// Denormalized field: [periodStartDate] enables sorting a barber's payslip
/// history without joining back to `payroll_periods`.
final class PayrollRecordFirestoreDto {
  const PayrollRecordFirestoreDto({
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
    this.periodStartDate,
  });

  factory PayrollRecordFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PayrollRecordFirestoreDto(
      payrollId: (data['payrollId'] as String?) ?? id,
      periodId: data['periodId'] as String,
      barberId: data['barberId'] as String,
      totalHaircuts: FirestoreParseUtils.parseInt(data['totalHaircuts']),
      grossSales: FirestoreParseUtils.parseDecimal(data['grossSales']),
      ownerSharePct: FirestoreParseUtils.parseDecimal(data['ownerSharePct']),
      barberSharePct: FirestoreParseUtils.parseDecimal(data['barberSharePct']),
      ownerShareAmount:
          FirestoreParseUtils.parseDecimal(data['ownerShareAmount']),
      barberPayAmount:
          FirestoreParseUtils.parseDecimal(data['barberPayAmount']),
      status: data['status'] as String,
      paidAt: FirestoreParseUtils.parseNullableTimestamp(data['paidAt']),
      periodStartDate:
          FirestoreParseUtils.parseNullableDate(data['periodStartDate']),
    );
  }

  factory PayrollRecordFirestoreDto.fromDomain(
    PayrollRecord record, {
    DateTime? periodStartDate,
  }) {
    return PayrollRecordFirestoreDto(
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
      periodStartDate: periodStartDate,
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
  final DateTime? periodStartDate;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'payrollId': payrollId,
      'periodId': periodId,
      'barberId': barberId,
      'totalHaircuts': totalHaircuts,
      'grossSales': MoneyMath.round2(grossSales),
      'ownerSharePct': MoneyMath.round2(ownerSharePct),
      'barberSharePct': MoneyMath.round2(barberSharePct),
      'ownerShareAmount': MoneyMath.round2(ownerShareAmount),
      'barberPayAmount': MoneyMath.round2(barberPayAmount),
      'status': status,
      'paidAt': paidAt == null ? null : fs.Timestamp.fromDate(paidAt!.toUtc()),
      if (periodStartDate != null)
        'periodStartDate': ShopDateUtils.formatIsoDate(periodStartDate!),
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
