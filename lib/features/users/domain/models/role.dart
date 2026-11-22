import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

const Object _unset = Object();

/// Domain model for `roles` (`role_id`, `role_name`, `description`).
/// Relationship: `roles` (1) -> `users` (M) via `users.role_id`.
final class Role {
  const Role({
    required this.roleId,
    required this.roleName,
    this.description,
  });

  /// String UUID (Supabase) or Firestore document ID (`roles.role_id`).
  final String roleId;
  final RoleName roleName;
  final String? description;

  Role copyWith({
    String? roleId,
    RoleName? roleName,
    Object? description = _unset,
  }) {
    return Role(
      roleId: roleId ?? this.roleId,
      roleName: roleName ?? this.roleName,
      description:
          identical(description, _unset) ? this.description : description as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Role &&
            other.roleId == roleId &&
            other.roleName == roleName &&
            other.description == description;
  }

  @override
  int get hashCode => Object.hash(roleId, roleName, description);

  @override
  String toString() =>
      'Role(roleId: $roleId, roleName: ${roleName.dbValue}, description: $description)';
}
