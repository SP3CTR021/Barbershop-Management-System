import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/features/services/data/firestore/service_firestore_dto.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [ServiceRepository].
/// Enforces `OWNER`-only catalog mutations and case-insensitive `serviceName`
/// uniqueness via `_unique_constraints/service_name_*` lock documents.
final class FirestoreServiceRepository implements ServiceRepository {
  FirestoreServiceRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _services =>
      _firestore.collection('services');
  fs.CollectionReference<Map<String, dynamic>> get _locks =>
      _firestore.collection(FirestoreParseUtils.uniqueConstraintsCollection);

  @override
  Future<Result<Service>> createService({
    required String serviceName,
    required bool isHaircut,
    required double price,
    required String actingOwnerId,
  }) {
    return FirestoreErrorMapper.guard(() async {
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

      final serviceId = _uuid.v4();
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final nameLockRef =
            _locks.doc(FirestoreParseUtils.serviceNameLockId(cleanName));
        final nameLockSnap = await tx.get(nameLockRef);
        if (nameLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Service "$cleanName" already exists.',
            field: 'serviceName',
            value: cleanName,
          );
        }

        final service = Service(
          serviceId: serviceId,
          serviceName: cleanName,
          isHaircut: isHaircut,
          price: roundedPrice,
          isActive: true,
        );
        final dto = ServiceFirestoreDto.fromDomain(service);

        tx.set(_services.doc(serviceId), dto.toFirestore());
        tx.set(nameLockRef, <String, dynamic>{
          'type': 'service_name',
          'serviceId': serviceId,
        });
        return service;
      });
    });
  }

  @override
  Future<Result<Service>> getServiceById(String serviceId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _services.doc(serviceId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Service $serviceId not found.',
          entityName: 'Service',
          entityId: serviceId,
        );
      }
      return ServiceFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
    });
  }

  @override
  Future<Result<List<Service>>> getServices({
    bool? isActive,
    bool? isHaircut,
  }) {
    return FirestoreErrorMapper.guard(() async {
      fs.Query<Map<String, dynamic>> query = _services;
      if (isActive != null) {
        query = query.where('isActive', isEqualTo: isActive);
      }
      if (isHaircut != null) {
        query = query.where('isHaircut', isEqualTo: isHaircut);
      }
      final snap = await query.get();
      final list = snap.docs
          .map(
            (doc) =>
                ServiceFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
      list.sort((a, b) => a.serviceName.compareTo(b.serviceName));
      return list;
    });
  }

  @override
  Stream<Result<List<Service>>> watchServices({bool? isActive}) {
    fs.Query<Map<String, dynamic>> query = _services;
    if (isActive != null) {
      query = query.where('isActive', isEqualTo: isActive);
    }
    final stream = query.snapshots().map((snap) {
      final list = snap.docs
          .map(
            (doc) =>
                ServiceFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
      list.sort((a, b) => a.serviceName.compareTo(b.serviceName));
      return list;
    });
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Service>> updateService({
    required Service service,
    required String actingOwnerId,
  }) {
    return FirestoreErrorMapper.guard(() async {
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

      return _firestore.runTransaction((tx) async {
        // 1. Reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final serviceRef = _services.doc(service.serviceId);
        final existingSnap = await tx.get(serviceRef);
        if (!existingSnap.exists || existingSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Service ${service.serviceId} not found.',
            entityName: 'Service',
            entityId: service.serviceId,
          );
        }

        final existing =
            ServiceFirestoreDto.fromFirestore(existingSnap.id, existingSnap.data()!)
                .toDomain();
        final oldLockId =
            FirestoreParseUtils.serviceNameLockId(existing.serviceName);
        final newLockId = FirestoreParseUtils.serviceNameLockId(cleanName);
        final nameChanged = oldLockId != newLockId;

        final newLockSnap =
            nameChanged ? await tx.get(_locks.doc(newLockId)) : null;
        if (newLockSnap != null && newLockSnap.exists) {
          throw DuplicateEntryFailure(
            message: 'Service "$cleanName" already exists.',
            field: 'serviceName',
            value: cleanName,
          );
        }

        // 2. Writes:
        final updated = service.copyWith(serviceName: cleanName);
        final dto = ServiceFirestoreDto.fromDomain(updated);
        tx.set(serviceRef, dto.toFirestore());
        if (nameChanged) {
          tx.delete(_locks.doc(oldLockId));
          tx.set(_locks.doc(newLockId), <String, dynamic>{
            'type': 'service_name',
            'serviceId': updated.serviceId,
          });
        }
        return updated;
      });
    });
  }

  @override
  Future<Result<Service>> setServiceActive({
    required String serviceId,
    required bool isActive,
    required String actingOwnerId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final serviceRef = _services.doc(serviceId);
        final snap = await tx.get(serviceRef);
        if (!snap.exists || snap.data() == null) {
          throw NotFoundFailure(
            message: 'Service $serviceId not found.',
            entityName: 'Service',
            entityId: serviceId,
          );
        }
        final existing =
            ServiceFirestoreDto.fromFirestore(snap.id, snap.data()!).toDomain();
        tx.update(serviceRef, <String, dynamic>{'isActive': isActive});
        return existing.copyWith(isActive: isActive);
      });
    });
  }
}
