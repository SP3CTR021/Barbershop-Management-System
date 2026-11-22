import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/transaction_item_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping `transactions/{transactionId}` documents to domain [Transaction].
///
/// Denormalized fields kept strictly inside this DTO:
/// - `shopDate` (`yyyy-MM-dd` in `+08:00`): supports indexed daily stream queries.
/// - `customerName` & `barberName`: eliminate N+1 reads on transaction lists.
/// - `paidAmount`: enables single-doc `runTransaction` balance checks on payments.
/// - `haircutCount`, `haircutGrossSales`, & `itemsSummary`: turn 15-day payroll
///   computation into 1 range query instead of N+1 subcollection reads.
final class TransactionFirestoreDto {
  const TransactionFirestoreDto({
    required this.transactionId,
    this.customerId,
    required this.barberId,
    required this.loggedBy,
    required this.transactionDate,
    required this.totalAmount,
    required this.status,
    required this.shopDate,
    this.customerName,
    this.barberName,
    required this.paidAmount,
    required this.haircutCount,
    required this.haircutGrossSales,
    required this.itemsSummary,
  });

  factory TransactionFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final txId = (data['transactionId'] as String?) ?? id;
    final txDate =
        FirestoreParseUtils.parseTimestamp(data['transactionDate']);
    final rawItems = data['itemsSummary'] as List<dynamic>? ?? const [];
    final items = rawItems
        .map(
          (entry) => TransactionItemFirestoreDto.fromFirestore(
            (entry as Map<String, dynamic>)['itemId'] as String? ?? '',
            entry,
            fallbackTransactionId: txId,
          ),
        )
        .toList(growable: false);

    return TransactionFirestoreDto(
      transactionId: txId,
      customerId: data['customerId'] as String?,
      barberId: data['barberId'] as String,
      loggedBy: data['loggedBy'] as String,
      transactionDate: txDate,
      totalAmount: FirestoreParseUtils.parseDecimal(data['totalAmount']),
      status: data['status'] as String,
      shopDate: (data['shopDate'] as String?) ??
          ShopDateUtils.formatIsoDate(ShopDateUtils.toShopLocalDate(txDate)),
      customerName: data['customerName'] as String?,
      barberName: data['barberName'] as String?,
      paidAmount: data['paidAmount'] == null
          ? 0.0
          : FirestoreParseUtils.parseDecimal(data['paidAmount']),
      haircutCount: data['haircutCount'] == null
          ? 0
          : FirestoreParseUtils.parseInt(data['haircutCount']),
      haircutGrossSales: data['haircutGrossSales'] == null
          ? 0.0
          : FirestoreParseUtils.parseDecimal(data['haircutGrossSales']),
      itemsSummary: items,
    );
  }

  factory TransactionFirestoreDto.fromDomain(
    Transaction transaction, {
    String? customerName,
    String? barberName,
    double paidAmount = 0.0,
    int haircutCount = 0,
    double haircutGrossSales = 0.0,
    List<TransactionItemFirestoreDto> itemsSummary =
        const <TransactionItemFirestoreDto>[],
  }) {
    final shopDate = ShopDateUtils.formatIsoDate(
      ShopDateUtils.toShopLocalDate(transaction.transactionDate),
    );
    return TransactionFirestoreDto(
      transactionId: transaction.transactionId,
      customerId: transaction.customerId,
      barberId: transaction.barberId,
      loggedBy: transaction.loggedBy,
      transactionDate: transaction.transactionDate,
      totalAmount: transaction.totalAmount,
      status: transaction.status.dbValue,
      shopDate: shopDate,
      customerName: customerName,
      barberName: barberName,
      paidAmount: paidAmount,
      haircutCount: haircutCount,
      haircutGrossSales: haircutGrossSales,
      itemsSummary: itemsSummary,
    );
  }

  final String transactionId;
  final String? customerId;
  final String barberId;
  final String loggedBy;
  final DateTime transactionDate;
  final double totalAmount;
  final String status;

  // Denormalized Firestore fields:
  final String shopDate;
  final String? customerName;
  final String? barberName;
  final double paidAmount;
  final int haircutCount;
  final double haircutGrossSales;
  final List<TransactionItemFirestoreDto> itemsSummary;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'transactionId': transactionId,
      'customerId': customerId,
      'barberId': barberId,
      'loggedBy': loggedBy,
      'transactionDate': fs.Timestamp.fromDate(transactionDate.toUtc()),
      'totalAmount': MoneyMath.round2(totalAmount),
      'status': status,
      'shopDate': shopDate,
      'customerName': customerName,
      'barberName': barberName,
      'paidAmount': MoneyMath.round2(paidAmount),
      'haircutCount': haircutCount,
      'haircutGrossSales': MoneyMath.round2(haircutGrossSales),
      'itemsSummary': itemsSummary
          .map((item) => item.toFirestore())
          .toList(growable: false),
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
