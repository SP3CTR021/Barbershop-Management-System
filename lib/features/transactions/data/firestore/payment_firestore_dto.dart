import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping top-level `payments/{paymentId}` documents to [Payment].
/// Top-level storage enables direct date-range & payment-method queries without
/// requiring a `collectionGroup` index.
final class PaymentFirestoreDto {
  const PaymentFirestoreDto({
    required this.paymentId,
    required this.transactionId,
    required this.receivedBy,
    required this.amount,
    required this.paymentMethod,
    this.referenceNo,
    required this.paidAt,
  });

  factory PaymentFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return PaymentFirestoreDto(
      paymentId: (data['paymentId'] as String?) ?? id,
      transactionId: data['transactionId'] as String,
      receivedBy: data['receivedBy'] as String,
      amount: FirestoreParseUtils.parseDecimal(data['amount']),
      paymentMethod: data['paymentMethod'] as String,
      referenceNo: data['referenceNo'] as String?,
      paidAt: FirestoreParseUtils.parseTimestamp(data['paidAt']),
    );
  }

  factory PaymentFirestoreDto.fromDomain(Payment payment) {
    return PaymentFirestoreDto(
      paymentId: payment.paymentId,
      transactionId: payment.transactionId,
      receivedBy: payment.receivedBy,
      amount: payment.amount,
      paymentMethod: payment.paymentMethod.dbValue,
      referenceNo: payment.referenceNo,
      paidAt: payment.paidAt,
    );
  }

  final String paymentId;
  final String transactionId;
  final String receivedBy;
  final double amount;
  final String paymentMethod;
  final String? referenceNo;
  final DateTime paidAt;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'paymentId': paymentId,
      'transactionId': transactionId,
      'receivedBy': receivedBy,
      'amount': MoneyMath.round2(amount),
      'paymentMethod': paymentMethod,
      'referenceNo': FirestoreParseUtils.cleanNullableText(referenceNo),
      'paidAt': fs.Timestamp.fromDate(paidAt.toUtc()),
    };
  }

  Payment toDomain() {
    return Payment(
      paymentId: paymentId,
      transactionId: transactionId,
      receivedBy: receivedBy,
      amount: amount,
      paymentMethod: PaymentMethod.fromDbValue(paymentMethod),
      referenceNo: referenceNo,
      paidAt: paidAt,
    );
  }
}
