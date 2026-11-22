import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runPayrollRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('PayrollRepository contract', () {
    test('generates 15-day haircut-only 60/40 payroll, preserves snapshot, and pays out',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      // Add a second active barber with 0 haircuts in the period.
      final zeroBarber = (await harness.barbers.createBarberWithProfile(
        firstName: 'Leo',
        lastName: 'Cruz',
        username: 'barber_leo',
        hireDate: DateTime.utc(2026, 1, 15),
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();

      // Validate sharesSumTo100 & OWNER role on settings.
      final badSplit = await harness.payroll.createPayrollSetting(
        createdByOwnerId: fixture.owner.userId,
        ownerSharePct: 70.0,
        barberSharePct: 40.0,
        effectiveFrom: DateTime.utc(2026, 11, 1),
      );
      expect(badSplit.failureOrNull, isA<ValidationFailure>());

      final initialSetting = (await harness.payroll.createPayrollSetting(
        createdByOwnerId: fixture.owner.userId,
        ownerSharePct: 60.0,
        barberSharePct: 40.0,
        effectiveFrom: DateTime.utc(2026, 11, 1),
      ))
          .getOrThrow();
      expect(initialSetting.isActive, isTrue);

      final nov5 = DateTime.utc(2026, 11, 5);
      (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: nov5,
        timeIn: const ShopTime(hour: 8, minute: 0),
      ))
          .getOrThrow();

      // ERD example: 50 haircuts @ 150 = 7,500.00 (4,500 owner / 3,000 barber)
      // plus 2 Beard Trims (isHaircut = false) excluded from haircut payroll!
      (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 4, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
            quantity: 50,
          ),
          CreateTransactionItemInput(
            serviceId: fixture.shaveService.serviceId,
            quantity: 2,
          ),
        ],
        initialPayment: InitialPaymentInput(
          amount: 7700.0,
          paymentMethod: PaymentMethod.cash,
        ),
      ))
          .getOrThrow();

      // PENDING transaction must be excluded from payroll.
      (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 5, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
            quantity: 5,
          ),
        ],
      ))
          .getOrThrow();

      // VOID transaction must also be excluded from payroll.
      final toVoid = (await harness.transactions.createTransaction(
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 5, 6, 0),
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
            quantity: 3,
          ),
        ],
        initialPayment: InitialPaymentInput(
          amount: 450.0,
          paymentMethod: PaymentMethod.cash,
        ),
      ))
          .getOrThrow();
      (await harness.transactions.voidTransaction(
        transactionId: toVoid.transaction.transactionId,
        actingUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      final periodStart = DateTime.utc(2026, 11, 1);
      final periodEnd = DateTime.utc(2026, 11, 15);
      final generated = (await harness.payroll.generatePayrollPeriod(
        startDate: periodStart,
        endDate: periodEnd,
        generatedByUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      expect(generated.period.status, PayrollPeriodStatus.draft);
      expect(generated.records.length, 2);

      final markRecord = generated.records
          .firstWhere((r) => r.barberId == fixture.barber.barberId);
      final leoRecord =
          generated.records.firstWhere((r) => r.barberId == zeroBarber.barberId);

      expect(markRecord.totalHaircuts, 50);
      expect(markRecord.grossSales, 7500.0);
      expect(markRecord.ownerSharePct, 60.0);
      expect(markRecord.barberSharePct, 40.0);
      expect(markRecord.ownerShareAmount, 4500.0);
      expect(markRecord.barberPayAmount, 3000.0);

      expect(leoRecord.totalHaircuts, 0);
      expect(leoRecord.grossSales, 0.0);

      // Overlapping payroll period must fail with ConflictFailure.
      final overlap = await harness.payroll.generatePayrollPeriod(
        startDate: DateTime.utc(2026, 11, 10),
        endDate: DateTime.utc(2026, 11, 25),
        generatedByUserId: fixture.owner.userId,
      );
      expect(overlap.failureOrNull, isA<ConflictFailure>());

      // Changing split to 50/50 closes previous setting and keeps old snapshot intact.
      final updatedSetting = (await harness.payroll.createPayrollSetting(
        createdByOwnerId: fixture.owner.userId,
        ownerSharePct: 50.0,
        barberSharePct: 50.0,
        effectiveFrom: DateTime.utc(2026, 11, 16),
      ))
          .getOrThrow();
      expect(updatedSetting.isActive, isTrue);

      final history =
          (await harness.payroll.getPayrollSettingsHistory()).getOrThrow();
      expect(history.where((s) => s.isActive).length, 1);

      final snapshotCheck = (await harness.payroll.getPayrollPeriodWithRecords(
        generated.period.periodId,
      ))
          .getOrThrow();
      expect(snapshotCheck.setting.ownerSharePct, 60.0);

      // Paying before approval must fail.
      final payBeforeApprove = await harness.payroll.markPayrollRecordPaid(
        payrollId: markRecord.payrollId,
        ownerUserId: fixture.owner.userId,
      );
      expect(payBeforeApprove.failureOrNull, isA<ValidationFailure>());

      expect(
        (await harness.payroll.isDateLockedByPayroll(nov5)).getOrThrow(),
        isFalse,
      );

      final approved = (await harness.payroll.approvePayrollPeriod(
        periodId: generated.period.periodId,
        ownerUserId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(approved.status, PayrollPeriodStatus.approved);
      expect(
        (await harness.payroll.isDateLockedByPayroll(nov5)).getOrThrow(),
        isTrue,
      );

      final paidMark = (await harness.payroll.markPayrollRecordPaid(
        payrollId: markRecord.payrollId,
        ownerUserId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(paidMark.status, PayrollRecordStatus.paid);

      // Parent period stays APPROVED until all barber records are PAID.
      expect(
        (await harness.payroll.getPayrollPeriodWithRecords(
          generated.period.periodId,
        ))
            .getOrThrow()
            .period
            .status,
        PayrollPeriodStatus.approved,
      );

      (await harness.payroll.markPayrollRecordPaid(
        payrollId: leoRecord.payrollId,
        ownerUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      final completedPeriod = (await harness.payroll.getPayrollPeriodWithRecords(
        generated.period.periodId,
      ))
          .getOrThrow();
      expect(completedPeriod.period.status, PayrollPeriodStatus.paid);

      final barberHistory = (await harness.payroll.getPayrollRecordsForBarber(
        fixture.barber.barberId,
      ))
          .getOrThrow();
      expect(barberHistory.length, 1);
      expect(barberHistory.first.barberPayAmount, 3000.0);
    });
  });
}
