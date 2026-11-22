import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';

/// In-memory fake implementation of [AuthRepository].
final class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<User>> signIn({
    required String emailOrUsername,
    required String password,
  }) {
    return _db.guard(() {
      final identifier = emailOrUsername.trim();
      if (identifier.isEmpty || password.isEmpty) {
        throw const ValidationFailure(
          message: 'Username/email and password are required.',
        );
      }

      String? emailLower;
      if (identifier.contains('@')) {
        emailLower = identifier.toLowerCase();
      } else {
        final lowerUsername = identifier.toLowerCase();
        for (final user in _db.users.values) {
          if (user.username.toLowerCase() == lowerUsername) {
            emailLower = user.email?.toLowerCase();
            break;
          }
        }
      }

      if (emailLower == null) {
        throw const UnauthenticatedFailure(
          message: 'Invalid username/email or password.',
        );
      }

      final storedPassword = _db.authPasswordsByEmailLower[emailLower];
      final userId = _db.authUserIdByEmailLower[emailLower];
      if (storedPassword == null ||
          userId == null ||
          storedPassword != password) {
        throw const UnauthenticatedFailure(
          message: 'Invalid username/email or password.',
        );
      }

      final profile = _authorizedProfile(userId);
      if (profile == null) {
        throw const PermissionDeniedFailure(
          message:
              'Account is inactive or not authorized for front-desk/owner login.',
        );
      }

      _db.currentAuthenticatedUserId = userId;
      _db.notifyChanged();
      return profile;
    });
  }

  @override
  Future<Result<void>> signOut() {
    return _db.guard(() {
      _db.currentAuthenticatedUserId = null;
      _db.notifyChanged();
    });
  }

  @override
  Future<Result<User?>> getCurrentUser() {
    return _db.guard(() {
      final uid = _db.currentAuthenticatedUserId;
      if (uid == null) return null;
      return _authorizedProfile(uid);
    });
  }

  @override
  Stream<User?> watchAuthState() {
    return _db.watchAuth(() {
      final uid = _db.currentAuthenticatedUserId;
      if (uid == null) return null;
      return _authorizedProfile(uid);
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
    return _db.guard(() {
      if (roleName == RoleName.barber) {
        throw const ValidationFailure(
          message:
              'Barbers do not have login accounts. Use BarberRepository.createBarberWithProfile.',
          field: 'roleName',
        );
      }

      if (createdByOwnerId != null) {
        _db.assertActiveUserRole(
          actingUserId: createdByOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
        );
      }

      final cleanUsername = username.trim();
      final cleanEmail = email.trim();
      if (cleanUsername.isEmpty || cleanEmail.isEmpty) {
        throw const ValidationFailure(
          message: 'Username and email are required for login accounts.',
        );
      }

      Role? role;
      for (final candidate in _db.roles.values) {
        if (candidate.roleName == roleName) {
          role = candidate;
          break;
        }
      }
      if (role == null) {
        throw NotFoundFailure(
          message: 'Role ${roleName.dbValue} is not seeded.',
          entityName: 'Role',
          entityId: roleName.dbValue,
        );
      }

      final lowerUsername = cleanUsername.toLowerCase();
      final lowerEmail = cleanEmail.toLowerCase();
      for (final existing in _db.users.values) {
        if (existing.username.toLowerCase() == lowerUsername) {
          throw DuplicateEntryFailure(
            message: 'Username "$cleanUsername" is already taken.',
            field: 'username',
            value: cleanUsername,
          );
        }
        if (existing.email?.toLowerCase() == lowerEmail) {
          throw DuplicateEntryFailure(
            message: 'Email "$cleanEmail" is already registered.',
            field: 'email',
            value: cleanEmail,
          );
        }
      }

      final now = DateTime.now().toUtc();
      final userId = _db.nextId();
      final cleanPhone = phone?.trim();
      final user = User(
        userId: userId,
        roleId: role.roleId,
        firstName: firstName.trim(),
        lastName: lastName.trim(),
        username: cleanUsername,
        phone: (cleanPhone == null || cleanPhone.isEmpty) ? null : cleanPhone,
        email: cleanEmail,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      _db.users[userId] = user;
      _db.authPasswordsByEmailLower[lowerEmail] = password;
      _db.authUserIdByEmailLower[lowerEmail] = userId;
      _db.currentAuthenticatedUserId = userId;
      _db.notifyChanged();
      return user;
    });
  }

  User? _authorizedProfile(String userId) {
    final user = _db.users[userId];
    if (user == null || !user.isActive) return null;
    final role = _db.roles[user.roleId];
    if (role == null || role.roleName == RoleName.barber) return null;
    return user;
  }
}
