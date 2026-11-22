import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';

/// Aggregated haircut totals for a single barber within a payroll period.
final class BarberSalesSummary {
  BarberSalesSummary({
    required this.barberId,
    required this.totalHaircuts,
    required double grossSales,
  }) : grossSales = MoneyMath.round2(grossSales);

  final String barberId;
  final int totalHaircuts;
  final double grossSales;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BarberSalesSummary &&
            other.barberId == barberId &&
            other.totalHaircuts == totalHaircuts &&
            other.grossSales == grossSales;
  }

  @override
  int get hashCode => Object.hash(barberId, totalHaircuts, grossSales);

  @override
  String toString() =>
      'BarberSalesSummary(barberId: $barberId, totalHaircuts: $totalHaircuts, grossSales: $grossSales)';
}

/// Pure-Dart domain service guaranteeing identical 60/40 haircut-only payroll
/// calculations across Firestore, InMemory fakes, and unit tests, matching the
/// PostgreSQL RPC logic.
abstract final class PayrollCalculator {
  /// Aggregates [transactions] filtered to `status == PAID`, shop-local date in
  /// `[startDate, endDate]`, and `item.isHaircut == true` (Business Rule #4).
  static List<PayrollRecord> computeFromDetails({
    required String periodId,
    required PayrollSetting setting,
    required DateTime startDate,
    required DateTime endDate,
    required Iterable<TransactionWithDetails> transactions,
    required Iterable<String> barberIdsToInclude,
    required String Function(String barberId) payrollIdGenerator,
    Duration shopUtcOffset = ShopDateUtils.defaultShopUtcOffset,
  }) {
    final normalizedStart = ShopDateUtils.normalizeDate(startDate);
    final normalizedEnd = ShopDateUtils.normalizeDate(endDate);

    final haircutsByBarber = <String, int>{};
    final centavosByBarber = <String, int>{};

    for (final detail in transactions) {
      final tx = detail.transaction;
      if (tx.status != TransactionStatus.paid) continue;

      final txDate = ShopDateUtils.toShopLocalDate(
        tx.transactionDate,
        shopOffset: shopUtcOffset,
      );
      if (txDate.isBefore(normalizedStart) || txDate.isAfter(normalizedEnd)) {
        continue;
      }

      for (final item in detail.items) {
        if (!item.isHaircut) continue;
        haircutsByBarber[tx.barberId] =
            (haircutsByBarber[tx.barberId] ?? 0) + item.quantity;
        centavosByBarber[tx.barberId] =
            (centavosByBarber[tx.barberId] ?? 0) +
                MoneyMath.toCentavos(item.subtotal);
      }
    }

    final summaries = <String, BarberSalesSummary>{};
    for (final barberId in haircutsByBarber.keys) {
      summaries[barberId] = BarberSalesSummary(
        barberId: barberId,
        totalHaircuts: haircutsByBarber[barberId] ?? 0,
        grossSales: MoneyMath.fromCentavos(centavosByBarber[barberId] ?? 0),
      );
    }

    return computeFromSummaries(
      periodId: periodId,
      setting: setting,
      summariesByBarberId: summaries,
      barberIdsToInclude: barberIdsToInclude,
      payrollIdGenerator: payrollIdGenerator,
    );
  }

  /// Computes deterministic [PayrollRecord] entries from pre-aggregated
  /// [summariesByBarberId], including active barbers with zero haircuts.
  static List<PayrollRecord> computeFromSummaries({
    required String periodId,
    required PayrollSetting setting,
    required Map<String, BarberSalesSummary> summariesByBarberId,
    required Iterable<String> barberIdsToInclude,
    required String Function(String barberId) payrollIdGenerator,
  }) {
    final allBarberIds = <String>{
      ...barberIdsToInclude,
      ...summariesByBarberId.keys,
    }.toList()
      ..sort();

    return allBarberIds.map((barberId) {
      final summary = summariesByBarberId[barberId] ??
          BarberSalesSummary(
            barberId: barberId,
            totalHaircuts: 0,
            grossSales: 0,
          );
      final split = MoneyMath.splitSales(
        grossSales: summary.grossSales,
        ownerSharePct: setting.ownerSharePct,
        barberSharePct: setting.barberSharePct,
      );
      return PayrollRecord(
        payrollId: payrollIdGenerator(barberId),
        periodId: periodId,
        barberId: barberId,
        totalHaircuts: summary.totalHaircuts,
        grossSales: summary.grossSales,
        ownerSharePct: setting.ownerSharePct,
        barberSharePct: setting.barberSharePct,
        ownerShareAmount: split.ownerShareAmount,
        barberPayAmount: split.barberPayAmount,
        status: PayrollRecordStatus.pending,
        paidAt: null,
      );
    }).toList(growable: false);
  }
}
