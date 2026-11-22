import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/services/data/supabase/service_supabase_dto.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [ServiceRepository].
/// Catalog mutations enforce active `OWNER` permission per Business Rule #2.
final class SupabaseServiceRepository implements ServiceRepository {
  SupabaseServiceRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<Service>> createService({
    required String serviceName,
    required bool isHaircut,
    required double price,
    required String actingOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final cleanName = serviceName.trim();
      if (cleanName.isEmpty) {
        throw const ValidationFailure(
          message: 'Service name is required.',
          field: 'serviceName',
        );
      }
      final roundedPrice = MoneyMath.round2(price);
      if (roundedPrice < 0) {
        throw const ValidationFailure(
          message: 'Service price cannot be negative.',
          field: 'price',
        );
      }

      final inserted = await _client
          .from('services')
          .insert(<String, dynamic>{
            'service_name': cleanName,
            'is_haircut': isHaircut,
            'price': roundedPrice,
            'is_active': true,
          })
          .select()
          .single();
      return ServiceSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  @override
  Future<Result<Service>> getServiceById(String serviceId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('services')
          .select()
          .eq('service_id', serviceId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Service $serviceId not found.',
          entityName: 'Service',
          entityId: serviceId,
        );
      }
      return ServiceSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<Service>>> getServices({
    bool? isActive,
    bool? isHaircut,
  }) {
    return SupabaseErrorMapper.guard(() async {
      var query = _client.from('services').select();
      if (isActive != null) {
        query = query.eq('is_active', isActive);
      }
      if (isHaircut != null) {
        query = query.eq('is_haircut', isHaircut);
      }
      final rows = await query.order('service_name', ascending: true);
      return rows
          .map((row) => ServiceSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<Service>>> watchServices({bool? isActive}) {
    final stream = _client
        .from('services')
        .stream(primaryKey: <String>['service_id'])
        .order('service_name', ascending: true)
        .map(
          (rows) => rows
              .map((row) => ServiceSupabaseDto.fromSupabase(row).toDomain())
              .where((s) => isActive == null || s.isActive == isActive)
              .toList(growable: false),
        );
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Service>> updateService({
    required Service service,
    required String actingOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      if (service.serviceName.trim().isEmpty) {
        throw const ValidationFailure(
          message: 'Service name is required.',
          field: 'serviceName',
        );
      }
      if (service.price < 0) {
        throw const ValidationFailure(
          message: 'Service price cannot be negative.',
          field: 'price',
        );
      }

      final dto = ServiceSupabaseDto.fromDomain(service);
      final updated = await _client
          .from('services')
          .update(dto.toSupabase())
          .eq('service_id', service.serviceId)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw NotFoundFailure(
          message: 'Service ${service.serviceId} not found.',
          entityName: 'Service',
          entityId: service.serviceId,
        );
      }
      return ServiceSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<Service>> setServiceActive({
    required String serviceId,
    required bool isActive,
    required String actingOwnerId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final updated = await _client
          .from('services')
          .update(<String, dynamic>{'is_active': isActive})
          .eq('service_id', serviceId)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw NotFoundFailure(
          message: 'Service $serviceId not found.',
          entityName: 'Service',
          entityId: serviceId,
        );
      }
      return ServiceSupabaseDto.fromSupabase(updated).toDomain();
    });
  }
}
