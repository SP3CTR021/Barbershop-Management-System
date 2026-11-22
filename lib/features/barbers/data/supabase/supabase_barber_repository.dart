import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/data/supabase/barber_supabase_dto.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [BarberRepository] using relational JOINs on
/// `barbers` + `users` and atomic RPCs for dual-table mutations.
final class SupabaseBarberRepository implements BarberRepository {
  SupabaseBarberRepository(this._client);

  final sb.SupabaseClient _client;

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
    return SupabaseErrorMapper.guard(() async {
      final barberId = await _client.rpc(
        'rpc_create_barber_with_profile',
        params: <String, dynamic>{
          'p_first_name': firstName.trim(),
          'p_last_name': lastName.trim(),
          'p_username': username.trim(),
          'p_phone': SupabaseParseUtils.cleanNullableText(phone),
          'p_email': SupabaseParseUtils.cleanNullableText(email),
          'p_hire_date': ShopDateUtils.formatIsoDate(hireDate),
          'p_specialty': SupabaseParseUtils.cleanNullableText(specialty),
          'p_acting_owner_id': actingOwnerId,
        },
      );
      return _fetchBarberWithUserOrThrow(barberId as String);
    });
  }

  @override
  Future<Result<Barber>> getBarberById(String barberId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('barbers')
          .select()
          .eq('barber_id', barberId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      return BarberSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<Barber?>> getBarberByUserId(String userId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('barbers')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null) return null;
      return BarberSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<BarberWithUser>> getBarberWithUser(String barberId) {
    return SupabaseErrorMapper.guard(
      () => _fetchBarberWithUserOrThrow(barberId),
    );
  }

  @override
  Future<Result<List<BarberWithUser>>> getBarbers({BarberStatus? status}) {
    return SupabaseErrorMapper.guard(() => _fetchBarbers(status: status));
  }

  @override
  Stream<Result<List<BarberWithUser>>> watchBarbers({BarberStatus? status}) {
    final stream = _client
        .from('barbers')
        .stream(primaryKey: <String>['barber_id'])
        .asyncMap((_) => _fetchBarbers(status: status));
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Barber>> updateBarber({
    required Barber barber,
    required String actingOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final dto = BarberSupabaseDto.fromDomain(barber);
      final payload = dto.toSupabase()
        ..remove('barber_id')
        ..remove('user_id');

      final updated = await _client
          .from('barbers')
          .update(payload)
          .eq('barber_id', barber.barberId)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw NotFoundFailure(
          message: 'Barber ${barber.barberId} not found.',
          entityName: 'Barber',
          entityId: barber.barberId,
        );
      }
      return BarberSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<Barber>> setBarberStatus({
    required String barberId,
    required BarberStatus status,
    required String actingOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await _client.rpc(
        'rpc_set_barber_status',
        params: <String, dynamic>{
          'p_barber_id': barberId,
          'p_status': status.dbValue,
          'p_acting_owner_id': actingOwnerId,
        },
      );
      final row = await _client
          .from('barbers')
          .select()
          .eq('barber_id', barberId)
          .single();
      return BarberSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  Future<BarberWithUser> _fetchBarberWithUserOrThrow(String barberId) async {
    final row = await _client
        .from('barbers')
        .select('*, users!inner(*)')
        .eq('barber_id', barberId)
        .maybeSingle();
    if (row == null) {
      throw NotFoundFailure(
        message: 'Barber $barberId not found.',
        entityName: 'Barber',
        entityId: barberId,
      );
    }
    return BarberSupabaseDto.toBarberWithUser(row);
  }

  Future<List<BarberWithUser>> _fetchBarbers({BarberStatus? status}) async {
    var query = _client.from('barbers').select('*, users!inner(*)');
    if (status != null) {
      query = query.eq('status', status.dbValue);
    }
    final rows = await query.order('hire_date', ascending: true);
    final list = rows
        .map(BarberSupabaseDto.toBarberWithUser)
        .toList(growable: false);
    list.sort((a, b) => a.fullName.compareTo(b.fullName));
    return list;
  }
}
