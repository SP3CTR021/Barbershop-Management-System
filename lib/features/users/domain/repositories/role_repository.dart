import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// Backend-agnostic contract for the `roles` lookup table/collection.
abstract interface class RoleRepository {
  Future<Result<List<Role>>> getAllRoles();

  Future<Result<Role>> getRoleById(String roleId);

  Future<Result<Role>> getRoleByName(RoleName roleName);

  /// Idempotently ensures the three canonical roles (`OWNER`, `STAFF`, `BARBER`)
  /// exist in the backing store and returns them.
  Future<Result<List<Role>>> seedDefaultRoles();
}
