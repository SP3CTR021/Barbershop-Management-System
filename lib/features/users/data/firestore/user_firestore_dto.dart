import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping `users/{userId}` documents to domain [User].
///
/// Denormalized fields kept strictly in Firestore DTO:
/// - [roleName]: copied from `roles/{roleId}` so Firestore Security Rules
///   evaluate `OWNER`/`STAFF` permissions in a single `get()`.
/// - `usernameLower`: supports case-insensitive username queries.
final class UserFirestoreDto {
  const UserFirestoreDto({
    required this.userId,
    required this.roleId,
    this.roleName,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.phone,
    this.email,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return UserFirestoreDto(
      userId: (data['userId'] as String?) ?? id,
      roleId: data['roleId'] as String,
      roleName: data['roleName'] as String?,
      firstName: data['firstName'] as String,
      lastName: data['lastName'] as String,
      username: data['username'] as String,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      isActive: data['isActive'] as bool,
      createdAt: FirestoreParseUtils.parseTimestamp(data['createdAt']),
      updatedAt: FirestoreParseUtils.parseTimestamp(data['updatedAt']),
    );
  }

  factory UserFirestoreDto.fromDomain(User user, {String? roleName}) {
    return UserFirestoreDto(
      userId: user.userId,
      roleId: user.roleId,
      roleName: roleName,
      firstName: user.firstName,
      lastName: user.lastName,
      username: user.username,
      phone: user.phone,
      email: user.email,
      isActive: user.isActive,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    );
  }

  final String userId;
  final String roleId;

  /// Denormalized role name (`OWNER`, `STAFF`, `BARBER`) for rules & filtering.
  final String? roleName;

  final String firstName;
  final String lastName;
  final String username;
  final String? phone;
  final String? email;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toFirestore() {
    final cleanUsername = username.trim();
    return <String, dynamic>{
      'userId': userId,
      'roleId': roleId,
      if (roleName != null) 'roleName': roleName,
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'username': cleanUsername,
      'usernameLower': cleanUsername.toLowerCase(),
      'phone': FirestoreParseUtils.cleanNullableText(phone),
      'email': FirestoreParseUtils.cleanNullableText(email),
      'isActive': isActive,
      'createdAt': fs.Timestamp.fromDate(createdAt.toUtc()),
      'updatedAt': fs.Timestamp.fromDate(updatedAt.toUtc()),
    };
  }

  User toDomain() {
    return User(
      userId: userId,
      roleId: roleId,
      firstName: firstName,
      lastName: lastName,
      username: username,
      phone: phone,
      email: email,
      isActive: isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
