import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/data/supabase/user_supabase_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [UserRepository].
final class SupabaseUserRepository implements UserRepository {
  SupabaseUserRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<User>> getUserById(String userId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'User $userId not found.',
          entityName: 'User',
          entityId: userId,
        );
      }
      return UserSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<User>> getUserByUsername(String username) {
    return SupabaseErrorMapper.guard(() async {
      final normalized = username.trim();
      final row = await _client
          .from('users')
          .select()
          .ilike('username', normalized)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'User "$normalized" not found.',
          entityName: 'User',
          entityId: normalized,
        );
      }
      return UserSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<User>>> getUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    return SupabaseErrorMapper.guard(() async {
      var query = _client.from('users').select('*, roles!inner(role_name)');
      if (roleFilter != null) {
        query = query.eq('roles.role_name', roleFilter.dbValue);
      }
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }
      final rows = await query
          .order('last_name', ascending: true)
          .order('first_name', ascending: true);
      return rows
          .map((row) => UserSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<User>>> watchUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    final stream = _client
        .from('users')
        .stream(primaryKey: <String>['user_id'])
        .order('last_name', ascending: true)
        .asyncMap((rows) async {
          String? roleIdFilter;
          if (roleFilter != null) {
            final roleRow = await _client
                .from('roles')
                .select('role_id')
                .eq('role_name', roleFilter.dbValue)
                .maybeSingle();
            roleIdFilter = roleRow?['role_id'] as String?;
            if (roleIdFilter == null) return <User>[];
          }
          return rows
              .map((row) => UserSupabaseDto.fromSupabase(row).toDomain())
              .where((user) {
                if (roleIdFilter != null && user.roleId != roleIdFilter) {
                  return false;
                }
                if (isActive != null && user.isActive != isActive) {
                  return false;
                }
                return true;
              })
              .toList(growable: false);
        });

    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<User>> createUser(User user) {
    return SupabaseErrorMapper.guard(() async {
      final dto = UserSupabaseDto.fromDomain(user);
      final inserted = await _client
          .from('users')
          .insert(dto.toSupabase())
          .select()
          .single();
      return UserSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  @override
  Future<Result<User>> updateUser(User user) {
    return SupabaseErrorMapper.guard(() async {
      final dto = UserSupabaseDto.fromDomain(user);
      final payload = dto.toSupabase()
        ..remove('user_id')
        ..remove('created_at')
        ..remove('updated_at');
      final updated = await _client
          .from('users')
          .update(payload)
          .eq('user_id', user.userId)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw NotFoundFailure(
          message: 'User ${user.userId} not found.',
          entityName: 'User',
          entityId: user.userId,
        );
      }
      return UserSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<User>> setUserActiveStatus({
    required String userId,
    required bool isActive,
    required String actingUserId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      // Uses atomic RPC so any linked `barbers.status` updates in the same txn.
      await _client.rpc(
        'rpc_set_user_active_status',
        params: <String, dynamic>{
          'p_user_id': userId,
          'p_is_active': isActive,
          'p_acting_user_id': actingUserId,
        },
      );
      final row = await _client
          .from('users')
          .select()
          .eq('user_id', userId)
          .single();
      return UserSupabaseDto.fromSupabase(row).toDomain();
    });
  }
}
