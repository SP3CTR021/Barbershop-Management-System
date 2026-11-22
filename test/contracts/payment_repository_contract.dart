import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runPaymentRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('PaymentRepository contract', () {
    test('supports split partial payments, auto-settles to PAID, and guards invalid payments',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      final workDate = DateTime.utc(2026, 11, 18);
      (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: workDate,
        timeIn: const ShopTime(hour: 9, minute: 0),
      ))
          .getOrThrow();

      // Total = 150 + 100 = 250.00
      final txDetails = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 18, 4, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
          CreateTransactionItemInput(
            serviceId: fixture.shaveService.serviceId,
          ),
        ],
      ))
          .getOrThrow();
      final txId = txDetails.transaction.transactionId;

      final p1 = (await harness.payments.recordPayment(
        transactionId: txId,
        receivedByStaffId: fixture.staff.userId,
        amount: 100.0,
        paymentMethod: PaymentMethod.cash,
        paidAt: DateTime.utc(2026, 11, 18, 4, 5),
      ))
          .getOrThrow();
      expect(p1.amount, 100.0);

      final afterFirst =
          (await harness.transactions.getTransactionWithDetails(txId)).getOrThrow();
      expect(afterFirst.transaction.status, TransactionStatus.pending);
      expect(afterFirst.remainingBalance, 150.0);

      final overpayment = await harness.payments.recordPayment(
        transactionId: txId,
        receivedByStaffId: fixture.staff.userId,
        amount: 200.0,
        paymentMethod: PaymentMethod.gcash,
      );
      expect(overpayment.failureOrNull, isA<ValidationFailure>());

      (await harness.payments.recordPayment(
        transactionId: txId,
        receivedByStaffId: fixture.staff.userId,
        amount: 150.0,
        paymentMethod: PaymentMethod.gcash,
        referenceNo: 'GCASH-888',
        paidAt: DateTime.utc(2026, 11, 18, 4, 10),
      ))
          .getOrThrow();

      final settled =
          (await harness.transactions.getTransactionWithDetails(txId)).getOrThrow();
      expect(settled.transaction.status, TransactionStatus.paid);
      expect(settled.totalPaid, 250.0);
      expect(settled.remainingBalance, 0.0);

      final alreadyPaidAttempt = await harness.payments.recordPayment(
        transactionId: txId,
        receivedByStaffId: fixture.staff.userId,
        amount: 10.0,
        paymentMethod: PaymentMethod.cash,
      );
      expect(alreadyPaidAttempt.failureOrNull, isA<ValidationFailure>());

      final gcashOnly = (await harness.payments.getPaymentsByDateRange(
        startDate: workDate,
        endDate: workDate,
        paymentMethod: PaymentMethod.gcash,
      ))
          .getOrThrow();
      expect(gcashOnly.length, 1);
      expect(gcashOnly.first.referenceNo, 'GCASH-888');
    });
  });
}
