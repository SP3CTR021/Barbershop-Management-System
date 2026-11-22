import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runTransactionRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('TransactionRepository contract', () {
    test('enforces PRESENT attendance rule, snapshots prices, and handles +08:00 boundaries',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      // Absent / unchecked-in barber is rejected (Business Rule #3).
      final blocked = await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 16, 2, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
        ],
      );
      expect(blocked.failureOrNull, isA<ValidationFailure>());

      // Check in for shop-local 2026-11-16.
      final shopDate = DateTime.utc(2026, 11, 16);
      (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: shopDate,
        timeIn: const ShopTime(hour: 7, minute: 0),
      ))
          .getOrThrow();

      // 2026-11-15T23:30:00Z == 2026-11-16 07:30 +08:00 (must resolve to Nov 16).
      final earlyMorningTx = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 15, 23, 30),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
            quantity: 1,
          ),
          CreateTransactionItemInput(
            serviceId: fixture.shaveService.serviceId,
            quantity: 1,
          ),
        ],
        initialPayment: InitialPaymentInput(
          amount: 250.0,
          paymentMethod: PaymentMethod.cash,
        ),
      ))
          .getOrThrow();

      expect(earlyMorningTx.transaction.totalAmount, 250.0);
      expect(earlyMorningTx.transaction.status, TransactionStatus.paid);
      expect(earlyMorningTx.totalHaircutQuantity, 1);
      expect(earlyMorningTx.haircutGrossSales, 150.0);

      // Updating service catalog later does NOT alter historical snapshots (Rule #5).
      (await harness.services.updateService(
        service: fixture.haircutService.copyWith(
          serviceName: 'Renamed Cut',
          price: 300.0,
          isHaircut: false,
        ),
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();

      final reloaded = (await harness.transactions.getTransactionWithDetails(
        earlyMorningTx.transaction.transactionId,
      ))
          .getOrThrow();
      expect(reloaded.items.first.serviceName, 'Classic Haircut');
      expect(reloaded.items.first.unitPrice, 150.0);
      expect(reloaded.items.first.isHaircut, isTrue);

      final nov16Txs = (await harness.transactions.getTransactions(
        startDate: shopDate,
        endDate: shopDate,
      ))
          .getOrThrow();
      expect(nov16Txs.map((t) => t.transactionId), [
        earlyMorningTx.transaction.transactionId,
      ]);

      final nov15Txs = (await harness.transactions.getTransactions(
        startDate: DateTime.utc(2026, 11, 15),
        endDate: DateTime.utc(2026, 11, 15),
      ))
          .getOrThrow();
      expect(nov15Txs, isEmpty);
    });

    test('voidTransaction rules: STAFF voids PENDING only; OWNER voids PAID unless payroll-locked',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      (await harness.payroll.createPayrollSetting(
        createdByOwnerId: fixture.owner.userId,
        ownerSharePct: 60.0,
        barberSharePct: 40.0,
        effectiveFrom: DateTime.utc(2026, 11, 1),
      ))
          .getOrThrow();

      final workDate = DateTime.utc(2026, 11, 5);
      (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: workDate,
        timeIn: const ShopTime(hour: 9, minute: 0),
      ))
          .getOrThrow();

      final pendingTx = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 3, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
        ],
      ))
          .getOrThrow();

      final voidedPending = (await harness.transactions.voidTransaction(
        transactionId: pendingTx.transaction.transactionId,
        actingUserId: fixture.staff.userId,
      ))
          .getOrThrow();
      expect(voidedPending.status, TransactionStatus.voided);

      final paidTx1 = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 4, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
        ],
        initialPayment: InitialPaymentInput(
          amount: 150.0,
          paymentMethod: PaymentMethod.cash,
        ),
      ))
          .getOrThrow();

      final paidTx2 = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 5, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
        ],
        initialPayment: InitialPaymentInput(
          amount: 150.0,
          paymentMethod: PaymentMethod.gcash,
          referenceNo: 'GC-100',
        ),
      ))
          .getOrThrow();

      // STAFF cannot void a PAID transaction.
      final staffVoidPaid = await harness.transactions.voidTransaction(
        transactionId: paidTx1.transaction.transactionId,
        actingUserId: fixture.staff.userId,
      );
      expect(staffVoidPaid.failureOrNull, isA<PermissionDeniedFailure>());

      // OWNER can void PAID while no APPROVED/PAID payroll locks that date.
      final ownerVoidPaid = (await harness.transactions.voidTransaction(
        transactionId: paidTx1.transaction.transactionId,
        actingUserId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(ownerVoidPaid.status, TransactionStatus.voided);

      // Generate and APPROVE Nov 1..15 payroll period -> locks paidTx2.
      final generated = (await harness.payroll.generatePayrollPeriod(
        startDate: DateTime.utc(2026, 11, 1),
        endDate: DateTime.utc(2026, 11, 15),
        generatedByUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      (await harness.payroll.approvePayrollPeriod(
        periodId: generated.period.periodId,
        ownerUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      final lockedVoid = await harness.transactions.voidTransaction(
        transactionId: paidTx2.transaction.transactionId,
        actingUserId: fixture.owner.userId,
      );
      expect(lockedVoid.failureOrNull, isA<ValidationFailure>());
    });
  });
}
