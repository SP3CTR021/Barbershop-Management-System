import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runBarberRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('BarberRepository contract', () {
    test('createBarberWithProfile enforces OWNER and links 1:1 user + barber',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final staffCreate = await harness.barbers.createBarberWithProfile(
        firstName: 'Unauthorized',
        lastName: 'Barber',
        username: 'unauth_barber',
        hireDate: DateTime.utc(2026, 2, 1),
        actingOwnerId: fixture.staff.userId,
      );
      expect(staffCreate.failureOrNull, isA<PermissionDeniedFailure>());

      final loaded = (await harness.barbers.getBarberWithUser(
        fixture.barber.barberId,
      ))
          .getOrThrow();
      final byUserId = (await harness.barbers.getBarberByUserId(
        fixture.barber.user.userId,
      ))
          .getOrThrow();

      expect(loaded.fullName, 'Mark Santos');
      expect(loaded.isAssignable, isTrue);
      expect(byUserId?.barberId, fixture.barber.barberId);
    });

    test('updateBarber, setBarberStatus syncs user.isActive, and watchBarbers filters',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final updated = (await harness.barbers.updateBarber(
        barber: fixture.barber.barber.copyWith(specialty: 'Razor Shaves'),
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();
      expect(updated.specialty, 'Razor Shaves');

      final activeWatch = <int>[];
      final sub = harness.barbers
          .watchBarbers(status: BarberStatus.active)
          .listen((res) => activeWatch.add(res.getOrThrow().length));
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(activeWatch.last, 1);

      (await harness.barbers.setBarberStatus(
        barberId: fixture.barber.barberId,
        status: BarberStatus.inactive,
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();

      await pumpEventQueue();
      expect(activeWatch.last, 0);

      final linkedUser = (await harness.users.getUserById(
        fixture.barber.user.userId,
      ))
          .getOrThrow();
      expect(linkedUser.isActive, isFalse);

      final activeList = (await harness.barbers.getBarbers(
        status: BarberStatus.active,
      ))
          .getOrThrow();
      expect(activeList, isEmpty);
    });
  });
}
