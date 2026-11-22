import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';

/// In-memory fake implementation of [RoleRepository].
final class InMemoryRoleRepository implements RoleRepository {
  InMemoryRoleRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<List<Role>>> getAllRoles() {
    return _db.guard(() {
      final list = _db.roles.values.toList(growable: false)
        ..sort((a, b) => a.roleName.dbValue.compareTo(b.roleName.dbValue));
      return list;
    });
  }

  @override
  Future<Result<Role>> getRoleById(String roleId) {
    return _db.guard(() {
      final role = _db.roles[roleId];
      if (role == null) {
        throw NotFoundFailure(
          message: 'Role $roleId not found.',
          entityName: 'Role',
          entityId: roleId,
        );
      }
      return role;
    });
  }

  @override
  Future<Result<Role>> getRoleByName(RoleName roleName) {
    return _db.guard(() {
      for (final role in _db.roles.values) {
        if (role.roleName == roleName) return role;
      }
      throw NotFoundFailure(
        message: 'Role ${roleName.dbValue} not found.',
        entityName: 'Role',
        entityId: roleName.dbValue,
      );
    });
  }

  @override
  Future<Result<List<Role>>> seedDefaultRoles() {
    return _db.guard(() {
      final defaults = <Role>[
        Role(
          roleId: _db.roleDocId(RoleName.owner),
          roleName: RoleName.owner,
          description:
              'Shop owner with full management and payroll approval access',
        ),
        Role(
          roleId: _db.roleDocId(RoleName.staff),
          roleName: RoleName.staff,
          description:
              'Front desk staff managing attendance, visits, and payments',
        ),
        Role(
          roleId: _db.roleDocId(RoleName.barber),
          roleName: RoleName.barber,
          description:
              'Service provider earning haircut commission (logged by staff)',
        ),
      ];

      for (final role in defaults) {
        final alreadyExists =
            _db.roles.values.any((existing) => existing.roleName == role.roleName);
        if (!alreadyExists) {
          _db.roles[role.roleId] = role;
        }
      }
      _db.notifyChanged();

      final list = _db.roles.values.toList(growable: false)
        ..sort((a, b) => a.roleName.dbValue.compareTo(b.roleName.dbValue));
      return list;
    });
  }
}
