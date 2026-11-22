import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';

/// Backend-agnostic contract for `transactions` and owned `transaction_items`.
abstract interface class TransactionRepository {
  /// Logs a client visit with one or more services and an optional [initialPayment].
  ///
  /// Business rules enforced by every implementation:
  /// - [loggedByStaffId] must be an active `STAFF` (or `OWNER`) user.
  /// - [barberId] must be active AND marked `PRESENT` on the shop-local date
  ///   of [transactionDate] (Business Rule #3).
  /// - Every item in [items] resolves current `services.price`, `service_name`,
  ///   and `is_haircut` atomically (`unit_price` snapshot per Business Rule #5).
  /// - Sets status to `PAID` if `initialPayment.amount >= totalAmount`, else `PENDING`.
  Future<Result<TransactionWithDetails>> createTransaction({
    String? customerId,
    required String barberId,
    required String loggedByStaffId,
    required DateTime transactionDate,
    required List<CreateTransactionItemInput> items,
    InitialPaymentInput? initialPayment,
  });

  Future<Result<Transaction>> getTransactionById(String transactionId);

  Future<Result<TransactionWithDetails>> getTransactionWithDetails(
    String transactionId,
  );

  Future<Result<List<Transaction>>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? barberId,
    TransactionStatus? status,
  });

  Stream<Result<List<Transaction>>> watchTransactionsByDate(DateTime shopDate);

  /// Voids a transaction (`status = VOID`).
  ///
  /// Authorization & payroll lock rules:
  /// - `STAFF` (and `OWNER`) may void a `PENDING` transaction.
  /// - Only `OWNER` may void a `PAID` transaction (`PermissionDeniedFailure` for `STAFF`).
  /// - Voiding a `PAID` transaction is blocked (`ValidationFailure`) if its
  ///   shop-local date falls inside an `APPROVED` or `PAID` payroll period.
  Future<Result<Transaction>> voidTransaction({
    required String transactionId,
    required String actingUserId,
  });
}
