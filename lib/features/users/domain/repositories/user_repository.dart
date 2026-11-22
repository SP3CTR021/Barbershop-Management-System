import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';

/// Backend-agnostic repository for `users` profile records.
abstract interface class UserRepository {
  Future<Result<User>> getUserById(String userId);

  Future<Result<User>> getUserByUsername(String username);

  Future<Result<List<User>>> getUsers({
    RoleName? roleFilter,
    bool? isActive,
  });

  Stream<Result<List<User>>> watchUsers({
    RoleName? roleFilter,
    bool? isActive,
  });

  Future<Result<User>> createUser(User user);

  Future<Result<User>> updateUser(User user);

  /// Soft-activates or soft-deactivates a user (OWNER-only per Business Rule #7).
  /// When the user has a linked `barbers` profile, implementations keep
  /// `barbers.status` synchronized in the same unit of work.
  Future<Result<User>> setUserActiveStatus({
    required String userId,
    required bool isActive,
    required String actingUserId,
  });
}
