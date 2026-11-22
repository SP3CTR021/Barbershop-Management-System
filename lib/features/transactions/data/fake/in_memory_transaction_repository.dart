import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// In-memory fake implementation of [TransactionRepository].
final class InMemoryTransactionRepository implements TransactionRepository {
  InMemoryTransactionRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<TransactionWithDetails>> createTransaction({
    String? customerId,
    required String barberId,
    required String loggedByStaffId,
    required DateTime transactionDate,
    required List<CreateTransactionItemInput> items,
    InitialPaymentInput? initialPayment,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: loggedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      if (items.isEmpty) {
        throw const ValidationFailure(
          message: 'A transaction must contain at least one service item.',
          field: 'items',
        );
      }

      if (customerId != null && !_db.customers.containsKey(customerId)) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }

      final barber = _db.barbers[barberId];
      if (barber == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      final barberUser = _db.users[barber.userId];
      if (barber.status != BarberStatus.active ||
          !(barberUser?.isActive ?? false)) {
        throw ValidationFailure(
          message: 'Barber $barberId is inactive and cannot serve visits.',
          field: 'barberId',
        );
      }

      final utcDate = transactionDate.toUtc();
      final shopDate = ShopDateUtils.toShopLocalDate(utcDate);
      final attendance = _db.attendance[_db.attendanceKey(barberId, shopDate)];
      if (attendance == null || attendance.status != AttendanceStatus.present) {
        throw ValidationFailure(
          message:
              'Barber $barberId must be marked PRESENT on ${ShopDateUtils.formatIsoDate(shopDate)} before logging a transaction.',
          field: 'barberId',
        );
      }

      final txId = _db.nextId();
      var totalCentavos = 0;
      final builtItems = <TransactionItem>[];

      for (final input in items) {
        if (input.quantity <= 0) {
          throw const ValidationFailure(
            message: 'Service quantity must be greater than zero.',
            field: 'quantity',
          );
        }
        final service = _db.services[input.serviceId];
        if (service == null) {
          throw NotFoundFailure(
            message: 'Service ${input.serviceId} not found.',
            entityName: 'Service',
            entityId: input.serviceId,
          );
        }
        if (!service.isActive) {
          throw ValidationFailure(
            message: 'Service "${service.serviceName}" is inactive.',
            field: 'serviceId',
          );
        }

        final subtotal = MoneyMath.multiply(service.price, input.quantity);
        totalCentavos += MoneyMath.toCentavos(subtotal);
        builtItems.add(
          TransactionItem(
            itemId: _db.nextId(),
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

      var txStatus = TransactionStatus.pending;
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
        if (initCentavos == totalCentavos) {
          txStatus = TransactionStatus.paid;
        }
        final cleanRef = initialPayment.referenceNo?.trim();
        createdPayment = Payment(
          paymentId: _db.nextId(),
          transactionId: txId,
          receivedBy: loggedByStaffId,
          amount: MoneyMath.fromCentavos(initCentavos),
          paymentMethod: initialPayment.paymentMethod,
          referenceNo: (cleanRef == null || cleanRef.isEmpty) ? null : cleanRef,
          paidAt: utcDate,
        );
      }

      final tx = Transaction(
        transactionId: txId,
        customerId: customerId,
        barberId: barberId,
        loggedBy: loggedByStaffId,
        transactionDate: utcDate,
        totalAmount: MoneyMath.fromCentavos(totalCentavos),
        status: txStatus,
      );

      _db.transactions[txId] = tx;
      _db.transactionItemsByTxId[txId] = builtItems;
      if (createdPayment != null) {
        _db.payments[createdPayment.paymentId] = createdPayment;
      }
      _db.notifyChanged();

      return TransactionWithDetails(
        transaction: tx,
        items: builtItems,
        payments: createdPayment == null
            ? const <Payment>[]
            : <Payment>[createdPayment],
      );
    });
  }

  @override
  Future<Result<Transaction>> getTransactionById(String transactionId) {
    return _db.guard(() {
      final tx = _db.transactions[transactionId];
      if (tx == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      return tx;
    });
  }

  @override
  Future<Result<TransactionWithDetails>> getTransactionWithDetails(
    String transactionId,
  ) {
    return _db.guard(() {
      final tx = _db.transactions[transactionId];
      if (tx == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      final items =
          _db.transactionItemsByTxId[transactionId] ?? const <TransactionItem>[];
      final payments = _db.payments.values
          .where((p) => p.transactionId == transactionId)
          .toList(growable: false)
        ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

      return TransactionWithDetails(
        transaction: tx,
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
    return _db.guard(() {
      DateTime? startUtc;
      DateTime? endUtcExcl;

      if (startDate != null && endDate != null) {
        final range = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: endDate,
        );
        startUtc = range.startUtcInclusive;
        endUtcExcl = range.endUtcExclusive;
      } else if (startDate != null) {
        startUtc = ShopDateUtils.utcRangeForShopDateRange(
          startDate: startDate,
          endDate: startDate,
        ).startUtcInclusive;
      } else if (endDate != null) {
        endUtcExcl = ShopDateUtils.utcRangeForShopDateRange(
          startDate: endDate,
          endDate: endDate,
        ).endUtcExclusive;
      }

      final list = _db.transactions.values.where((tx) {
        if (barberId != null && tx.barberId != barberId) return false;
        if (status != null && tx.status != status) return false;
        if (startUtc != null && tx.transactionDate.isBefore(startUtc)) {
          return false;
        }
        if (endUtcExcl != null && !tx.transactionDate.isBefore(endUtcExcl)) {
          return false;
        }
        return true;
      }).toList(growable: false)
        ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
      return list;
    });
  }

  @override
  Stream<Result<List<Transaction>>> watchTransactionsByDate(DateTime shopDate) {
    final range = ShopDateUtils.utcRangeForShopDateRange(
      startDate: shopDate,
      endDate: shopDate,
    );
    return _db.watchQuery(() {
      final list = _db.transactions.values
          .where(
            (tx) =>
                !tx.transactionDate.isBefore(range.startUtcInclusive) &&
                tx.transactionDate.isBefore(range.endUtcExclusive),
          )
          .toList(growable: false)
        ..sort((a, b) => b.transactionDate.compareTo(a.transactionDate));
      return list;
    });
  }

  @override
  Future<Result<Transaction>> voidTransaction({
    required String transactionId,
    required String actingUserId,
  }) {
    return _db.guard(() {
      final existing = _db.transactions[transactionId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Transaction $transactionId not found.',
          entityName: 'Transaction',
          entityId: transactionId,
        );
      }
      if (existing.status == TransactionStatus.voided) {
        throw ValidationFailure(
          message: 'Transaction $transactionId is already VOID.',
        );
      }

      if (existing.status == TransactionStatus.pending) {
        _db.assertActiveUserRole(
          actingUserId: actingUserId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
        );
      } else if (existing.status == TransactionStatus.paid) {
        _db.assertActiveUserRole(
          actingUserId: actingUserId,
          allowedRoles: const <RoleName>[RoleName.owner],
        );
        final txShopDate =
            ShopDateUtils.toShopLocalDate(existing.transactionDate);
        if (_db.isDateLockedByPayroll(txShopDate)) {
          throw const ValidationFailure(
            message:
                'Cannot void a PAID transaction covered by an APPROVED or PAID payroll period.',
          );
        }
      }

      final updated = existing.copyWith(status: TransactionStatus.voided);
      _db.transactions[transactionId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }
}
