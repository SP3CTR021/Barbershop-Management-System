import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';

/// Backend-agnostic contract for managing `barbers` and their 1:1 `users` rows.
abstract interface class BarberRepository {
  /// Atomically creates a `User` (`BARBER` role, no login credentials required)
  /// and its 1:1 `Barber` profile. Restricted to `OWNER`.
  Future<Result<BarberWithUser>> createBarberWithProfile({
    required String firstName,
    required String lastName,
    required String username,
    String? phone,
    String? email,
    required DateTime hireDate,
    String? specialty,
    required String actingOwnerId,
  });

  Future<Result<Barber>> getBarberById(String barberId);

  Future<Result<Barber?>> getBarberByUserId(String userId);

  Future<Result<BarberWithUser>> getBarberWithUser(String barberId);

  Future<Result<List<BarberWithUser>>> getBarbers({
    BarberStatus? status,
  });

  Stream<Result<List<BarberWithUser>>> watchBarbers({
    BarberStatus? status,
  });

  Future<Result<Barber>> updateBarber({
    required Barber barber,
    required String actingOwnerId,
  });

  /// Soft-updates `barbers.status` and keeps the paired `users.is_active` flag
  /// synchronized (Business Rule #7). Restricted to `OWNER`.
  Future<Result<Barber>> setBarberStatus({
    required String barberId,
    required BarberStatus status,
    required String actingOwnerId,
  });
}
