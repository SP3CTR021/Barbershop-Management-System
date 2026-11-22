import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runRoleRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('RoleRepository contract', () {
    test('seedDefaultRoles is idempotent and populates OWNER, STAFF, BARBER',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final firstSeed = (await harness.roles.seedDefaultRoles()).getOrThrow();
      final secondSeed = (await harness.roles.seedDefaultRoles()).getOrThrow();
      final all = (await harness.roles.getAllRoles()).getOrThrow();

      expect(firstSeed.map((r) => r.roleName).toSet(), {
        RoleName.owner,
        RoleName.staff,
        RoleName.barber,
      });
      expect(secondSeed.length, 3);
      expect(all.length, 3);
    });

    test('getRoleByName and getRoleById return matching role', () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      await harness.roles.seedDefaultRoles();

      final staffByName =
          (await harness.roles.getRoleByName(RoleName.staff)).getOrThrow();
      final staffById =
          (await harness.roles.getRoleById(staffByName.roleId)).getOrThrow();

      expect(staffByName.roleName, RoleName.staff);
      expect(staffById, staffByName);
    });

    test('getRoleById returns NotFoundFailure for unknown ID', () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final res = await harness.roles.getRoleById('missing-role-id');
      expect(res.failureOrNull, isA<NotFoundFailure>());
    });
  });
}
