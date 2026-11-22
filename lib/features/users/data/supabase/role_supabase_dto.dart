import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// Supabase DTO mapping `public.roles` snake_case rows to domain [Role].
final class RoleSupabaseDto {
  const RoleSupabaseDto({
    required this.roleId,
    required this.roleName,
    this.description,
  });

  factory RoleSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return RoleSupabaseDto(
      roleId: map['role_id'] as String,
      roleName: map['role_name'] as String,
      description: map['description'] as String?,
    );
  }

  factory RoleSupabaseDto.fromDomain(Role role) {
    return RoleSupabaseDto(
      roleId: role.roleId,
      roleName: role.roleName.dbValue,
      description: role.description,
    );
  }

  final String roleId;
  final String roleName;
  final String? description;

  Map<String, dynamic> toSupabase() {
    return <String, dynamic>{
      'role_id': roleId,
      'role_name': roleName,
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
