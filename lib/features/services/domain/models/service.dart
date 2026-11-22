import 'package:barbershop_management_app/core/utils/money_math.dart';

/// Domain model for `services`.
/// Relationship: `services` (1) -> `transaction_items` (M).
final class Service {
  Service({
    required this.serviceId,
    required this.serviceName,
    required this.isHaircut,
    required double price,
    required this.isActive,
  }) : price = MoneyMath.round2(price);

  final String serviceId;

  /// Unique service catalog name (`services.service_name`).
  final String serviceName;

  /// Flags whether sales of this service count toward barber haircut payroll.
  final bool isHaircut;

  /// Current catalog price; copied into `transaction_items.unit_price` at sale time.
  final double price;

  /// Soft-delete flag (Business Rule #7).
  final bool isActive;

  Service copyWith({
    String? serviceId,
    String? serviceName,
    bool? isHaircut,
    double? price,
    bool? isActive,
  }) {
    return Service(
      serviceId: serviceId ?? this.serviceId,
      serviceName: serviceName ?? this.serviceName,
      isHaircut: isHaircut ?? this.isHaircut,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Service &&
            other.serviceId == serviceId &&
            other.serviceName == serviceName &&
            other.isHaircut == isHaircut &&
            other.price == price &&
            other.isActive == isActive;
  }

  @override
  int get hashCode =>
      Object.hash(serviceId, serviceName, isHaircut, price, isActive);

  @override
  String toString() =>
      'Service(serviceId: $serviceId, serviceName: $serviceName, isHaircut: $isHaircut, price: $price, isActive: $isActive)';
}
