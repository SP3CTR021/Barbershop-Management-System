import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runAuthRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('AuthRepository contract', () {
    test('registers OWNER and STAFF and rejects BARBER login registration',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      await harness.roles.seedDefaultRoles();

      final owner = (await harness.auth.registerLoginAccount(
        roleName: RoleName.owner,
        firstName: 'Elena',
        lastName: 'Reyes',
        username: 'owner_elena',
        email: 'owner@shop.test',
        password: 'Password123!',
      ))
          .getOrThrow();

      final staff = (await harness.auth.registerLoginAccount(
        roleName: RoleName.staff,
        firstName: 'Carlo',
        lastName: 'Mendoza',
        username: 'staff_carlo',
        email: 'staff@shop.test',
        password: 'Password123!',
        createdByOwnerId: owner.userId,
      ))
          .getOrThrow();

      expect(staff.username, 'staff_carlo');

      final barberAttempt = await harness.auth.registerLoginAccount(
        roleName: RoleName.barber,
        firstName: 'Mark',
        lastName: 'Santos',
        username: 'barber_mark',
        email: 'mark@shop.test',
        password: 'Password123!',
        createdByOwnerId: owner.userId,
      );
      expect(barberAttempt.failureOrNull, isA<ValidationFailure>());
    });

    test('signIn works with email or case-insensitive username and updates watchAuthState',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      (await harness.auth.signOut()).getOrThrow();
      expect((await harness.auth.getCurrentUser()).getOrThrow(), isNull);

      final authEvents = <String?>[];
      final sub = harness.auth.watchAuthState().listen(
            (user) => authEvents.add(user?.userId),
          );
      addTearDown(sub.cancel);

      final signedInByEmail = (await harness.auth.signIn(
        emailOrUsername: 'staff@shop.test',
        password: 'Password123!',
      ))
          .getOrThrow();
      expect(signedInByEmail.userId, fixture.staff.userId);

      (await harness.auth.signOut()).getOrThrow();

      final signedInByUsername = (await harness.auth.signIn(
        emailOrUsername: 'OWNER_ELENA',
        password: 'Password123!',
      ))
          .getOrThrow();
      expect(signedInByUsername.userId, fixture.owner.userId);

      await pumpEventQueue();
      expect(authEvents, containsAllInOrder([fixture.staff.userId, null, fixture.owner.userId]));
    });

    test('rejects invalid password, duplicate credentials, and deactivated users',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();

      final badPass = await harness.auth.signIn(
        emailOrUsername: 'staff_carlo',
        password: 'wrong-password',
      );
      expect(badPass.failureOrNull, isA<UnauthenticatedFailure>());

      final dupUsername = await harness.auth.registerLoginAccount(
        roleName: RoleName.staff,
        firstName: 'Other',
        lastName: 'Staff',
        username: 'STAFF_CARLO',
        email: 'other@shop.test',
        password: 'Password123!',
        createdByOwnerId: fixture.owner.userId,
      );
      expect(dupUsername.failureOrNull, isA<DuplicateEntryFailure>());

      (await harness.users.setUserActiveStatus(
        userId: fixture.staff.userId,
        isActive: false,
        actingUserId: fixture.owner.userId,
      ))
          .getOrThrow();

      final disabledSignIn = await harness.auth.signIn(
        emailOrUsername: 'staff@shop.test',
        password: 'Password123!',
      );
      expect(disabledSignIn.failureOrNull, isA<PermissionDeniedFailure>());
    });
  });
}
