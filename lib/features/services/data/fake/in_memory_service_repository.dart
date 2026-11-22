import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// In-memory fake implementation of [ServiceRepository].
final class InMemoryServiceRepository implements ServiceRepository {
  InMemoryServiceRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<Service>> createService({
    required String serviceName,
    required bool isHaircut,
    required double price,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
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

      _assertUniqueServiceName(cleanName);

      final service = Service(
        serviceId: _db.nextId(),
        serviceName: cleanName,
        isHaircut: isHaircut,
        price: roundedPrice,
        isActive: true,
      );
      _db.services[service.serviceId] = service;
      _db.notifyChanged();
      return service;
    });
  }

  @override
  Future<Result<Service>> getServiceById(String serviceId) {
    return _db.guard(() {
      final service = _db.services[serviceId];
      if (service == null) {
        throw NotFoundFailure(
          message: 'Service $serviceId not found.',
          entityName: 'Service',
          entityId: serviceId,
        );
      }
      return service;
    });
  }

  @override
  Future<Result<List<Service>>> getServices({
    bool? isActive,
    bool? isHaircut,
  }) {
    return _db.guard(
      () => _listServices(isActive: isActive, isHaircut: isHaircut),
    );
  }

  @override
  Stream<Result<List<Service>>> watchServices({bool? isActive}) {
    return _db.watchQuery(() => _listServices(isActive: isActive));
  }

  @override
  Future<Result<Service>> updateService({
    required Service service,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      if (!_db.services.containsKey(service.serviceId)) {
        throw NotFoundFailure(
          message: 'Service ${service.serviceId} not found.',
          entityName: 'Service',
          entityId: service.serviceId,
        );
      }
      final cleanName = service.serviceName.trim();
      if (cleanName.isEmpty) {
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

      _assertUniqueServiceName(cleanName, excludingServiceId: service.serviceId);

      final updated = service.copyWith(serviceName: cleanName);
      _db.services[updated.serviceId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }

  @override
  Future<Result<Service>> setServiceActive({
    required String serviceId,
    required bool isActive,
    required String actingOwnerId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingOwnerId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existing = _db.services[serviceId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Service $serviceId not found.',
          entityName: 'Service',
          entityId: serviceId,
        );
      }
      final updated = existing.copyWith(isActive: isActive);
      _db.services[serviceId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }

  List<Service> _listServices({
    bool? isActive,
    bool? isHaircut,
  }) {
    final list = _db.services.values.where((service) {
      if (isActive != null && service.isActive != isActive) return false;
      if (isHaircut != null && service.isHaircut != isHaircut) return false;
      return true;
    }).toList(growable: false)
      ..sort((a, b) => a.serviceName.compareTo(b.serviceName));
    return list;
  }

  void _assertUniqueServiceName(
    String name, {
    String? excludingServiceId,
  }) {
    final lower = name.toLowerCase();
    for (final other in _db.services.values) {
      if (other.serviceId == excludingServiceId) continue;
      if (other.serviceName.toLowerCase() == lower) {
        throw DuplicateEntryFailure(
          message: 'Service "$name" already exists.',
          field: 'serviceName',
          value: name,
        );
      }
    }
  }
}
