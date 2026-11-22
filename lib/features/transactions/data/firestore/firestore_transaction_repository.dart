import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/services/data/firestore/service_firestore_dto.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/payment_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/transaction_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/transaction_item_firestore_dto.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [TransactionRepository].
///
/// Firestore workarounds implemented here:
/// - Inside `runTransaction`, validates active `STAFF`/`OWNER` role, active barber,
///   `PRESENT` attendance via `O(1)` lookup on `attendance/{barberId}_{shopDate}`,
///   and service prices/flags before writing.
/// - Writes items both to `transactions/{txId}/items/{itemId}` AND as embedded
///   `itemsSummary` + `haircutCount`/`haircutGrossSales` on `transactions/{txId}`
///   to avoid N+1 subcollection reads during POS lists and 15-day payroll runs.
final class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');
  fs.CollectionReference<Map<String, dynamic>> get _payments =>
      _firestore.collection('payments');
  fs.CollectionReference<Map<String, dynamic>> get _barbers =>
      _firestore.collection('barbers');
  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _customers =>
      _firestore.collection('customers');
  fs.CollectionReference<Map<String, dynamic>> get _services =>
      _firestore.collection('services');
  fs.CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('attendance');
  fs.CollectionReference<Map<String, dynamic>> get _payrollPeriods =>
      _firestore.collection('payroll_periods');

  @override
  Future<Result<TransactionWithDetails>> createTransaction({
    String? customerId,
    required String barberId,
    required String loggedByStaffId,
    required DateTime transactionDate,
    required List<CreateTransactionItemInput> items,
    InitialPaymentInput? initialPayment,
  }) {
    return FirestoreErrorMapper.guard(() async {
      if (items.isEmpty) {
        throw const ValidationFailure(
          message: 'A transaction must contain at least one service item.',
          field: 'items',
        );
      }

      final txId = _uuid.v4();
      final utcTxDate = transactionDate.toUtc();
      final shopDate = ShopDateUtils.toShopLocalDate(utcTxDate);
      final attendanceDocId =
          FirestoreParseUtils.attendanceDocId(barberId, shopDate);

      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: loggedByStaffId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
          tx: tx,
        );

        final barberSnap = await tx.get(_barbers.doc(barberId));
        if (!barberSnap.exists || barberSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Barber $barberId not found.',
            entityName: 'Barber',
            entityId: barberId,
          );
        }

        final barberData = barberSnap.data()!;
        bool barberUserActive;
        String? barberName = barberData['fullName'] as String?;
        if (barberData['userIsActive'] is bool && barberName != null) {
          barberUserActive = barberData['userIsActive'] as bool;
        } else {
          final barberUserSnap =
              await tx.get(_users.doc(barberData['userId'] as String));
          final uData = barberUserSnap.data();
          barberUserActive = uData?['isActive'] as bool? ?? false;
          if (uData != null) {
            barberName ??=
                '${uData['firstName'] ?? ''} ${uData['lastName'] ?? ''}'.trim();
          }
        }

        final customerSnap = customerId == null
            ? null
            : await tx.get(_customers.doc(customerId));
        final attendanceSnap = await tx.get(_attendance.doc(attendanceDocId));

        final uniqueServiceIds = items.map((i) => i.serviceId).toSet();
        final resolvedServices = <String, Service>{};
        for (final serviceId in uniqueServiceIds) {
          final serviceSnap = await tx.get(_services.doc(serviceId));
          if (!serviceSnap.exists || serviceSnap.data() == null) {
            throw NotFoundFailure(
              message: 'Service $serviceId not found.',
              entityName: 'Service',
              entityId: serviceId,
            );
          }
          resolvedServices[serviceId] = ServiceFirestoreDto.fromFirestore(
            serviceSnap.id,
            serviceSnap.data()!,
          ).toDomain();
        }

        // 2. Domain validations:
        if (barberData['status'] != BarberStatus.active.dbValue ||
            !barberUserActive) {
          throw ValidationFailure(
            message: 'Barber $barberId is inactive and cannot serve visits.',
            field: 'barberId',
          );
        }

        String? customerName;
        if (customerId != null) {
          if (customerSnap == null ||
              !customerSnap.exists ||
              customerSnap.data() == null) {
            throw NotFoundFailure(
              message: 'Customer $customerId not found.',
              entityName: 'Customer',
              entityId: customerId,
            );
          }
          final cData = customerSnap.data()!;
          customerName =
              '${cData['firstName'] ?? ''} ${cData['lastName'] ?? ''}'.trim();
        }

        if (!attendanceSnap.exists ||
            attendanceSnap.data() == null ||
            attendanceSnap.data()!['status'] !=
                AttendanceStatus.present.dbValue) {
          throw ValidationFailure(
            message:
                'Barber $barberId must be marked PRESENT on ${ShopDateUtils.formatIsoDate(shopDate)} before logging a transaction.',
            field: 'barberId',
          );
        }

        var totalCentavos = 0;
        var haircutCount = 0;
        var haircutCentavos = 0;
        final builtItems = <TransactionItem>[];

        for (final input in items) {
          if (input.quantity <= 0) {
            throw const ValidationFailure(
              message: 'Service quantity must be greater than zero.',
              field: 'quantity',
            );
          }
          final service = resolvedServices[input.serviceId]!;
          if (!service.isActive) {
            throw ValidationFailure(
              message: 'Service "${service.serviceName}" is inactive.',
              field: 'serviceId',
            );
          }
          final subtotal = MoneyMath.multiply(service.price, input.quantity);
          final subtotalCentavos = MoneyMath.toCentavos(subtotal);
          totalCentavos += subtotalCentavos;
          if (service.isHaircut) {
            haircutCount += input.quantity;
            haircutCentavos += subtotalCentavos;
          }
          builtItems.add(
            TransactionItem(
              itemId: _uuid.v4(),
              transactionId: txId,
              serviceId: service.serviceId,
              serviceName: service.serviceName,
              isHaircut: service.isHaircut,
              quantity: input.quantity,
              unitPrice: service.price,
              subtotal: subtotal,
            ),
          );
        }

        final totalAmount = MoneyMath.fromCentavos(totalCentavos);
        var txStatus = TransactionStatus.pending;
        var paidAmount = 0.0;
        Payment? createdPayment;

        if (initialPayment != null) {
          final initCentavos = MoneyMath.toCentavos(initialPayment.amount);
          if (initCentavos <= 0) {
            throw const ValidationFailure(
              message: 'Initial payment amount must be greater than zero.',
              field: 'amount',
            );
          }
          if (initCentavos > totalCentavos) {
            throw const ValidationFailure(
              message: 'Initial payment exceeds transaction total.',
              field: 'amount',
            );
          }
          paidAmount = MoneyMath.fromCentavos(initCentavos);
          if (initCentavos == totalCentavos) {
            txStatus = TransactionStatus.paid;
          }
          createdPayment = Payment(
            paymentId: _uuid.v4(),
            transactionId: txId,
            receivedBy: loggedByStaffId,
            amount: paidAmount,
            paymentMethod: initialPayment.paymentMethod,
            referenceNo: FirestoreParseUtils.cleanNullableText(
              initialPayment.referenceNo,
            ),
            paidAt: utcTxDate,
          );
        }

        final domainTx = Transaction(
          transactionId: txId,
          customerId: customerId,
          barberId: barberId,
          loggedBy: loggedByStaffId,
          transactionDate: utcTxDate,
          totalAmount: totalAmount,
          status: txStatus,
        );

        final itemDtos = builtItems
            .map(TransactionItemFirestoreDto.fromDomain)
            .toList(growable: false);
        final txDto = TransactionFirestoreDto.fromDomain(
          domainTx,
          customerName: customerName,
          barberName: barberName,
          paidAmount: paidAmount,
          haircutCount: haircutCount,
          haircutGrossSales: MoneyMath.fromCentavos(haircutCentavos),
          itemsSummary: itemDtos,
        );

        // 3. Writes:
        final txRef = _transactions.doc(txId);
        tx.set(txRef, txDto.toFirestore());
        for (final itemDto in itemDtos) {
          tx.set(
            txRef.collection('items').doc(itemDto.itemId),
            itemDto.toFirestore(),
          );
        }
        if (createdPayment != null) {
          tx.set(
            _payments.doc(createdPayment.paymentId),
            PaymentFirestoreDto.fromDomain(createdPayment).toFirestore(),
          );
        }

        return TransactionWithDetails(
          transaction: domainTx,
          items: builtItems,
          payments: createdPayment == null
              ? const <Payment>[]
              : <Payment>[createdPayment],
        );
      });
    });
  }

  @override
  Future<Result<Transaction>> getTransactionById(String transactionId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _transactions.doc(transactionId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      return TransactionFirestoreDto.fromFirestore(doc.id, doc.data()!)
          .toDomain();
    });
  }

  @override
  Future<Result<TransactionWithDetails>> getTransactionWithDetails(
    String transactionId,
  ) {
    return FirestoreErrorMapper.guard(() async {
      final txDoc = await _transactions.doc(transactionId).get();
      if (!txDoc.exists || txDoc.data() == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }

      final txDto =
          TransactionFirestoreDto.fromFirestore(txDoc.id, txDoc.data()!);

      // Use denormalized itemsSummary when present; fall back to subcollection.
      List<TransactionItem> items;
      if (txDto.itemsSummary.isNotEmpty) {
        items = txDto.itemsSummary
            .map((dto) => dto.toDomain())
            .toList(growable: false);
      } else {
        final itemsSnap =
            await _transactions.doc(transactionId).collection('items').get();
        items = itemsSnap.docs
            .map(
              (doc) => TransactionItemFirestoreDto.fromFirestore(
                doc.id,
                doc.data(),
                fallbackTransactionId: transactionId,
              ).toDomain(),
            )
            .toList(growable: false);
      }

      final paymentsSnap = await _payments
          .where('transactionId', isEqualTo: transactionId)
          .get();
      final payments = paymentsSnap.docs
          .map(
            (doc) => PaymentFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false)
        ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

      return TransactionWithDetails(
        transaction: txDto.toDomain(),
        items: items,
        payments: payments,
      );
    });
  }

  @override
  Future<Result<List<Transaction>>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? barberId,
    TransactionStatus? status,
  }) {
    return FirestoreErrorMapper.guard(() async {
      fs.Query<Map<String, dynamic>> query = _transactions;

      if (barberId != null) {
        query = query.where('barberId', isEqualTo: barberId);
      }
      if (status != null) {
        query = query.where('status', isEqualTo: status.dbValue);
      }

      if (startDate != null && endDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: endDate,
        );
        query = query
            .where(
              'transactionDate',
              isGreaterThanOrEqualTo:
                  fs.Timestamp.fromDate(range.startUtcInclusive),
            )
            .where(
              'transactionDate',
              isLessThan: fs.Timestamp.fromDate(range.endUtcExclusive),
            );
      } else if (startDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: startDate,
        );
        query = query.where(
          'transactionDate',
          isGreaterThanOrEqualTo:
              fs.Timestamp.fromDate(range.startUtcInclusive),
        );
      } else if (endDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: endDate,
          endDate: endDate,
        );
        query = query.where(
          'transactionDate',
          isLessThan: fs.Timestamp.fromDate(range.endUtcExclusive),
        );
      }

      final snap =
          await query.orderBy('transactionDate', descending: true).get();
      return snap.docs
          .map(
            (doc) => TransactionFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<Transaction>>> watchTransactionsByDate(DateTime shopDate) {
    final isoDate = ShopDateUtils.formatIsoDate(
      ShopDateUtils.normalizeDate(shopDate),
    );
    final stream = _transactions
        .where('shopDate', isEqualTo: isoDate)
        .orderBy('transactionDate', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    TransactionFirestoreDto.fromFirestore(doc.id, doc.data())
                        .toDomain(),
              )
              .toList(growable: false),
        );
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Transaction>> voidTransaction({
    required String transactionId,
    required String actingUserId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      // Pre-check payroll period lock via query before entering client
      // `runTransaction` (Firestore client transactions only support `doc.get`).
      final initialSnap = await _transactions.doc(transactionId).get();
      if (!initialSnap.exists || initialSnap.data() == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      final initialTx = TransactionFirestoreDto.fromFirestore(
        initialSnap.id,
        initialSnap.data()!,
      ).toDomain();

      if (initialTx.status == TransactionStatus.paid) {
        final txShopDate =
            ShopDateUtils.toShopLocalDate(initialTx.transactionDate);
        if (await _isShopDateLocked(txShopDate)) {
          throw const ValidationFailure(
            message:
                'Cannot void a PAID transaction covered by an APPROVED or PAID payroll period.',
          );
        }
      }

      return _firestore.runTransaction((tx) async {
        final txRef = _transactions.doc(transactionId);
        final txSnap = await tx.get(txRef);
        if (!txSnap.exists || txSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Transaction $transactionId not found.',
            entityName: 'Transaction',
            entityId: transactionId,
          );
        }

        final current = TransactionFirestoreDto.fromFirestore(
          txSnap.id,
          txSnap.data()!,
        ).toDomain();

        if (current.status == TransactionStatus.voided) {
          throw ValidationFailure(
            message: 'Transaction $transactionId is already VOID.',
          );
        }

        if (current.status == TransactionStatus.pending) {
          await FirestoreParseUtils.assertActiveUserRole(
            _firestore,
            actingUserId: actingUserId,
            allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
            tx: tx,
          );
        } else if (current.status == TransactionStatus.paid) {
          await FirestoreParseUtils.assertActiveUserRole(
            _firestore,
            actingUserId: actingUserId,
            allowedRoles: const <RoleName>[RoleName.owner],
            tx: tx,
          );
        }

        tx.update(txRef, <String, dynamic>{
          'status': TransactionStatus.voided.dbValue,
        });
        return current.copyWith(status: TransactionStatus.voided);
      });
    });
  }

  Future<bool> _isShopDateLocked(DateTime shopDate) async {
    final normalized = ShopDateUtils.normalizeDate(shopDate);
    final snap = await _payrollPeriods.where(
      'status',
      whereIn: <String>[
        PayrollPeriodStatus.approved.dbValue,
        PayrollPeriodStatus.paid.dbValue,
      ],
    ).get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final start = FirestoreParseUtils.parseDate(data['startDate']);
      final end = FirestoreParseUtils.parseDate(data['endDate']);
      if (!normalized.isBefore(start) && !normalized.isAfter(end)) {
        return true;
      }
    }
    return false;
  }
}
