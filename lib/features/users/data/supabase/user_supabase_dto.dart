import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';

/// Supabase DTO mapping `public.users` snake_case columns to domain [User].
final class UserSupabaseDto {
  const UserSupabaseDto({
    required this.userId,
    required this.roleId,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.phone,
    this.email,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return UserSupabaseDto(
      userId: map['user_id'] as String,
      roleId: map['role_id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      username: map['username'] as String,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      isActive: map['is_active'] as bool,
      createdAt: SupabaseParseUtils.parseTimestamp(map['created_at']),
      updatedAt: SupabaseParseUtils.parseTimestamp(map['updated_at']),
    );
  }

  factory UserSupabaseDto.fromDomain(User user) {
    return UserSupabaseDto(
      userId: user.userId,
      roleId: user.roleId,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      phone: user.phone,
      email: user.email,
      isActive: user.isActive,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    );
  }

  final String userId;
  final String roleId;
  final String firstName;
  final String lastName;
  final String username;
  final String? phone;
  final String? email;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toSupabase({bool includeTimestamps = false}) {
    return <String, dynamic>{
      'user_id': userId,
      'role_id': roleId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'username': username.trim(),
      'phone': SupabaseParseUtils.cleanNullableText(phone),
      'email': SupabaseParseUtils.cleanNullableText(email),
      'is_active': isActive,
      if (includeTimestamps) 'created_at': createdAt.toUtc().toIso8601String(),
      if (includeTimestamps) 'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  User toDomain() {
    return User(
      userId: userId,
      roleId: roleId,
      firstName: firstName,
      lastName: lastName,
      username: username,
      phone: phone,
      email: email,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
