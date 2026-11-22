import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';

/// Firestore DTO mapping `transactions/{txId}/items/{itemId}` documents AND
/// embedded `itemsSummary` entries on the parent `transactions/{txId}` doc.
final class TransactionItemFirestoreDto {
  const TransactionItemFirestoreDto({
    required this.itemId,
    required this.transactionId,
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory TransactionItemFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data, {
    String? fallbackTransactionId,
  }) {
    return TransactionItemFirestoreDto(
      itemId: (data['itemId'] as String?) ?? id,
      transactionId:
          (data['transactionId'] as String?) ?? fallbackTransactionId ?? '',
      serviceId: data['serviceId'] as String,
      serviceName: data['serviceName'] as String,
      isHaircut: data['isHaircut'] as bool,
      quantity: FirestoreParseUtils.parseInt(data['quantity']),
      unitPrice: FirestoreParseUtils.parseDecimal(data['unitPrice']),
      subtotal: FirestoreParseUtils.parseDecimal(data['subtotal']),
    );
  }

  factory TransactionItemFirestoreDto.fromDomain(TransactionItem item) {
    return TransactionItemFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'itemId': itemId,
      'transactionId': transactionId,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'isHaircut': isHaircut,
      'quantity': quantity,
      'unitPrice': MoneyMath.round2(unitPrice),
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
