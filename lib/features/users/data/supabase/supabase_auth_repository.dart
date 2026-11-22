import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/data/supabase/user_supabase_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Supabase Auth implementation of [AuthRepository].
/// Only `OWNER` and `STAFF` authenticate; `BARBER` accounts have no Auth login.
final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<User>> signIn({
    required String emailOrUsername,
    required String password,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final identifier = emailOrUsername.trim();
      if (identifier.isEmpty || password.isEmpty) {
        throw const ValidationFailure(
          message: 'Username/email and password are required.',
        );
      }

      String emailToUse;
      if (identifier.contains('@')) {
        emailToUse = identifier;
      } else {
        final resolved = await _client.rpc(
          'resolve_login_email_by_username',
          params: <String, dynamic>{'p_username': identifier},
        );
        if (resolved is! String || resolved.trim().isEmpty) {
          throw const UnauthenticatedFailure(
            message: 'Invalid username/email or password.',
          );
        }
        emailToUse = resolved.trim();
      }

      final response = await _client.auth.signInWithPassword(
        email: emailToUse,
        password: password,
      );
      final authUser = response.user;
      if (authUser == null) {
        throw const UnauthenticatedFailure(
          message: 'Authentication failed.',
        );
      }

      final profile = await _loadAuthorizedProfile(authUser.id);
      if (profile == null) {
        await _client.auth.signOut();
        throw const PermissionDeniedFailure(
          message:
              'Account is inactive or not authorized for front-desk/owner login.',
        );
      }
      return profile;
    });
  }

  @override
  Future<Result<void>> signOut() {
    return SupabaseErrorMapper.guard(() => _client.auth.signOut());
  }

  @override
  Future<Result<User?>> getCurrentUser() {
    return SupabaseErrorMapper.guard(() async {
      final authUser = _client.auth.currentUser;
      if (authUser == null) return null;
      return _loadAuthorizedProfile(authUser.id);
    });
  }

  @override
  Stream<User?> watchAuthState() {
    return _client.auth.onAuthStateChange.asyncMap((state) async {
      final authUser = state.session?.user;
      if (authUser == null) return null;
      try {
        return await _loadAuthorizedProfile(authUser.id);
      } catch (_) {
        return null;
      }
    });
  }

  @override
  Future<Result<User>> registerLoginAccount({
    required RoleName roleName,
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phone,
    String? createdByOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      if (roleName == RoleName.barber) {
        throw const ValidationFailure(
          message:
              'Barbers do not have login accounts. Use BarberRepository.createBarberWithProfile.',
          field: 'roleName',
        );
      }

      if (createdByOwnerId != null) {
        await SupabaseParseUtils.assertActiveUserRole(
          _client,
          actingUserId: createdByOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
        );
      }

      final roleRow = await _client
          .from('roles')
          .select('role_id')
          .eq('role_name', roleName.dbValue)
          .maybeSingle();
      if (roleRow == null) {
        throw NotFoundFailure(
          message: 'Role ${roleName.dbValue} is not seeded.',
          entityName: 'Role',
          entityId: roleName.dbValue,
        );
      }
      final roleId = roleRow['role_id'] as String;

      // Note: client-side `auth.signUp` creates the Auth user; when email
      // confirmations are enabled or an Owner provisions Staff without losing
      // their own session, wrap this call in a Supabase Edge Function.
      final authRes = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final authUser = authRes.user;
      if (authUser == null) {
        throw const UnknownFailure(
          message: 'Supabase Auth did not return a created user.',
        );
      }

      final inserted = await _client
          .from('users')
          .insert(<String, dynamic>{
            'user_id': authUser.id,
            'role_id': roleId,
            'first_name': firstName.trim(),
            'last_name': lastName.trim(),
            'username': username.trim(),
            'phone': SupabaseParseUtils.cleanNullableText(phone),
            'email': email.trim(),
            'is_active': true,
          })
          .select()
          .single();

      return UserSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  Future<User?> _loadAuthorizedProfile(String userId) async {
    final row = await _client
        .from('users')
        .select('*, roles!inner(role_name)')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;

    final user = UserSupabaseDto.fromSupabase(row).toDomain();
    final roleData = row['roles'] as Map<String, dynamic>;
    final roleName = RoleName.fromDbValue(roleData['role_name'] as String);
    if (!user.isActive || roleName == RoleName.barber) {
      return null;
    }
    return user;
  }
}
