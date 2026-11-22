import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// Firestore DTO mapping `roles/{roleId}` documents to domain [Role].
final class RoleFirestoreDto {
  const RoleFirestoreDto({
    required this.roleId,
    required this.roleName,
    this.description,
  });

  factory RoleFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return RoleFirestoreDto(
      roleId: (data['roleId'] as String?) ?? id,
      roleName: data['roleName'] as String,
      description: data['description'] as String?,
    );
  }

  factory RoleFirestoreDto.fromDomain(Role role) {
    return RoleFirestoreDto(
      roleId: role.roleId,
      roleName: role.roleName.dbValue,
      description: role.description,
    );
  }

  final String roleId;
  final String roleName;
  final String? description;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'roleId': roleId,
      'roleName': roleName,
      'description': description,
    };
  }

  Role toDomain() {
    return Role(
      roleId: roleId,
      roleName: RoleName.fromDbValue(roleName),
      description: description,
    );
  }
}
