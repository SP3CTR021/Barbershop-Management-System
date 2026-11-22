import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/data/firestore/role_firestore_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Cloud Firestore implementation of [RoleRepository] using deterministic role
/// document IDs (`role_owner`, `role_staff`, `role_barber`).
final class FirestoreRoleRepository implements RoleRepository {
  FirestoreRoleRepository(this._firestore);

  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _roles =>
      _firestore.collection('roles');

  @override
  Future<Result<List<Role>>> getAllRoles() {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _roles.orderBy('roleName').get();
      return snap.docs
          .map((doc) => RoleFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Future<Result<Role>> getRoleById(String roleId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _roles.doc(roleId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Role $roleId not found.',
          entityName: 'Role',
          entityId: roleId,
        );
      }
      return RoleFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
    });
  }

  @override
  Future<Result<Role>> getRoleByName(RoleName roleName) {
    return FirestoreErrorMapper.guard(() async {
      // Try deterministic ID first, then fall back to query by `roleName`.
      final doc = await _roles.doc(FirestoreParseUtils.roleDocId(roleName)).get();
      if (doc.exists && doc.data() != null) {
        return RoleFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
      }
      final query = await _roles
          .where('roleName', isEqualTo: roleName.dbValue)
          .limit(1)
          .get();
      if (query.docs.isEmpty) {
        throw NotFoundFailure(
          message: 'Role ${roleName.dbValue} not found.',
          entityName: 'Role',
          entityId: roleName.dbValue,
        );
      }
      final hit = query.docs.first;
      return RoleFirestoreDto.fromFirestore(hit.id, hit.data()).toDomain();
    });
  }

  @override
  Future<Result<List<Role>>> seedDefaultRoles() {
    return FirestoreErrorMapper.guard(() async {
      final defaults = <Role>[
        Role(
          roleId: FirestoreParseUtils.roleDocId(RoleName.owner),
          roleName: RoleName.owner,
          description:
              'Shop owner with full management and payroll approval access',
        ),
        Role(
          roleId: FirestoreParseUtils.roleDocId(RoleName.staff),
          roleName: RoleName.staff,
          description:
              'Front desk staff managing attendance, visits, and payments',
        ),
        Role(
          roleId: FirestoreParseUtils.roleDocId(RoleName.barber),
          roleName: RoleName.barber,
          description:
              'Service provider earning haircut commission (logged by staff)',
        ),
      ];

      final batch = _firestore.batch();
      for (final role in defaults) {
        final dto = RoleFirestoreDto.fromDomain(role);
        batch.set(_roles.doc(role.roleId), dto.toFirestore(), fs.SetOptions(merge: true));
      }
      await batch.commit();

      final snap = await _roles.orderBy('roleName').get();
      return snap.docs
          .map((doc) => RoleFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain())
          .toList(growable: false);
    });
  }
}
