import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';

/// Composite domain view joining a `Barber` profile with its 1:1 `User` row.
/// Keeps `Barber` and `User` normalized in the domain layer regardless of
/// whether the backend fetches via SQL JOIN or denormalized Firestore DTO.
final class BarberWithUser {
  const BarberWithUser({
    required this.barber,
    required this.user,
  });

  final Barber barber;
  final User user;

  String get barberId => barber.barberId;

  String get fullName => user.fullName;

  /// Only barbers active on both `barbers.status` and `users.is_active` may be
  /// checked in or assigned to transactions.
  bool get isAssignable =>
      barber.status == BarberStatus.active && user.isActive;

  BarberWithUser copyWith({
    Barber? barber,
    User? user,
  }) {
    return BarberWithUser(
      barber: barber ?? this.barber,
      user: user ?? this.user,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BarberWithUser && other.barber == barber && other.user == user;
  }

  @override
  int get hashCode => Object.hash(barber, user);

  @override
  String toString() =>
      'BarberWithUser(barberId: $barberId, fullName: $fullName, isAssignable: $isAssignable)';
}
