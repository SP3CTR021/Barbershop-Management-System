import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping `barbers/{barberId}` documents to [Barber] and [BarberWithUser].
///
/// Denormalized user fields (`firstName`, `lastName`, `username`, `phone`,
/// `email`, `userIsActive`, `roleId`, `userCreatedAt`, `userUpdatedAt`) are
/// stored alongside barber columns so roster lists avoid N+1 `users` reads.
final class BarberFirestoreDto {
  const BarberFirestoreDto({
    required this.barberId,
    required this.userId,
    required this.hireDate,
    this.specialty,
    required this.status,
    this.roleId,
    this.firstName,
    this.lastName,
    this.username,
    this.phone,
    this.email,
    this.userIsActive,
    this.userCreatedAt,
    this.userUpdatedAt,
  });

  factory BarberFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return BarberFirestoreDto(
      barberId: (data['barberId'] as String?) ?? id,
      userId: data['userId'] as String,
      hireDate: FirestoreParseUtils.parseDate(data['hireDate']),
      specialty: data['specialty'] as String?,
      status: data['status'] as String,
      roleId: data['roleId'] as String?,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      username: data['username'] as String?,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      userIsActive: data['userIsActive'] as bool?,
      userCreatedAt:
          FirestoreParseUtils.parseNullableTimestamp(data['userCreatedAt']),
      userUpdatedAt:
          FirestoreParseUtils.parseNullableTimestamp(data['userUpdatedAt']),
    );
  }

  factory BarberFirestoreDto.fromDomain(
    Barber barber, {
    User? user,
  }) {
    return BarberFirestoreDto(
      barberId: barber.barberId,
      userId: barber.userId,
      hireDate: barber.hireDate,
      specialty: barber.specialty,
      status: barber.status.dbValue,
      roleId: user?.roleId,
      firstName: user?.firstName,
      lastName: user?.lastName,
      username: user?.username,
      phone: user?.phone,
      email: user?.email,
      userIsActive: user?.isActive,
      userCreatedAt: user?.createdAt,
      userUpdatedAt: user?.updatedAt,
    );
  }

  final String barberId;
  final String userId;
  final DateTime hireDate;
  final String? specialty;
  final String status;

  // Denormalized User fields for 0-extra-read roster queries:
  final String? roleId;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? phone;
  final String? email;
  final bool? userIsActive;
  final DateTime? userCreatedAt;
  final DateTime? userUpdatedAt;

  bool get hasDenormalizedUser =>
      firstName != null &&
      lastName != null &&
      username != null &&
      userIsActive != null &&
      userCreatedAt != null &&
      userUpdatedAt != null;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'barberId': barberId,
      'userId': userId,
      'hireDate': ShopDateUtils.formatIsoDate(hireDate),
      'specialty': FirestoreParseUtils.cleanNullableText(specialty),
      'status': status,
      if (roleId != null) 'roleId': roleId,
      if (firstName != null) 'firstName': firstName!.trim(),
      if (lastName != null) 'lastName': lastName!.trim(),
      if (firstName != null && lastName != null)
        'fullName': '${firstName!.trim()} ${lastName!.trim()}'.trim(),
      if (username != null) 'username': username!.trim(),
      if (phone != null) 'phone': FirestoreParseUtils.cleanNullableText(phone),
      if (email != null) 'email': FirestoreParseUtils.cleanNullableText(email),
      if (userIsActive != null) 'userIsActive': userIsActive,
      if (userCreatedAt != null)
        'userCreatedAt': fs.Timestamp.fromDate(userCreatedAt!.toUtc()),
      if (userUpdatedAt != null)
        'userUpdatedAt': fs.Timestamp.fromDate(userUpdatedAt!.toUtc()),
    };
  }

  Barber toDomain() {
    return Barber(
      barberId: barberId,
      userId: userId,
      hireDate: hireDate,
      specialty: specialty,
      status: BarberStatus.fromDbValue(status),
    );
  }

  BarberWithUser toBarberWithUser() {
    final barber = toDomain();
    final user = User(
      userId: userId,
      roleId: roleId ?? FirestoreParseUtils.roleDocId(RoleName.barber),
      firstName: firstName!,
      lastName: lastName!,
      username: username!,
      phone: phone,
      email: email,
      isActive: userIsActive!,
      createdAt: userCreatedAt!,
      updatedAt: userUpdatedAt!,
    );
    return BarberWithUser(barber: barber, user: user);
  }
}
