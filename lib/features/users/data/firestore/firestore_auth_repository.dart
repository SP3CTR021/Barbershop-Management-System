import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/users/data/firestore/user_firestore_dto.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fa;

/// Firebase Auth + Firestore implementation of [AuthRepository].
/// Only `OWNER` and `STAFF` hold login credentials; `BARBER` users cannot sign in.
final class FirestoreAuthRepository implements AuthRepository {
  FirestoreAuthRepository(this._auth, this._firestore);

  final fa.FirebaseAuth _auth;
  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  fs.CollectionReference<Map<String, dynamic>> get _roles =>
      _firestore.collection('roles');
  fs.CollectionReference<Map<String, dynamic>> get _locks =>
      _firestore.collection(FirestoreParseUtils.uniqueConstraintsCollection);

  @override
  Future<Result<User>> signIn({
    required String emailOrUsername,
    required String password,
  }) {
    return FirestoreErrorMapper.guard(() async {
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
        // Resolve username -> email via `_unique_constraints/username_*` lock doc.
        final lockDoc = await _locks
            .doc(FirestoreParseUtils.usernameLockId(identifier))
            .get();
        final data = lockDoc.data();
        final resolvedEmail = data?['email'] as String?;
        final isActive = data?['isActive'] as bool? ?? true;
        if (!lockDoc.exists ||
            resolvedEmail == null ||
            resolvedEmail.isEmpty ||
            !isActive) {
          throw const UnauthenticatedFailure(
            message: 'Invalid username/email or password.',
          );
        }
        emailToUse = resolvedEmail;
      }

      final cred = await _auth.signInWithEmailAndPassword(
        email: emailToUse,
        password: password,
      );
      final fbUser = cred.user;
      if (fbUser == null) {
        throw const UnauthenticatedFailure(message: 'Authentication failed.');
      }

      final profile = await _loadAuthorizedProfile(fbUser.uid);
      if (profile == null) {
        await _auth.signOut();
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
    return FirestoreErrorMapper.guard(() => _auth.signOut());
  }

  @override
  Future<Result<User?>> getCurrentUser() {
    return FirestoreErrorMapper.guard(() async {
      final fbUser = _auth.currentUser;
      if (fbUser == null) return null;
      return _loadAuthorizedProfile(fbUser.uid);
    });
  }

  @override
  Stream<User?> watchAuthState() {
    return _auth.authStateChanges().asyncMap((fbUser) async {
      if (fbUser == null) return null;
      try {
        return await _loadAuthorizedProfile(fbUser.uid);
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
    return FirestoreErrorMapper.guard(() async {
      if (roleName == RoleName.barber) {
        throw const ValidationFailure(
          message:
              'Barbers do not have login accounts. Use BarberRepository.createBarberWithProfile.',
          field: 'roleName',
        );
      }

      if (createdByOwnerId != null) {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
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

      final roleId = FirestoreParseUtils.roleDocId(roleName);
      final roleSnap = await _roles.doc(roleId).get();
      if (!roleSnap.exists) {
        throw NotFoundFailure(
          message: 'Role ${roleName.dbValue} is not seeded.',
          entityName: 'Role',
          entityId: roleName.dbValue,
        );
      }

      // Check locks before creating Firebase Auth credentials to avoid orphans.
      final usernameLockRef =
          _locks.doc(FirestoreParseUtils.usernameLockId(cleanUsername));
      final emailLockRef =
          _locks.doc(FirestoreParseUtils.emailLockId(cleanEmail));
      if ((await usernameLockRef.get()).exists) {
        throw DuplicateEntryFailure(
          message: 'Username "$cleanUsername" is already taken.',
          field: 'username',
          value: cleanUsername,
        );
      }
      if ((await emailLockRef.get()).exists) {
        throw DuplicateEntryFailure(
          message: 'Email "$cleanEmail" is already registered.',
          field: 'email',
          value: cleanEmail,
        );
      }

      // Note: On client SDKs, `createUserWithEmailAndPassword` signs into the
      // newly created user. In production Owner->Staff provisioning, invoke this
      // from a secondary FirebaseApp instance or Cloud Function.
      final credential = await _auth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );
      final fbUser = credential.user;
      if (fbUser == null) {
        throw const UnknownFailure(
          message: 'Firebase Auth did not return a created user.',
        );
      }

      try {
        return await _firestore.runTransaction((tx) async {
          final userRef = _users.doc(fbUser.uid);
          final bootstrapRef =
              _locks.doc(FirestoreParseUtils.bootstrapOwnerLockId);

          final uLockSnap = await tx.get(usernameLockRef);
          final eLockSnap = await tx.get(emailLockRef);
          final bootstrapSnap = await tx.get(bootstrapRef);

          if (uLockSnap.exists) {
            throw DuplicateEntryFailure(
              message: 'Username "$cleanUsername" is already taken.',
              field: 'username',
              value: cleanUsername,
            );
          }
          if (eLockSnap.exists) {
            throw DuplicateEntryFailure(
              message: 'Email "$cleanEmail" is already registered.',
              field: 'email',
              value: cleanEmail,
            );
          }

          final now = DateTime.now().toUtc();
          final domainUser = User(
            userId: fbUser.uid,
            roleId: roleId,
            firstName: firstName.trim(),
            lastName: lastName.trim(),
            username: cleanUsername,
            phone: FirestoreParseUtils.cleanNullableText(phone),
            email: cleanEmail,
            isActive: true,
            createdAt: now,
            updatedAt: now,
          );
          final dto =
              UserFirestoreDto.fromDomain(domainUser, roleName: roleName.dbValue);

          tx.set(userRef, dto.toFirestore());
          tx.set(usernameLockRef, <String, dynamic>{
            'type': 'username',
            'ownerId': fbUser.uid,
            'email': cleanEmail,
            'isActive': true,
          });
          tx.set(emailLockRef, <String, dynamic>{
            'type': 'email',
            'ownerId': fbUser.uid,
          });
          if (roleName == RoleName.owner && !bootstrapSnap.exists) {
            tx.set(bootstrapRef, <String, dynamic>{'ownerId': fbUser.uid});
          }

          return domainUser;
        });
      } catch (error) {
        // Best-effort cleanup of the newly created Auth record if Firestore failed.
        try {
          await fbUser.delete();
        } catch (_) {}
        rethrow;
      }
    });
  }

  Future<User?> _loadAuthorizedProfile(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = doc.data()!;
    final user = UserFirestoreDto.fromFirestore(doc.id, data).toDomain();
    final roleRaw = data['roleName'] as String?;
    RoleName roleName;
    if (roleRaw != null && roleRaw.isNotEmpty) {
      roleName = RoleName.fromDbValue(roleRaw);
    } else {
      final roleDoc = await _roles.doc(user.roleId).get();
      if (!roleDoc.exists || roleDoc.data() == null) return null;
      roleName = RoleName.fromDbValue(roleDoc.data()!['roleName'] as String);
    }

    if (!user.isActive || roleName == RoleName.barber) {
      return null;
    }
    return user;
  }
}
