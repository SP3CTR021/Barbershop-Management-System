import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runCustomerRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('CustomerRepository contract', () {
    test('CRUD, search by name/phone, and watchCustomers work as expected',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final invalid = await harness.customers.createCustomer(
        firstName: ' ',
        lastName: 'Doe',
      );
      expect(invalid.failureOrNull, isA<ValidationFailure>());

      final john = (await harness.customers.createCustomer(
        firstName: 'John',
        lastName: 'Cruz',
        phone: '09171234567',
      ))
          .getOrThrow();
      final jane = (await harness.customers.createCustomer(
        firstName: 'Jane',
        lastName: 'Dela Rosa',
        phone: '09987654321',
      ))
          .getOrThrow();

      final byPhone =
          (await harness.customers.getCustomers(searchQuery: '1234567'))
              .getOrThrow();
      expect(byPhone, [john]);

      final updatedJane = (await harness.customers.updateCustomer(
        jane.copyWith(phone: '09180000000'),
      ))
          .getOrThrow();
      expect(updatedJane.phone, '09180000000');

      final fetched =
          (await harness.customers.getCustomerById(john.customerId)).getOrThrow();
      expect(fetched.fullName, 'John Cruz');
    });

    test('deleteCustomer sets customerId to null on linked transactions (ON DELETE SET NULL)',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      final customer = (await harness.customers.createCustomer(
        firstName: 'Walk',
        lastName: 'Client',
      ))
          .getOrThrow();

      final workDate = DateTime.utc(2026, 11, 10);
      (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: workDate,
        timeIn: const ShopTime(hour: 9, minute: 0),
      ))
          .getOrThrow();

      final txDetails = (await harness.transactions.createTransaction(
        customerId: customer.customerId,
        barberId: fixture.barber.barberId,
        loggedByStaffId: fixture.staff.userId,
        transactionDate: DateTime.utc(2026, 11, 10, 2, 0), // 10:00 +08:00
        items: <CreateTransactionItemInput>[
          CreateTransactionItemInput(
            serviceId: fixture.haircutService.serviceId,
          ),
        ],
      ))
          .getOrThrow();
      expect(txDetails.transaction.customerId, customer.customerId);

      (await harness.customers.deleteCustomer(customer.customerId)).getOrThrow();

      final missing =
          await harness.customers.getCustomerById(customer.customerId);
      expect(missing.failureOrNull, isA<NotFoundFailure>());

      final preservedTx = (await harness.transactions.getTransactionById(
        txDetails.transaction.transactionId,
      ))
          .getOrThrow();
      expect(preservedTx.customerId, isNull);
    });
  });
}
