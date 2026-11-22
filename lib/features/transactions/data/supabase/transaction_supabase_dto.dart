import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';

/// Supabase DTO mapping `public.transactions` snake_case rows to domain [Transaction].
final class TransactionSupabaseDto {
  const TransactionSupabaseDto({
    required this.transactionId,
    this.customerId,
    required this.barberId,
    required this.loggedBy,
    required this.transactionDate,
    required this.totalAmount,
    required this.status,
  });

  factory TransactionSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return TransactionSupabaseDto(
      transactionId: map['transaction_id'] as String,
      customerId: map['customer_id'] as String?,
      barberId: map['barber_id'] as String,
      loggedBy: map['logged_by'] as String,
      transactionDate:
          SupabaseParseUtils.parseTimestamp(map['transaction_date']),
      totalAmount: SupabaseParseUtils.parseDecimal(map['total_amount']),
      status: map['status'] as String,
    );
  }

  factory TransactionSupabaseDto.fromDomain(Transaction transaction) {
    return TransactionSupabaseDto(
      transactionId: transaction.transactionId,
      customerId: transaction.customerId,
      barberId: transaction.barberId,
      loggedBy: transaction.loggedBy,
      transactionDate: transaction.transactionDate,
      totalAmount: transaction.totalAmount,
      status: transaction.status.dbValue,
    );
  }

  final String transactionId;
  final String? customerId;
  final String barberId;
  final String loggedBy;
  final DateTime transactionDate;
  final double totalAmount;
  final String status;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'transaction_id': transactionId,
      'customer_id': customerId,
      'barber_id': barberId,
      'logged_by': loggedBy,
      'transaction_date': transactionDate.toUtc().toIso8601String(),
      'total_amount': MoneyMath.round2(totalAmount),
      'status': status,
    };
  }

  Transaction toDomain() {
    return Transaction(
      transactionId: transactionId,
      customerId: customerId,
      barberId: barberId,
      loggedBy: loggedBy,
      transactionDate: transactionDate,
      totalAmount: totalAmount,
      status: TransactionStatus.fromDbValue(status),
    );
  }
}
