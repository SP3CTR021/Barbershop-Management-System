import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';

/// Supabase DTO mapping `public.transaction_items` rows to domain [TransactionItem].
final class TransactionItemSupabaseDto {
  const TransactionItemSupabaseDto({
    required this.itemId,
    required this.transactionId,
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory TransactionItemSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return TransactionItemSupabaseDto(
      itemId: map['item_id'] as String,
      transactionId: map['transaction_id'] as String,
      serviceId: map['service_id'] as String,
      serviceName: map['service_name'] as String,
      isHaircut: map['is_haircut'] as bool,
      quantity: SupabaseParseUtils.parseInt(map['quantity']),
      unitPrice: SupabaseParseUtils.parseDecimal(map['unit_price']),
      subtotal: SupabaseParseUtils.parseDecimal(map['subtotal']),
    );
  }

  factory TransactionItemSupabaseDto.fromDomain(TransactionItem item) {
    return TransactionItemSupabaseDto(
      itemId: item.itemId,
      transactionId: item.transactionId,
      serviceId: item.serviceId,
      serviceName: item.serviceName,
      isHaircut: item.isHaircut,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      subtotal: item.subtotal,
    );
  }

  final String itemId;
  final String transactionId;
  final String serviceId;
  final String serviceName;
  final bool isHaircut;
  final int quantity;
  final double unitPrice;
  final double subtotal;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'item_id': itemId,
      'transaction_id': transactionId,
      'service_id': serviceId,
      'service_name': serviceName,
      'is_haircut': isHaircut,
      'quantity': quantity,
      'unit_price': MoneyMath.round2(unitPrice),
      'subtotal': MoneyMath.round2(subtotal),
    };
  }

  TransactionItem toDomain() {
    return TransactionItem(
      itemId: itemId,
      transactionId: transactionId,
      serviceId: serviceId,
      serviceName: serviceName,
      isHaircut: isHaircut,
      quantity: quantity,
      unitPrice: unitPrice,
      subtotal: subtotal,
    );
  }
}
