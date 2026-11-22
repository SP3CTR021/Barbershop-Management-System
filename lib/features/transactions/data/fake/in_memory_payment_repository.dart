import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// In-memory fake implementation of [PaymentRepository].
final class InMemoryPaymentRepository implements PaymentRepository {
  InMemoryPaymentRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<Payment>> recordPayment({
    required String transactionId,
    required String receivedByStaffId,
    required double amount,
    required PaymentMethod paymentMethod,
    String? referenceNo,
    DateTime? paidAt,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: receivedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      final roundedAmount = MoneyMath.round2(amount);
      final amountCentavos = MoneyMath.toCentavos(roundedAmount);
      if (amountCentavos <= 0) {
        throw const ValidationFailure(
          message: 'Payment amount must be greater than zero.',
          field: 'amount',
        );
      }

      final tx = _db.transactions[transactionId];
      if (tx == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      if (tx.status == TransactionStatus.voided) {
        throw const ValidationFailure(
          message: 'Cannot record payment on a VOID transaction.',
        );
      }
      if (tx.status == TransactionStatus.paid) {
        throw ValidationFailure(
          message: 'Transaction $transactionId is already fully PAID.',
        );
      }

      final paidSoFarCentavos = _db.payments.values
          .where((p) => p.transactionId == transactionId)
          .fold<int>(0, (acc, p) => acc + MoneyMath.toCentavos(p.amount));
      final totalCentavos = MoneyMath.toCentavos(tx.totalAmount);

      if (paidSoFarCentavos + amountCentavos > totalCentavos) {
        final remaining =
            MoneyMath.fromCentavos(totalCentavos - paidSoFarCentavos);
        throw ValidationFailure(
          message:
              'Payment ($roundedAmount) exceeds remaining balance ($remaining).',
          field: 'amount',
        );
      }

      final cleanRef = referenceNo?.trim();
      final payment = Payment(
        paymentId: _db.nextId(),
        transactionId: transactionId,
        receivedBy: receivedByStaffId,
        amount: roundedAmount,
        paymentMethod: paymentMethod,
        referenceNo: (cleanRef == null || cleanRef.isEmpty) ? null : cleanRef,
        paidAt: (paidAt ?? DateTime.now()).toUtc(),
      );
      _db.payments[payment.paymentId] = payment;

      if (paidSoFarCentavos + amountCentavos == totalCentavos) {
        _db.transactions[transactionId] =
            tx.copyWith(status: TransactionStatus.paid);
      }
      _db.notifyChanged();
      return payment;
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsForTransaction(
    String transactionId,
  ) {
    return _db.guard(() {
      final list = _db.payments.values
          .where((p) => p.transactionId == transactionId)
          .toList(growable: false)
        ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
      return list;
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    PaymentMethod? paymentMethod,
  }) {
    return _db.guard(() {
      final range = ShopDateUtils.utcRangeForShopDateRange(
        startDate: startDate,
        endDate: endDate,
      );
      final list = _db.payments.values.where((p) {
        if (p.paidAt.isBefore(range.startUtcInclusive) ||
            !p.paidAt.isBefore(range.endUtcExclusive)) {
          return false;
        }
        if (paymentMethod != null && p.paymentMethod != paymentMethod) {
          return false;
        }
        return true;
      }).toList(growable: false)
        ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
      return list;
    });
  }
}
