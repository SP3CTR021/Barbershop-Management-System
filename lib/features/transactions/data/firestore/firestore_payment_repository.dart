import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/payment_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/transaction_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [PaymentRepository].
///
/// Firestore workaround: relies on denormalized `paidAmount` on the parent
/// `transactions/{txId}` doc so `runTransaction` validates partial/split
/// balances in 1 doc read without running a query inside the transaction.
final class FirestorePaymentRepository implements PaymentRepository {
  FirestorePaymentRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');
  fs.CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');

  @override
  Future<Result<Payment>> recordPayment({
    required String transactionId,
    required String receivedByStaffId,
    required double amount,
    required PaymentMethod paymentMethod,
    String? referenceNo,
    DateTime? paidAt,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final roundedAmount = MoneyMath.round2(amount);
      final amountCentavos = MoneyMath.toCentavos(roundedAmount);
      if (amountCentavos <= 0) {
        throw const ValidationFailure(
          message: 'Payment amount must be greater than zero.',
          field: 'amount',
        );
      }

      final paymentId = _uuid.v4();
      final effectivePaidAt = (paidAt ?? DateTime.now()).toUtc();

      return _firestore.runTransaction((tx) async {
        // 1. Reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: receivedByStaffId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
          tx: tx,
        );

        final txRef = _transactions.doc(transactionId);
        final txSnap = await tx.get(txRef);
        if (!txSnap.exists || txSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Transaction $transactionId not found.',
            entityName: 'Transaction',
            entityId: transactionId,
          );
        }

        final txDto =
            TransactionFirestoreDto.fromFirestore(txSnap.id, txSnap.data()!);
        final parent = txDto.toDomain();

        // 2. Validations:
        if (parent.status == TransactionStatus.voided) {
          throw const ValidationFailure(
            message: 'Cannot record payment on a VOID transaction.',
          );
        }
        if (parent.status == TransactionStatus.paid) {
          throw ValidationFailure(
            message: 'Transaction $transactionId is already fully PAID.',
          );
        }

        final paidSoFarCentavos = MoneyMath.toCentavos(txDto.paidAmount);
        final totalCentavos = MoneyMath.toCentavos(parent.totalAmount);
        if (paidSoFarCentavos + amountCentavos > totalCentavos) {
          final remaining =
              MoneyMath.fromCentavos(totalCentavos - paidSoFarCentavos);
          throw ValidationFailure(
            message:
                'Payment ($roundedAmount) exceeds remaining balance ($remaining).',
            field: 'amount',
          );
        }

        final newPaidCentavos = paidSoFarCentavos + amountCentavos;
        final isSettled = newPaidCentavos == totalCentavos;

        final payment = Payment(
          paymentId: paymentId,
          transactionId: transactionId,
          receivedBy: receivedByStaffId,
          amount: roundedAmount,
          paymentMethod: paymentMethod,
          referenceNo: FirestoreParseUtils.cleanNullableText(referenceNo),
          paidAt: effectivePaidAt,
        );

        // 3. Writes:
        tx.set(
          _payments.doc(paymentId),
          PaymentFirestoreDto.fromDomain(payment).toFirestore(),
        );
        tx.update(txRef, <String, dynamic>{
          'paidAmount': MoneyMath.fromCentavos(newPaidCentavos),
          if (isSettled) 'status': TransactionStatus.paid.dbValue,
        });

        return payment;
      });
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsForTransaction(
    String transactionId,
  ) {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _payments
          .where('transactionId', isEqualTo: transactionId)
          .orderBy('paidAt')
          .get();
      return snap.docs
          .map(
            (doc) => PaymentFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    PaymentMethod? paymentMethod,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final range = ShopDateUtils.utcRangeForShopDateRange(
        startDate: startDate,
        endDate: endDate,
      );
      fs.Query<Map<String, dynamic>> query = _payments
          .where(
            'paidAt',
            isGreaterThanOrEqualTo:
                fs.Timestamp.fromDate(range.startUtcInclusive),
          )
          .where(
            'paidAt',
            isLessThan: fs.Timestamp.fromDate(range.endUtcExclusive),
          );

      if (paymentMethod != null) {
        query = query.where('paymentMethod', isEqualTo: paymentMethod.dbValue);
      }

      final snap = await query.orderBy('paidAt').get();
      return snap.docs
          .map(
            (doc) => PaymentFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false);
    });
  }
}
