import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/data/supabase/role_supabase_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [RoleRepository] using PostgREST on `roles`.
final class SupabaseRoleRepository implements RoleRepository {
  SupabaseRoleRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<List<Role>>> getAllRoles() {
    return SupabaseErrorMapper.guard(() async {
      final rows = await _client
          .from('roles')
          .select()
          .order('role_name', ascending: true);
      return rows
          .map((row) => RoleSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Future<Result<Role>> getRoleById(String roleId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('roles')
          .select()
          .eq('role_id', roleId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Role $roleId not found.',
          entityName: 'Role',
          entityId: roleId,
        );
      }
      return RoleSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<Role>> getRoleByName(RoleName roleName) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('roles')
          .select()
          .eq('role_name', roleName.dbValue)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Role ${roleName.dbValue} not found.',
          entityName: 'Role',
          entityId: roleName.dbValue,
        );
      }
      return RoleSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<Role>>> seedDefaultRoles() {
    return SupabaseErrorMapper.guard(() async {
      await _client.from('roles').upsert(
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'role_name': 'OWNER',
            'description':
                'Shop owner with full management and payroll approval access',
          },
          <String, dynamic>{
            'role_name': 'STAFF',
            'description':
                'Front desk staff managing attendance, visits, and payments',
          },
          <String, dynamic>{
            'role_name': 'BARBER',
            'description':
                'Service provider earning haircut commission (logged by staff)',
          },
        ],
        onConflict: 'role_name',
        ignoreDuplicates: true,
      );
      final rows = await _client
          .from('roles')
          .select()
          .order('role_name', ascending: true);
      return rows
          .map((row) => RoleSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }
}
