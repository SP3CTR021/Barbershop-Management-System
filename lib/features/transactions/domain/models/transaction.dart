import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';

const Object _unset = Object();

/// Domain model for `transactions` (one row per client visit).
///
/// Relationships:
/// - `customers` (0..1) -> `transactions` (M) via nullable [customerId] (null = walk-in).
/// - `barbers` (1) -> `transactions` (M) via [barberId].
/// - `users` (`STAFF`, 1) -> `transactions` (M) via [loggedBy].
/// - `transactions` (1) -> `transaction_items` (1..M) and `payments` (M).
final class Transaction {
  Transaction({
    required this.transactionId,
    this.customerId,
    required this.barberId,
    required this.loggedBy,
    required this.transactionDate,
    required double totalAmount,
    required this.status,
  }) : totalAmount = MoneyMath.round2(totalAmount);

  final String transactionId;

  /// Nullable FK -> `customers.customer_id` (`null` for walk-in clients).
  final String? customerId;

  /// FK -> `barbers.barber_id` (barber who served the client).
  final String barberId;

  /// FK -> `users.user_id` (`STAFF` who logged the visit).
  final String loggedBy;

  final DateTime transactionDate;
  final double totalAmount;
  final TransactionStatus status;

  Transaction copyWith({
    String? transactionId,
    Object? customerId = _unset,
    String? barberId,
    String? loggedBy,
    DateTime? transactionDate,
    double? totalAmount,
    TransactionStatus? status,
  }) {
    return Transaction(
      transactionId: transactionId ?? this.transactionId,
      customerId: identical(customerId, _unset)
          ? this.customerId
          : customerId as String?,
      barberId: barberId ?? this.barberId,
      loggedBy: loggedBy ?? this.loggedBy,
      transactionDate: transactionDate ?? this.transactionDate,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Transaction &&
            other.transactionId == transactionId &&
            other.customerId == customerId &&
            other.barberId == barberId &&
            other.loggedBy == loggedBy &&
            other.transactionDate == transactionDate &&
            other.totalAmount == totalAmount &&
            other.status == status;
  }

  @override
  int get hashCode => Object.hash(
        transactionId,
        customerId,
        barberId,
        loggedBy,
        transactionDate,
        totalAmount,
        status,
      );

  @override
  String toString() =>
      'Transaction(transactionId: $transactionId, barberId: $barberId, totalAmount: $totalAmount, status: ${status.dbValue})';
}
