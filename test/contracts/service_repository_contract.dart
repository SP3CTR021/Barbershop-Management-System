import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runServiceRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('ServiceRepository contract', () {
    test('enforces OWNER role, unique name, non-negative price, and filters',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final staffCreate = await harness.services.createService(
        serviceName: 'Hot Towel',
        isHaircut: false,
        price: 80.0,
        actingOwnerId: fixture.staff.userId,
      );
      expect(staffCreate.failureOrNull, isA<PermissionDeniedFailure>());

      final duplicate = await harness.services.createService(
        serviceName: 'classic haircut',
        isHaircut: true,
        price: 150.0,
        actingOwnerId: fixture.owner.userId,
      );
      expect(duplicate.failureOrNull, isA<DuplicateEntryFailure>());

      final negativePrice = await harness.services.createService(
        serviceName: 'Invalid Cut',
        isHaircut: true,
        price: -10.0,
        actingOwnerId: fixture.owner.userId,
      );
      expect(negativePrice.failureOrNull, isA<ValidationFailure>());

      final haircutsOnly =
          (await harness.services.getServices(isHaircut: true)).getOrThrow();
      expect(haircutsOnly.map((s) => s.serviceId), [
        fixture.haircutService.serviceId,
      ]);

      final updated = (await harness.services.updateService(
        service: fixture.haircutService.copyWith(price: 180.0),
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(updated.price, 180.0);

      final deactivated = (await harness.services.setServiceActive(
        serviceId: fixture.shaveService.serviceId,
        isActive: false,
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(deactivated.isActive, isFalse);

      final activeOnly =
          (await harness.services.getServices(isActive: true)).getOrThrow();
      expect(activeOnly.map((s) => s.serviceId), [
        fixture.haircutService.serviceId,
      ]);
    });
  });
}
