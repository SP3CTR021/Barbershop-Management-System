import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/data/firestore/barber_firestore_dto.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/users/data/firestore/user_firestore_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [BarberRepository].
///
/// Firestore workarounds implemented here:
/// - Atomically creates `users/{userId}` (`BARBER`, no Auth account) and
///   `barbers/{barberId}` + `barber_user_{userId}` lock inside `runTransaction`.
/// - Stores denormalized user snapshot fields on `barbers/{barberId}` so
///   roster queries require 1 read instead of N+1 `users` lookups.
final class FirestoreBarberRepository implements BarberRepository {
  FirestoreBarberRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _barbers =>
      _firestore.collection('barbers');
  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _roles =>
      _firestore.collection('roles');
  fs.CollectionReference<Map<String, dynamic>> get _locks =>
      _firestore.collection(FirestoreParseUtils.uniqueConstraintsCollection);

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
    return FirestoreErrorMapper.guard(() async {
      final cleanFirst = firstName.trim();
      final cleanLast = lastName.trim();
      final cleanUsername = username.trim();
      final cleanEmail = FirestoreParseUtils.cleanNullableText(email);

      if (cleanFirst.isEmpty || cleanLast.isEmpty || cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Barber first name, last name, and username are required.',
        );
      }

      final userId = _uuid.v4();
      final barberId = _uuid.v4();
      final barberRoleId = FirestoreParseUtils.roleDocId(RoleName.barber);

      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final roleSnap = await tx.get(_roles.doc(barberRoleId));
        final usernameLockRef =
            _locks.doc(FirestoreParseUtils.usernameLockId(cleanUsername));
        final usernameLockSnap = await tx.get(usernameLockRef);
        final emailLockRef = cleanEmail == null
            ? null
            : _locks.doc(FirestoreParseUtils.emailLockId(cleanEmail));
        final emailLockSnap =
            emailLockRef == null ? null : await tx.get(emailLockRef);

        if (!roleSnap.exists) {
          throw const NotFoundFailure(
            message: 'BARBER role is not seeded.',
            entityName: 'Role',
            entityId: 'BARBER',
          );
        }
        if (usernameLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Username "$cleanUsername" is already taken.',
            field: 'username',
            value: cleanUsername,
          );
        }
        if (emailLockSnap != null && emailLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Email "$cleanEmail" is already registered.',
            field: 'email',
            value: cleanEmail,
          );
        }

        // 2. Writes:
        final now = DateTime.now().toUtc();
        final user = User(
          userId: userId,
          roleId: barberRoleId,
          firstName: cleanFirst,
          lastName: cleanLast,
          username: cleanUsername,
          phone: FirestoreParseUtils.cleanNullableText(phone),
          email: cleanEmail,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        );
        final barber = Barber(
          barberId: barberId,
          userId: userId,
          hireDate: ShopDateUtils.normalizeDate(hireDate),
          specialty: FirestoreParseUtils.cleanNullableText(specialty),
          status: BarberStatus.active,
        );

        final userDto = UserFirestoreDto.fromDomain(
          user,
          roleName: RoleName.barber.dbValue,
        );
        final barberDto = BarberFirestoreDto.fromDomain(barber, user: user);

        tx.set(_users.doc(userId), userDto.toFirestore());
        tx.set(_barbers.doc(barberId), barberDto.toFirestore());
        tx.set(usernameLockRef, <String, dynamic>{
          'type': 'username',
          'ownerId': userId,
          'email': cleanEmail,
          'isActive': true,
        });
        if (emailLockRef != null) {
          tx.set(emailLockRef, <String, dynamic>{
            'type': 'email',
            'ownerId': userId,
          });
        }
        tx.set(
          _locks.doc(FirestoreParseUtils.barberUserLockId(userId)),
          <String, dynamic>{'barberId': barberId, 'userId': userId},
        );

        return BarberWithUser(barber: barber, user: user);
      });
    });
  }

  @override
  Future<Result<Barber>> getBarberById(String barberId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _barbers.doc(barberId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      return BarberFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
    });
  }

  @override
  Future<Result<Barber?>> getBarberByUserId(String userId) {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _barbers
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final doc = snap.docs.first;
      return BarberFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain();
    });
  }

  @override
  Future<Result<BarberWithUser>> getBarberWithUser(String barberId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _barbers.doc(barberId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      return _hydrateBarberWithUser(doc.id, doc.data()!);
    });
  }

  @override
  Future<Result<List<BarberWithUser>>> getBarbers({BarberStatus? status}) {
    return FirestoreErrorMapper.guard(() async {
      fs.Query<Map<String, dynamic>> query = _barbers;
      if (status != null) {
        query = query.where('status', isEqualTo: status.dbValue);
      }
      final snap = await query.get();
      final results = <BarberWithUser>[];
      for (final doc in snap.docs) {
        results.add(await _hydrateBarberWithUser(doc.id, doc.data()));
      }
      results.sort((a, b) => a.fullName.compareTo(b.fullName));
      return results;
    });
  }

  @override
  Stream<Result<List<BarberWithUser>>> watchBarbers({BarberStatus? status}) {
    fs.Query<Map<String, dynamic>> query = _barbers;
    if (status != null) {
      query = query.where('status', isEqualTo: status.dbValue);
    }
    final stream = query.snapshots().asyncMap((snap) async {
      final results = <BarberWithUser>[];
      for (final doc in snap.docs) {
        results.add(await _hydrateBarberWithUser(doc.id, doc.data()));
      }
      results.sort((a, b) => a.fullName.compareTo(b.fullName));
      return results;
    });
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Barber>> updateBarber({
    required Barber barber,
    required String actingOwnerId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final barberRef = _barbers.doc(barber.barberId);
        final snap = await tx.get(barberRef);
        if (!snap.exists) {
          throw NotFoundFailure(
            message: 'Barber ${barber.barberId} not found.',
            entityName: 'Barber',
            entityId: barber.barberId,
          );
        }

        tx.update(barberRef, <String, dynamic>{
          'hireDate': ShopDateUtils.formatIsoDate(barber.hireDate),
          'specialty': FirestoreParseUtils.cleanNullableText(barber.specialty),
          'status': barber.status.dbValue,
        });
        return barber;
      });
    });
  }

  @override
  Future<Result<Barber>> setBarberStatus({
    required String barberId,
    required BarberStatus status,
    required String actingOwnerId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final barberRef = _barbers.doc(barberId);
        final barberSnap = await tx.get(barberRef);
        if (!barberSnap.exists || barberSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Barber $barberId not found.',
            entityName: 'Barber',
            entityId: barberId,
          );
        }

        final existing =
            BarberFirestoreDto.fromFirestore(barberSnap.id, barberSnap.data()!)
                .toDomain();
        final userRef = _users.doc(existing.userId);
        final userSnap = await tx.get(userRef);

        final isActive = status == BarberStatus.active;
        final now = DateTime.now().toUtc();

        tx.update(barberRef, <String, dynamic>{
          'status': status.dbValue,
          'userIsActive': isActive,
          'userUpdatedAt': fs.Timestamp.fromDate(now),
        });

        if (userSnap.exists) {
          tx.update(userRef, <String, dynamic>{
            'isActive': isActive,
            'updatedAt': fs.Timestamp.fromDate(now),
          });
        }

        return existing.copyWith(status: status);
      });
    });
  }

  Future<BarberWithUser> _hydrateBarberWithUser(
    String id,
    Map<String, dynamic> data,
  ) async {
    final dto = BarberFirestoreDto.fromFirestore(id, data);
    if (dto.hasDenormalizedUser) {
      return dto.toBarberWithUser();
    }
    final userDoc = await _users.doc(dto.userId).get();
    if (!userDoc.exists || userDoc.data() == null) {
      throw NotFoundFailure(
        message: 'Linked user ${dto.userId} for barber $id not found.',
        entityName: 'User',
        entityId: dto.userId,
      );
    }
    return BarberWithUser(
      barber: dto.toDomain(),
      user: UserFirestoreDto.fromFirestore(userDoc.id, userDoc.data()!).toDomain(),
    );
  }
}
