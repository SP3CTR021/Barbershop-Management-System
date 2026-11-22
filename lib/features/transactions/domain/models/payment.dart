import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';

const Object _unset = Object();

/// Domain model for `payments` (supports partial and split payments per visit).
///
/// Relationships:
/// - `transactions` (1) -> `payments` (M) via [transactionId].
/// - `users` (`STAFF`, 1) -> `payments` (M) via [receivedBy].
final class Payment {
  Payment({
    required this.paymentId,
    required this.transactionId,
    required this.receivedBy,
    required double amount,
    required this.paymentMethod,
    this.referenceNo,
    required this.paidAt,
  }) : amount = MoneyMath.round2(amount);

  final String paymentId;

  /// FK -> `transactions.transaction_id`.
  final String transactionId;

  /// FK -> `users.user_id` (`STAFF` who collected the payment).
  final String receivedBy;

  final double amount;
  final PaymentMethod paymentMethod;

  /// Reference number for `GCASH` or `CARD` payments; null for `CASH`.
  final String? referenceNo;

  final DateTime paidAt;

  Payment copyWith({
    String? paymentId,
    String? transactionId,
    String? receivedBy,
    double? amount,
    PaymentMethod? paymentMethod,
    Object? referenceNo = _unset,
    DateTime? paidAt,
  }) {
    return Payment(
      paymentId: paymentId ?? this.paymentId,
      transactionId: transactionId ?? this.transactionId,
      receivedBy: receivedBy ?? this.receivedBy,
      amount: amount ?? this.amount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNo: identical(referenceNo, _unset)
          ? this.referenceNo
          : referenceNo as String?,
      paidAt: paidAt ?? this.paidAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Payment &&
            other.paymentId == paymentId &&
            other.transactionId == transactionId &&
            other.receivedBy == receivedBy &&
            other.amount == amount &&
            other.paymentMethod == paymentMethod &&
            other.referenceNo == referenceNo &&
            other.paidAt == paidAt;
  }

  @override
  int get hashCode => Object.hash(
        paymentId,
        transactionId,
        receivedBy,
        amount,
        paymentMethod,
        referenceNo,
        paidAt,
      );

  @override
  String toString() =>
      'Payment(paymentId: $paymentId, transactionId: $transactionId, amount: $amount, method: ${paymentMethod.dbValue})';
}
