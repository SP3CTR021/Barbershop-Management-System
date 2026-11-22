import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';

/// Backend-agnostic authentication contract bridging Supabase Auth / Firebase Auth
/// with the shop's `users` directory. Only `OWNER` and `STAFF` hold login accounts.
abstract interface class AuthRepository {
  /// Signs in an `OWNER` or `STAFF` user by email or username + password.
  Future<Result<User>> signIn({
    required String emailOrUsername,
    required String password,
  });

  Future<Result<void>> signOut();

  Future<Result<User?>> getCurrentUser();

  Stream<User?> watchAuthState();

  /// Registers a login account (`OWNER` or `STAFF` only) and creates its `users` row.
  /// Rejects [RoleName.barber] because barbers are checked in by `STAFF`.
  Future<Result<User>> registerLoginAccount({
    required RoleName roleName,
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? phone,
    String? createdByOwnerId,
  });
}
