import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runUserRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('UserRepository contract', () {
    test('fetches by ID/username, filters by role/isActive, and streams watchUsers',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final byId =
          (await harness.users.getUserById(fixture.staff.userId)).getOrThrow();
      final byUsername =
          (await harness.users.getUserByUsername('STAFF_CARLO')).getOrThrow();
      expect(byId, fixture.staff);
      expect(byUsername, fixture.staff);

      final barbersOnly = (await harness.users.getUsers(
        roleFilter: RoleName.barber,
        isActive: true,
      ))
          .getOrThrow();
      expect(barbersOnly.map((u) => u.userId), [fixture.barber.user.userId]);

      final streamEvents = <int>[];
      final sub = harness.users
          .watchUsers(isActive: true)
          .listen((res) => streamEvents.add(res.getOrThrow().length));
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(streamEvents.last, 3);
    });

    test('updateUser checks uniqueness and setUserActiveStatus enforces OWNER & syncs barber',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final renamed = (await harness.users.updateUser(
        fixture.staff.copyWith(firstName: 'Carlos', phone: '09170001111'),
      ))
          .getOrThrow();
      expect(renamed.firstName, 'Carlos');
      expect(renamed.phone, '09170001111');

      final duplicateUpdate = await harness.users.updateUser(
        fixture.staff.copyWith(username: fixture.owner.username),
      );
      expect(duplicateUpdate.failureOrNull, isA<DuplicateEntryFailure>());

      final forbidden = await harness.users.setUserActiveStatus(
        userId: fixture.barber.user.userId,
        isActive: false,
        actingUserId: fixture.staff.userId,
      );
      expect(forbidden.failureOrNull, isA<PermissionDeniedFailure>());

      final deactivated = (await harness.users.setUserActiveStatus(
        userId: fixture.barber.user.userId,
        isActive: false,
        actingUserId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(deactivated.isActive, isFalse);

      final syncedBarber = (await harness.barbers.getBarberById(
        fixture.barber.barberId,
      ))
          .getOrThrow();
      expect(syncedBarber.status, BarberStatus.inactive);
    });
  });
}
