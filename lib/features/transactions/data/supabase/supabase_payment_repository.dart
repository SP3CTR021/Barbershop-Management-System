import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/payment_supabase_dto.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [PaymentRepository] using `rpc_record_payment`
/// to lock the parent transaction and auto-transition `PENDING -> PAID`.
final class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<Payment>> recordPayment({
    required String transactionId,
    required String receivedByStaffId,
    required double amount,
    required PaymentMethod paymentMethod,
    String? referenceNo,
    DateTime? paidAt,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final effectivePaidAt = (paidAt ?? DateTime.now()).toUtc();
      final paymentId = await _client.rpc(
        'rpc_record_payment',
        params: <String, dynamic>{
          'p_transaction_id': transactionId,
          'p_received_by_staff_id': receivedByStaffId,
          'p_amount': amount,
          'p_payment_method': paymentMethod.dbValue,
          'p_reference_no': SupabaseParseUtils.cleanNullableText(referenceNo),
          'p_paid_at': effectivePaidAt.toIso8601String(),
        },
      );

      final row = await _client
          .from('payments')
          .select()
          .eq('payment_id', paymentId as String)
          .single();
      return PaymentSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsForTransaction(
    String transactionId,
  ) {
    return SupabaseErrorMapper.guard(() async {
      final rows = await _client
          .from('payments')
          .select()
          .eq('transaction_id', transactionId)
          .order('paid_at', ascending: true);
      return rows
          .map((row) => PaymentSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Future<Result<List<Payment>>> getPaymentsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
    PaymentMethod? paymentMethod,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final range = ShopDateUtils.utcRangeForShopDateRange(
        startDate: startDate,
        endDate: endDate,
      );
      var query = _client
          .from('payments')
          .select()
          .gte('paid_at', range.startUtcInclusive.toIso8601String())
          .lt('paid_at', range.endUtcExclusive.toIso8601String());

      if (paymentMethod != null) {
        query = query.eq('payment_method', paymentMethod.dbValue);
      }

      final rows = await query.order('paid_at', ascending: true);
      return rows
          .map((row) => PaymentSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }
}
