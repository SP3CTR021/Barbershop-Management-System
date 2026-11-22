import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/payment_supabase_dto.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/transaction_item_supabase_dto.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/transaction_supabase_dto.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [TransactionRepository] leveraging ACID RPCs
/// and single-query relational joins (`transactions -> transaction_items, payments`).
final class SupabaseTransactionRepository implements TransactionRepository {
  SupabaseTransactionRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<TransactionWithDetails>> createTransaction({
    String? customerId,
    required String barberId,
    required String loggedByStaffId,
    required DateTime transactionDate,
    required List<CreateTransactionItemInput> items,
    InitialPaymentInput? initialPayment,
  }) {
    return SupabaseErrorMapper.guard(() async {
      if (items.isEmpty) {
        throw const ValidationFailure(
          message: 'A transaction must contain at least one service item.',
          field: 'items',
        );
      }

      final itemPayload = items
          .map(
            (item) => <String, dynamic>{
              'service_id': item.serviceId,
              'quantity': item.quantity,
            },
          )
          .toList(growable: false);

      final initialPaymentPayload = initialPayment == null
          ? null
          : <String, dynamic>{
              'amount': initialPayment.amount,
              'payment_method': initialPayment.paymentMethod.dbValue,
              'reference_no': SupabaseParseUtils.cleanNullableText(
                initialPayment.referenceNo,
              ),
              'paid_at': transactionDate.toUtc().toIso8601String(),
            };

      final txId = await _client.rpc(
        'rpc_create_transaction',
        params: <String, dynamic>{
          'p_customer_id': customerId,
          'p_barber_id': barberId,
          'p_logged_by_staff_id': loggedByStaffId,
          'p_transaction_date': transactionDate.toUtc().toIso8601String(),
          'p_items': itemPayload,
          'p_initial_payment': initialPaymentPayload,
        },
      );

      return _fetchTransactionWithDetailsOrThrow(txId as String);
    });
  }

  @override
  Future<Result<Transaction>> getTransactionById(String transactionId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('transactions')
          .select()
          .eq('transaction_id', transactionId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      return TransactionSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<TransactionWithDetails>> getTransactionWithDetails(
    String transactionId,
  ) {
    return SupabaseErrorMapper.guard(
      () => _fetchTransactionWithDetailsOrThrow(transactionId),
    );
  }

  @override
  Future<Result<List<Transaction>>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? barberId,
    TransactionStatus? status,
  }) {
    return SupabaseErrorMapper.guard(() async {
      var query = _client.from('transactions').select();

      if (startDate != null && endDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: endDate,
        );
        query = query
            .gte('transaction_date', range.startUtcInclusive.toIso8601String())
            .lt('transaction_date', range.endUtcExclusive.toIso8601String());
      } else if (startDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: startDate,
        );
        query = query.gte(
          'transaction_date',
          range.startUtcInclusive.toIso8601String(),
        );
      } else if (endDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: endDate,
          endDate: endDate,
        );
        query = query.lt(
          'transaction_date',
          range.endUtcExclusive.toIso8601String(),
        );
      }

      if (barberId != null) {
        query = query.eq('barber_id', barberId);
      }
      if (status != null) {
        query = query.eq('status', status.dbValue);
      }

      final rows = await query.order('transaction_date', ascending: false);
      return rows
          .map((row) => TransactionSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<Transaction>>> watchTransactionsByDate(DateTime shopDate) {
    final range = ShopDateUtils.utcRangeForShopDateRange(
      startDate: shopDate,
      endDate: shopDate,
    );
    final stream = _client
        .from('transactions')
        .stream(primaryKey: <String>['transaction_id'])
        .order('transaction_date', ascending: false)
        .map(
          (rows) => rows
              .map((row) => TransactionSupabaseDto.fromSupabase(row).toDomain())
              .where(
                (tx) =>
                    !tx.transactionDate.isBefore(range.startUtcInclusive) &&
                    tx.transactionDate.isBefore(range.endUtcExclusive),
              )
              .toList(growable: false),
        );
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Transaction>> voidTransaction({
    required String transactionId,
    required String actingUserId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await _client.rpc(
        'rpc_void_transaction',
        params: <String, dynamic>{
          'p_transaction_id': transactionId,
          'p_acting_user_id': actingUserId,
        },
      );
      final row = await _client
          .from('transactions')
          .select()
          .eq('transaction_id', transactionId)
          .single();
      return TransactionSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  Future<TransactionWithDetails> _fetchTransactionWithDetailsOrThrow(
    String transactionId,
  ) async {
    final row = await _client
        .from('transactions')
        .select('*, transaction_items(*), payments(*)')
        .eq('transaction_id', transactionId)
        .maybeSingle();

    if (row == null) {
      throw NotFoundFailure(
        message: 'Transaction $transactionId not found.',
        entityName: 'Transaction',
        entityId: transactionId,
      );
    }

    final tx = TransactionSupabaseDto.fromSupabase(row).toDomain();
    final rawItems = (row['transaction_items'] as List<dynamic>? ?? const []);
    final items = rawItems
        .map(
          (item) => TransactionItemSupabaseDto.fromSupabase(
            item as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false);

    final rawPayments = (row['payments'] as List<dynamic>? ?? const []);
    final payments = rawPayments
        .map(
          (payment) => PaymentSupabaseDto.fromSupabase(
            payment as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false)
      ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

    return TransactionWithDetails(
      transaction: tx,
      items: items,
      payments: payments,
    );
  }
}
