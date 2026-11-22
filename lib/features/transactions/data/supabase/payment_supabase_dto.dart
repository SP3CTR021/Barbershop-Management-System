import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';

/// Supabase DTO mapping `public.payments` snake_case rows to domain [Payment].
final class PaymentSupabaseDto {
  const PaymentSupabaseDto({
    required this.paymentId,
    required this.transactionId,
    required this.receivedBy,
    required this.amount,
    required this.paymentMethod,
    this.referenceNo,
    required this.paidAt,
  });

  factory PaymentSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return PaymentSupabaseDto(
      paymentId: map['payment_id'] as String,
      transactionId: map['transaction_id'] as String,
      receivedBy: map['received_by'] as String,
      amount: SupabaseParseUtils.parseDecimal(map['amount']),
      paymentMethod: map['payment_method'] as String,
      referenceNo: map['reference_no'] as String?,
      paidAt: SupabaseParseUtils.parseTimestamp(map['paid_at']),
    );
  }

  factory PaymentSupabaseDto.fromDomain(Payment payment) {
    return PaymentSupabaseDto(
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

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'payment_id': paymentId,
      'transaction_id': transactionId,
      'received_by': receivedBy,
      'amount': MoneyMath.round2(amount),
      'payment_method': paymentMethod,
      'reference_no': SupabaseParseUtils.cleanNullableText(referenceNo),
      'paid_at': paidAt.toUtc().toIso8601String(),
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
