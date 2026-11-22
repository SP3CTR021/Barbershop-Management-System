import 'package:barbershop_management_app/core/utils/collection_equality.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';

/// Input item supplied when logging a new client visit; unit prices and haircut
/// flags are resolved authoritatively from `services` inside the repository.
final class CreateTransactionItemInput {
  const CreateTransactionItemInput({
    required this.serviceId,
    this.quantity = 1,
  });

  final String serviceId;
  final int quantity;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreateTransactionItemInput &&
            other.serviceId == serviceId &&
            other.quantity == quantity;
  }

  @override
  int get hashCode => Object.hash(serviceId, quantity);

  @override
  String toString() =>
      'CreateTransactionItemInput(serviceId: $serviceId, quantity: $quantity)';
}

/// Optional payment collected at the same time a transaction is logged.
final class InitialPaymentInput {
  InitialPaymentInput({
    required double amount,
    required this.paymentMethod,
    this.referenceNo,
  }) : amount = MoneyMath.round2(amount);

  final double amount;
  final PaymentMethod paymentMethod;
  final String? referenceNo;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is InitialPaymentInput &&
            other.amount == amount &&
            other.paymentMethod == paymentMethod &&
            other.referenceNo == referenceNo;
  }

  @override
  int get hashCode => Object.hash(amount, paymentMethod, referenceNo);

  @override
  String toString() =>
      'InitialPaymentInput(amount: $amount, paymentMethod: ${paymentMethod.dbValue})';
}

/// Aggregate root read model combining a [Transaction], its [items], and [payments].
final class TransactionWithDetails {
  TransactionWithDetails({
    required this.transaction,
    required List<TransactionItem> items,
    required List<Payment> payments,
  })  : items = List<TransactionItem>.unmodifiable(items),
        payments = List<Payment>.unmodifiable(payments);

  final Transaction transaction;
  final List<TransactionItem> items;
  final List<Payment> payments;

  double get totalPaid => MoneyMath.sum(payments.map((p) => p.amount));

  double get remainingBalance =>
      MoneyMath.round2(transaction.totalAmount - totalPaid);

  int get totalHaircutQuantity => items
      .where((item) => item.isHaircut)
      .fold<int>(0, (acc, item) => acc + item.quantity);

  double get haircutGrossSales => MoneyMath.sum(
        items.where((item) => item.isHaircut).map((item) => item.subtotal),
      );

  TransactionWithDetails copyWith({
    Transaction? transaction,
    List<TransactionItem>? items,
    List<Payment>? payments,
  }) {
    return TransactionWithDetails(
      transaction: transaction ?? this.transaction,
      items: items ?? this.items,
      payments: payments ?? this.payments,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TransactionWithDetails &&
            other.transaction == transaction &&
            listEquals(other.items, items) &&
            listEquals(other.payments, payments);
  }

  @override
  int get hashCode =>
      Object.hash(transaction, listHash(items), listHash(payments));

  @override
  String toString() =>
      'TransactionWithDetails(transactionId: ${transaction.transactionId}, items: ${items.length}, payments: ${payments.length})';
}
