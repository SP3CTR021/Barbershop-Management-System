import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/users/data/supabase/user_supabase_dto.dart';

/// Supabase DTO mapping `public.barbers` and nested `users!inner(*)` joins.
final class BarberSupabaseDto {
  const BarberSupabaseDto({
    required this.barberId,
    required this.userId,
    required this.hireDate,
    this.specialty,
    required this.status,
  });

  factory BarberSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return BarberSupabaseDto(
      barberId: map['barber_id'] as String,
      userId: map['user_id'] as String,
      hireDate: SupabaseParseUtils.parseDate(map['hire_date']),
      specialty: map['specialty'] as String?,
      status: map['status'] as String,
    );
  }

  factory BarberSupabaseDto.fromDomain(Barber barber) {
    return BarberSupabaseDto(
      barberId: barber.barberId,
      userId: barber.userId,
      hireDate: barber.hireDate,
      specialty: barber.specialty,
      status: barber.status.dbValue,
    );
  }

  /// Hydrates a [BarberWithUser] from `barbers` joined with `users!inner(*)`.
  static BarberWithUser toBarberWithUser(Map<String, dynamic> map) {
    final barber = BarberSupabaseDto.fromSupabase(map).toDomain();
    final userMap = map['users'] as Map<String, dynamic>;
    final user = UserSupabaseDto.fromSupabase(userMap).toDomain();
    return BarberWithUser(barber: barber, user: user);
  }

  final String barberId;
  final String userId;
  final DateTime hireDate;
  final String? specialty;
  final String status;

  Map<String, dynamic> toSupabase() {
    return <String, dynamic>{
      'barber_id': barberId,
      'user_id': userId,
      'hire_date': ShopDateUtils.formatIsoDate(hireDate),
      'specialty': SupabaseParseUtils.cleanNullableText(specialty),
      'status': status,
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
}
