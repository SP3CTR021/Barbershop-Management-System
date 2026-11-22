import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/data/firestore/user_firestore_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Cloud Firestore implementation of [UserRepository].
///
/// Firestore workarounds implemented here:
/// - `_unique_constraints/username_*` & `email_*` lock docs checked inside
///   `runTransaction` emulate relational `UNIQUE` constraints.
/// - Denormalized `roleName` on `users/{userId}` enables 1-read Security Rules.
/// - Updates to a barber user atomically sync denormalized user fields on the
///   paired `barbers/{barberId}` document.
final class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._firestore);

  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _roles =>
      _firestore.collection('roles');
  fs.CollectionReference<Map<String, dynamic>> get _barbers =>
      _firestore.collection('barbers');
  fs.CollectionReference<Map<String, dynamic>> get _locks =>
      _firestore.collection(FirestoreParseUtils.uniqueConstraintsCollection);

  @override
  Future<Result<User>> getUserById(String userId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _users.doc(userId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'User $userId not found.',
          entityName: 'User',
          entityId: userId,
        );
      }
      return UserFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
    });
  }

  @override
  Future<Result<User>> getUserByUsername(String username) {
    return FirestoreErrorMapper.guard(() async {
      final clean = username.trim();
      final snap = await _users
          .where('usernameLower', isEqualTo: clean.toLowerCase())
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        throw NotFoundFailure(
          message: 'User "$clean" not found.',
          entityName: 'User',
          entityId: clean,
        );
      }
      final doc = snap.docs.first;
      return UserFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain();
    });
  }

  @override
  Future<Result<List<User>>> getUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    return FirestoreErrorMapper.guard(() async {
      fs.Query<Map<String, dynamic>> query = _users;
      if (roleFilter != null) {
        query = query.where('roleName', isEqualTo: roleFilter.dbValue);
      }
      if (isActive != null) {
        query = query.where('isActive', isEqualTo: isActive);
      }
      final snap = await query.orderBy('lastName').get();
      final list = snap.docs
          .map((doc) => UserFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain())
          .toList(growable: false);
      list.sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
      return list;
    });
  }

  @override
  Stream<Result<List<User>>> watchUsers({
    RoleName? roleFilter,
    bool? isActive,
  }) {
    fs.Query<Map<String, dynamic>> query = _users;
    if (roleFilter != null) {
      query = query.where('roleName', isEqualTo: roleFilter.dbValue);
    }
    if (isActive != null) {
      query = query.where('isActive', isEqualTo: isActive);
    }
    final stream = query.orderBy('lastName').snapshots().map((snap) {
      final list = snap.docs
          .map((doc) => UserFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain())
          .toList(growable: false);
      list.sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
      return list;
    });
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<User>> createUser(User user) {
    return FirestoreErrorMapper.guard(() async {
      final cleanUsername = user.username.trim();
      final cleanEmail = FirestoreParseUtils.cleanNullableText(user.email);
      if (cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Username is required.',
          field: 'username',
        );
      }

      return _firestore.runTransaction((tx) async {
        // Strict read-before-write in Firestore transactions:
        final userRef = _users.doc(user.userId);
        final roleRef = _roles.doc(user.roleId);
        final usernameLockRef =
            _locks.doc(FirestoreParseUtils.usernameLockId(cleanUsername));
        final emailLockRef = cleanEmail == null
            ? null
            : _locks.doc(FirestoreParseUtils.emailLockId(cleanEmail));

        final existingSnap = await tx.get(userRef);
        final roleSnap = await tx.get(roleRef);
        final usernameLockSnap = await tx.get(usernameLockRef);
        final emailLockSnap =
            emailLockRef == null ? null : await tx.get(emailLockRef);

        if (existingSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'User ${user.userId} already exists.',
            field: 'userId',
            value: user.userId,
          );
        }
        if (!roleSnap.exists || roleSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Role ${user.roleId} not found.',
            entityName: 'Role',
            entityId: user.roleId,
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

        final roleName = roleSnap.data()!['roleName'] as String;
        final dto = UserFirestoreDto.fromDomain(user, roleName: roleName);

        tx.set(userRef, dto.toFirestore());
        tx.set(usernameLockRef, <String, dynamic>{
          'type': 'username',
          'ownerId': user.userId,
          'email': cleanEmail,
          'isActive': user.isActive,
        });
        if (emailLockRef != null) {
          tx.set(emailLockRef, <String, dynamic>{
            'type': 'email',
            'ownerId': user.userId,
          });
        }
        return dto.toDomain();
      });
    });
  }

  @override
  Future<Result<User>> updateUser(User user) {
    return FirestoreErrorMapper.guard(() async {
      final cleanUsername = user.username.trim();
      final cleanEmail = FirestoreParseUtils.cleanNullableText(user.email);
      if (cleanUsername.isEmpty) {
        throw const ValidationFailure(
          message: 'Username is required.',
          field: 'username',
        );
      }

      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        final userRef = _users.doc(user.userId);
        final roleRef = _roles.doc(user.roleId);
        final barberLockRef =
            _locks.doc(FirestoreParseUtils.barberUserLockId(user.userId));

        final existingSnap = await tx.get(userRef);
        final roleSnap = await tx.get(roleRef);
        final barberLockSnap = await tx.get(barberLockRef);

        if (!existingSnap.exists || existingSnap.data() == null) {
          throw NotFoundFailure(
            message: 'User ${user.userId} not found.',
            entityName: 'User',
            entityId: user.userId,
          );
        }
        if (!roleSnap.exists || roleSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Role ${user.roleId} not found.',
            entityName: 'Role',
            entityId: user.roleId,
          );
        }

        final previous =
            UserFirestoreDto.fromFirestore(existingSnap.id, existingSnap.data()!)
                .toDomain();

        final oldUsernameLockId =
            FirestoreParseUtils.usernameLockId(previous.username);
        final newUsernameLockId =
            FirestoreParseUtils.usernameLockId(cleanUsername);
        final usernameChanged = oldUsernameLockId != newUsernameLockId;

        final oldEmail = FirestoreParseUtils.cleanNullableText(previous.email);
        final oldEmailLockId =
            oldEmail == null ? null : FirestoreParseUtils.emailLockId(oldEmail);
        final newEmailLockId = cleanEmail == null
            ? null
            : FirestoreParseUtils.emailLockId(cleanEmail);
        final emailChanged = oldEmailLockId != newEmailLockId;

        final newUsernameLockSnap = usernameChanged
            ? await tx.get(_locks.doc(newUsernameLockId))
            : null;
        final newEmailLockSnap = (emailChanged && newEmailLockId != null)
            ? await tx.get(_locks.doc(newEmailLockId))
            : null;

        fs.DocumentReference<Map<String, dynamic>>? barberRef;
        fs.DocumentSnapshot<Map<String, dynamic>>? barberSnap;
        if (barberLockSnap.exists && barberLockSnap.data() != null) {
          final barberId = barberLockSnap.data()!['barberId'] as String?;
          if (barberId != null) {
            barberRef = _barbers.doc(barberId);
            barberSnap = await tx.get(barberRef);
          }
        }

        // 2. Validation checks:
        if (newUsernameLockSnap != null && newUsernameLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Username "$cleanUsername" is already taken.',
            field: 'username',
            value: cleanUsername,
          );
        }
        if (newEmailLockSnap != null && newEmailLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Email "$cleanEmail" is already registered.',
            field: 'email',
            value: cleanEmail,
          );
        }

        // 3. Writes:
        final roleName = roleSnap.data()!['roleName'] as String;
        final now = DateTime.now().toUtc();
        final updatedUser = user.copyWith(
          username: cleanUsername,
          email: cleanEmail,
          updatedAt: now,
        );
        final dto =
            UserFirestoreDto.fromDomain(updatedUser, roleName: roleName);

        tx.set(userRef, dto.toFirestore());

        if (usernameChanged) {
          tx.delete(_locks.doc(oldUsernameLockId));
        }
        tx.set(_locks.doc(newUsernameLockId), <String, dynamic>{
          'type': 'username',
          'ownerId': user.userId,
          'email': cleanEmail,
          'isActive': updatedUser.isActive,
        });

        if (emailChanged) {
          if (oldEmailLockId != null) {
            tx.delete(_locks.doc(oldEmailLockId));
          }
          if (newEmailLockId != null) {
            tx.set(_locks.doc(newEmailLockId), <String, dynamic>{
              'type': 'email',
              'ownerId': user.userId,
            });
          }
        }

        // Keep denormalized user fields on paired `barbers/{barberId}` in sync.
        if (barberRef != null && barberSnap != null && barberSnap.exists) {
          tx.update(barberRef, <String, dynamic>{
            'firstName': updatedUser.firstName.trim(),
            'lastName': updatedUser.lastName.trim(),
            'fullName': updatedUser.fullName,
            'username': cleanUsername,
            'phone': FirestoreParseUtils.cleanNullableText(updatedUser.phone),
            'email': cleanEmail,
            'userIsActive': updatedUser.isActive,
            'userUpdatedAt': fs.Timestamp.fromDate(now),
          });
        }

        return updatedUser;
      });
    });
  }

  @override
  Future<Result<User>> setUserActiveStatus({
    required String userId,
    required bool isActive,
    required String actingUserId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingUserId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final userRef = _users.doc(userId);
        final userSnap = await tx.get(userRef);
        if (!userSnap.exists || userSnap.data() == null) {
          throw NotFoundFailure(
            message: 'User $userId not found.',
            entityName: 'User',
            entityId: userId,
          );
        }

        final current =
            UserFirestoreDto.fromFirestore(userSnap.id, userSnap.data()!)
                .toDomain();
        final usernameLockRef = _locks.doc(
          FirestoreParseUtils.usernameLockId(current.username),
        );
        final usernameLockSnap = await tx.get(usernameLockRef);

        final barberLockSnap = await tx.get(
          _locks.doc(FirestoreParseUtils.barberUserLockId(userId)),
        );
        fs.DocumentReference<Map<String, dynamic>>? barberRef;
        fs.DocumentSnapshot<Map<String, dynamic>>? barberSnap;
        if (barberLockSnap.exists && barberLockSnap.data() != null) {
          final barberId = barberLockSnap.data()!['barberId'] as String?;
          if (barberId != null) {
            barberRef = _barbers.doc(barberId);
            barberSnap = await tx.get(barberRef);
          }
        }

        // 2. Writes:
        final now = DateTime.now().toUtc();
        tx.update(userRef, <String, dynamic>{
          'isActive': isActive,
          'updatedAt': fs.Timestamp.fromDate(now),
        });
        if (usernameLockSnap.exists) {
          tx.update(usernameLockRef, <String, dynamic>{'isActive': isActive});
        }
        if (barberRef != null && barberSnap != null && barberSnap.exists) {
          tx.update(barberRef, <String, dynamic>{
            'userIsActive': isActive,
            'status': isActive
                ? BarberStatus.active.dbValue
                : BarberStatus.inactive.dbValue,
            'userUpdatedAt': fs.Timestamp.fromDate(now),
          });
        }

        return current.copyWith(isActive: isActive, updatedAt: now);
      });
    });
  }
}
