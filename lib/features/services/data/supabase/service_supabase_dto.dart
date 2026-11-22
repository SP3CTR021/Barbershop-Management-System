import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';

/// Supabase DTO mapping `public.services` snake_case rows to domain [Service].
final class ServiceSupabaseDto {
  const ServiceSupabaseDto({
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required this.price,
    required this.isActive,
  });

  factory ServiceSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return ServiceSupabaseDto(
      serviceId: map['service_id'] as String,
      serviceName: map['service_name'] as String,
      isHaircut: map['is_haircut'] as bool,
      price: SupabaseParseUtils.parseDecimal(map['price']),
      isActive: map['is_active'] as bool,
    );
  }

  factory ServiceSupabaseDto.fromDomain(Service service) {
    return ServiceSupabaseDto(
      serviceId: service.serviceId,
      serviceName: service.serviceName,
      isHaircut: service.isHaircut,
      price: service.price,
      isActive: service.isActive,
    );
  }

  final String serviceId;
  final String serviceName;
  final bool isHaircut;
  final double price;
  final bool isActive;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'service_id': serviceId,
      'service_name': serviceName.trim(),
      'is_haircut': isHaircut,
      'price': MoneyMath.round2(price),
      'is_active': isActive,
    };
  }

  Service toDomain() {
    return Service(
      serviceId: serviceId,
      serviceName: serviceName,
      isHaircut: isHaircut,
      price: price,
      isActive: isActive,
    );
  }
}
