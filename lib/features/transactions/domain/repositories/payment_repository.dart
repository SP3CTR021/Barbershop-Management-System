import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';

/// Backend-agnostic contract for `payments` supporting partial and split tenders.
abstract interface class PaymentRepository {
  /// Records a payment against [transactionId] and atomically transitions the
  /// parent transaction to `PAID` once cumulative payments reach `total_amount`.
  /// Rejects payments on `VOID` or already-paid transactions, and overpayments.
  Future<Result<Payment>> recordPayment({
    required String transactionId,
    required String receivedByStaffId,
    required double amount,
    required PaymentMethod paymentMethod,
    String? referenceNo,
    DateTime? paidAt,
  });

  Future<Result<List<Payment>>> getPaymentsForTransaction(String transactionId);

  Future<Result<List<Payment>>> getPaymentsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    PaymentMethod? paymentMethod,
  });
}
