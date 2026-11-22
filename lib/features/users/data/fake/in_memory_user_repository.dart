import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';

/// In-memory fake implementation of [UserRepository].
final class InMemoryUserRepository implements UserRepository {
  InMemoryUserRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<User>> getUserById(String userId) {
    return _db.guard(() {
      final user = _db.users[userId];
      if (user == null) {
        throw NotFoundFailure(
          message: 'User $userId not found.',
          entityName: 'User',
          entityId: userId,
        );
      }
      return user;
    });
  }

  @override
  Future<Result<User>> getUserByUsername(String username) {
    return _db.guard(() {
      final lower = username.trim().toLowerCase();
      for (final user in _db.users.values) {
        if (user.username.toLowerCase() == lower) return user;
      }
      throw NotFoundFailure(
        message: 'User "$username" not found.',
        entityName: 'User',
        entityId: username,
      );
    });
  }

  @override
  Future<Result<List<User>>> getUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    return _db.guard(() => _filterUsers(roleFilter: roleFilter, isActive: isActive));
  }

  @override
  Stream<Result<List<User>>> watchUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    return _db.watchQuery(
      () => _filterUsers(roleFilter: roleFilter, isActive: isActive),
    );
  }

  @override
  Future<Result<User>> createUser(User user) {
    return _db.guard(() {
      final cleanUsername = user.username.trim();
      final cleanEmail = _cleanNullable(user.email);
      if (cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Username is required.',
          field: 'username',
        );
      }
      if (_db.users.containsKey(user.userId)) {
        throw DuplicateEntryFailure(
          message: 'User ${user.userId} already exists.',
          field: 'userId',
          value: user.userId,
        );
      }
      if (!_db.roles.containsKey(user.roleId)) {
        throw NotFoundFailure(
          message: 'Role ${user.roleId} not found.',
          entityName: 'Role',
          entityId: user.roleId,
        );
      }
      _assertUniqueUsernameAndEmail(
        username: cleanUsername,
        email: cleanEmail,
      );

      final created = user.copyWith(
        username: cleanUsername,
        email: cleanEmail,
      );
      _db.users[created.userId] = created;
      _db.notifyChanged();
      return created;
    });
  }

  @override
  Future<Result<User>> updateUser(User user) {
    return _db.guard(() {
      final existing = _db.users[user.userId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'User ${user.userId} not found.',
          entityName: 'User',
          entityId: user.userId,
        );
      }
      if (!_db.roles.containsKey(user.roleId)) {
        throw NotFoundFailure(
          message: 'Role ${user.roleId} not found.',
          entityName: 'Role',
          entityId: user.roleId,
        );
      }
      final cleanUsername = user.username.trim();
      final cleanEmail = _cleanNullable(user.email);
      if (cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Username is required.',
          field: 'username',
        );
      }
      _assertUniqueUsernameAndEmail(
        username: cleanUsername,
        email: cleanEmail,
        excludingUserId: user.userId,
      );

      final updated = user.copyWith(
        username: cleanUsername,
        email: cleanEmail,
        updatedAt: DateTime.now().toUtc(),
      );
      _db.users[updated.userId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }

  @override
  Future<Result<User>> setUserActiveStatus({
    required String userId,
    required bool isActive,
    required String actingUserId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existing = _db.users[userId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'User $userId not found.',
          entityName: 'User',
          entityId: userId,
        );
      }

      final updated = existing.copyWith(
        isActive: isActive,
        updatedAt: DateTime.now().toUtc(),
      );
      _db.users[userId] = updated;

      // Keep any paired `barbers` profile synchronized.
      for (final entry in _db.barbers.entries.toList(growable: false)) {
        if (entry.value.userId == userId) {
          _db.barbers[entry.key] = entry.value.copyWith(
            status: isActive ? BarberStatus.active : BarberStatus.inactive,
          );
        }
      }

      _db.notifyChanged();
      return updated;
    });
  }

  List<User> _filterUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    final list = _db.users.values.where((user) {
      if (roleFilter != null) {
        final role = _db.roles[user.roleId];
        if (role == null || role.roleName != roleFilter) return false;
      }
      if (isActive != null && user.isActive != isActive) {
        return false;
      }
      return true;
    }).toList(growable: false)
      ..sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
    return list;
  }

  void _assertUniqueUsernameAndEmail({
    required String username,
    required String? email,
    String? excludingUserId,
  }) {
    final usernameLower = username.toLowerCase();
    final emailLower = email?.toLowerCase();
    for (final other in _db.users.values) {
      if (other.userId == excludingUserId) continue;
      if (other.username.toLowerCase() == usernameLower) {
        throw DuplicateEntryFailure(
          message: 'Username "$username" is already taken.',
          field: 'username',
          value: username,
        );
      }
      if (emailLower != null && other.email?.toLowerCase() == emailLower) {
        throw DuplicateEntryFailure(
          message: 'Email "$email" is already registered.',
          field: 'email',
          value: email,
        );
      }
    }
  }

  String? _cleanNullable(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
