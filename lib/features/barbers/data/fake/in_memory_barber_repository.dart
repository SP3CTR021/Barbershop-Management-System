import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';

/// In-memory fake implementation of [BarberRepository].
final class InMemoryBarberRepository implements BarberRepository {
  InMemoryBarberRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<BarberWithUser>> createBarberWithProfile({
    required String firstName,
    required String lastName,
    required String username,
    String? phone,
    String? email,
    required DateTime hireDate,
    String? specialty,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final cleanFirst = firstName.trim();
      final cleanLast = lastName.trim();
      final cleanUsername = username.trim();
      final cleanEmail = _cleanNullable(email);
      if (cleanFirst.isEmpty || cleanLast.isEmpty || cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Barber first name, last name, and username are required.',
        );
      }

      Role? barberRole;
      for (final role in _db.roles.values) {
        if (role.roleName == RoleName.barber) {
          barberRole = role;
          break;
        }
      }
      if (barberRole == null) {
        throw const NotFoundFailure(
          message: 'BARBER role is not seeded.',
          entityName: 'Role',
          entityId: 'BARBER',
        );
      }

      final lowerUsername = cleanUsername.toLowerCase();
      final lowerEmail = cleanEmail?.toLowerCase();
      for (final existing in _db.users.values) {
        if (existing.username.toLowerCase() == lowerUsername) {
          throw DuplicateEntryFailure(
            message: 'Username "$cleanUsername" is already taken.',
            field: 'username',
            value: cleanUsername,
          );
        }
        if (lowerEmail != null && existing.email?.toLowerCase() == lowerEmail) {
          throw DuplicateEntryFailure(
            message: 'Email "$cleanEmail" is already registered.',
            field: 'email',
            value: cleanEmail,
          );
        }
      }

      final now = DateTime.now().toUtc();
      final user = User(
        userId: _db.nextId(),
        roleId: barberRole.roleId,
        firstName: cleanFirst,
        lastName: cleanLast,
        username: cleanUsername,
        phone: _cleanNullable(phone),
        email: cleanEmail,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      final barber = Barber(
        barberId: _db.nextId(),
        userId: user.userId,
        hireDate: ShopDateUtils.normalizeDate(hireDate),
        specialty: _cleanNullable(specialty),
        status: BarberStatus.active,
      );

      _db.users[user.userId] = user;
      _db.barbers[barber.barberId] = barber;
      _db.notifyChanged();
      return BarberWithUser(barber: barber, user: user);
    });
  }

  @override
  Future<Result<Barber>> getBarberById(String barberId) {
    return _db.guard(() {
      final barber = _db.barbers[barberId];
      if (barber == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      return barber;
    });
  }

  @override
  Future<Result<Barber?>> getBarberByUserId(String userId) {
    return _db.guard(() {
      for (final barber in _db.barbers.values) {
        if (barber.userId == userId) return barber;
      }
      return null;
    });
  }

  @override
  Future<Result<BarberWithUser>> getBarberWithUser(String barberId) {
    return _db.guard(() {
      final barber = _db.barbers[barberId];
      if (barber == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      final user = _db.users[barber.userId];
      if (user == null) {
        throw NotFoundFailure(
          message: 'User ${barber.userId} not found.',
          entityName: 'User',
          entityId: barber.userId,
        );
      }
      return BarberWithUser(barber: barber, user: user);
    });
  }

  @override
  Future<Result<List<BarberWithUser>>> getBarbers({BarberStatus? status}) {
    return _db.guard(() => _listBarbers(status: status));
  }

  @override
  Stream<Result<List<BarberWithUser>>> watchBarbers({BarberStatus? status}) {
    return _db.watchQuery(() => _listBarbers(status: status));
  }

  @override
  Future<Result<Barber>> updateBarber({
    required Barber barber,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );
      if (!_db.barbers.containsKey(barber.barberId)) {
        throw NotFoundFailure(
          message: 'Barber ${barber.barberId} not found.',
          entityName: 'Barber',
          entityId: barber.barberId,
        );
      }
      _db.barbers[barber.barberId] = barber;
      _db.notifyChanged();
      return barber;
    });
  }

  @override
  Future<Result<Barber>> setBarberStatus({
    required String barberId,
    required BarberStatus status,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existing = _db.barbers[barberId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }

      final updated = existing.copyWith(status: status);
      _db.barbers[barberId] = updated;

      final linkedUser = _db.users[existing.userId];
      if (linkedUser != null) {
        _db.users[linkedUser.userId] = linkedUser.copyWith(
          isActive: status == BarberStatus.active,
          updatedAt: DateTime.now().toUtc(),
        );
      }

      _db.notifyChanged();
      return updated;
    });
  }

  List<BarberWithUser> _listBarbers({BarberStatus? status}) {
    final results = <BarberWithUser>[];
    for (final barber in _db.barbers.values) {
      if (status != null && barber.status != status) continue;
      final user = _db.users[barber.userId];
      if (user != null) {
        results.add(BarberWithUser(barber: barber, user: user));
      }
    }
    results.sort((a, b) => a.fullName.compareTo(b.fullName));
    return results;
  }

  String? _cleanNullable(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
