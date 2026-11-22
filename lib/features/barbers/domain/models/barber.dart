import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';

const Object _unset = Object();

/// Domain model for `barbers`.
///
/// Relationships:
/// - `users` (1) -> `barbers` (0..1) via unique FK [userId].
/// - `barbers` (1) -> `attendance` (M), `transactions` (M), `payroll_records` (M).
final class Barber {
  Barber({
    required this.barberId,
    required this.userId,
    required DateTime hireDate,
    this.specialty,
    required this.status,
  }) : hireDate = ShopDateUtils.normalizeDate(hireDate);

  final String barberId;

  /// Unique 1:1 FK -> `users.user_id`.
  final String userId;

  /// Normalized shop-local date (UTC midnight).
  final DateTime hireDate;

  final String? specialty;
  final BarberStatus status;

  Barber copyWith({
    String? barberId,
    String? userId,
    DateTime? hireDate,
    Object? specialty = _unset,
    BarberStatus? status,
  }) {
    return Barber(
      barberId: barberId ?? this.barberId,
      userId: userId ?? this.userId,
      hireDate: hireDate ?? this.hireDate,
      specialty:
          identical(specialty, _unset) ? this.specialty : specialty as String?,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Barber &&
            other.barberId == barberId &&
            other.userId == userId &&
            other.hireDate == hireDate &&
            other.specialty == specialty &&
            other.status == status;
  }

  @override
  int get hashCode =>
      Object.hash(barberId, userId, hireDate, specialty, status);

  @override
  String toString() =>
      'Barber(barberId: $barberId, userId: $userId, status: ${status.dbValue})';
}
