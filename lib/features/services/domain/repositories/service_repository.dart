import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';

/// Backend-agnostic contract for `services` catalog management.
/// Mutations (create, price/flag updates, soft-deactivation) require `OWNER`.
abstract interface class ServiceRepository {
  Future<Result<Service>> createService({
    required String serviceName,
    required bool isHaircut,
    required double price,
    required String actingOwnerId,
  });

  Future<Result<Service>> getServiceById(String serviceId);

  Future<Result<List<Service>>> getServices({
    bool? isActive,
    bool? isHaircut,
  });

  Stream<Result<List<Service>>> watchServices({bool? isActive});

  Future<Result<Service>> updateService({
    required Service service,
    required String actingOwnerId,
  });

  Future<Result<Service>> setServiceActive({
    required String serviceId,
    required bool isActive,
    required String actingOwnerId,
  });
}
