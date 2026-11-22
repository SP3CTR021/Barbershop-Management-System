import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';

/// Firestore DTO mapping `services/{serviceId}` documents to domain [Service].
final class ServiceFirestoreDto {
  const ServiceFirestoreDto({
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required this.price,
    required this.isActive,
  });

  factory ServiceFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return ServiceFirestoreDto(
      serviceId: (data['serviceId'] as String?) ?? id,
      serviceName: data['serviceName'] as String,
      isHaircut: data['isHaircut'] as bool,
      price: FirestoreParseUtils.parseDecimal(data['price']),
      isActive: data['isActive'] as bool,
    );
  }

  factory ServiceFirestoreDto.fromDomain(Service service) {
    return ServiceFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    final cleanName = serviceName.trim();
    return <String, dynamic>{
      'serviceId': serviceId,
      'serviceName': cleanName,
      'serviceNameLower': cleanName.toLowerCase(),
      'isHaircut': isHaircut,
      'price': MoneyMath.round2(price),
      'isActive': isActive,
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
