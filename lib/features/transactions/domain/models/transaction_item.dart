import 'package:barbershop_management_app/core/utils/money_math.dart';

/// Domain model for `transaction_items` (resolves M:N `transactions <-> services`).
///
/// Relationships:
/// - `transactions` (1) -> `transaction_items` (M) via [transactionId] (`ON DELETE CASCADE`).
/// - `services` (1) -> `transaction_items` (M) via [serviceId] (`ON DELETE RESTRICT`).
///
/// History safety: [serviceName], [isHaircut], and [unitPrice] are snapshotted at
/// sale time so catalog renames, price changes, or `is_haircut` edits never
/// corrupt historical receipts or payroll periods.
final class TransactionItem {
  TransactionItem({
    required this.itemId,
    required this.transactionId,
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required this.quantity,
    required double unitPrice,
    required double subtotal,
  })  : unitPrice = MoneyMath.round2(unitPrice),
        subtotal = MoneyMath.round2(subtotal);

  final String itemId;

  /// FK -> `transactions.transaction_id`.
  final String transactionId;

  /// FK -> `services.service_id`.
  final String serviceId;

  /// Snapshot of `services.service_name` at time of sale.
  final String serviceName;

  /// Snapshot of `services.is_haircut` at time of sale for audit-safe payroll.
  final bool isHaircut;

  final int quantity;

  /// Snapshot of `services.price` at time of sale (Business Rule #5).
  final double unitPrice;

  final double subtotal;

  TransactionItem copyWith({
    String? itemId,
    String? transactionId,
    String? serviceId,
    String? serviceName,
    bool? isHaircut,
    int? quantity,
    double? unitPrice,
    double? subtotal,
  }) {
    return TransactionItem(
      itemId: itemId ?? this.itemId,
      transactionId: transactionId ?? this.transactionId,
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      isHaircut: isHaircut ?? this.isHaircut,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      subtotal: subtotal ?? this.subtotal,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TransactionItem &&
            other.itemId == itemId &&
            other.transactionId == transactionId &&
            other.serviceId == serviceId &&
            other.serviceName == serviceName &&
            other.isHaircut == isHaircut &&
            other.quantity == quantity &&
            other.unitPrice == unitPrice &&
            other.subtotal == subtotal;
  }

  @override
  int get hashCode => Object.hash(
        itemId,
        transactionId,
        serviceId,
        serviceName,
        isHaircut,
        quantity,
        unitPrice,
        subtotal,
      );

  @override
  String toString() =>
      'TransactionItem(itemId: $itemId, serviceName: $serviceName, quantity: $quantity, subtotal: $subtotal)';
}
