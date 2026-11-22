import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/customers/data/firestore/customer_firestore_dto.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [CustomerRepository].
///
/// Firestore workarounds implemented here:
/// - Client-side substring filtering in [getCustomers] (Firestore lacks `ILIKE %q%`).
/// - Chunked `WriteBatch` in [deleteCustomer] emulates SQL `ON DELETE SET NULL`
///   by clearing `customerId`/`customerName` on linked `transactions` docs.
final class FirestoreCustomerRepository implements CustomerRepository {
  FirestoreCustomerRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _customers =>
      _firestore.collection('customers');
  fs.CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');

  @override
  Future<Result<Customer>> createCustomer({
    required String firstName,
    required String lastName,
    String? phone,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final cleanFirst = firstName.trim();
      final cleanLast = lastName.trim();
      if (cleanFirst.isEmpty || cleanLast.isEmpty) {
        throw const ValidationFailure(
          message: 'Customer first and last name are required.',
        );
      }

      final customer = Customer(
        customerId: _uuid.v4(),
        firstName: cleanFirst,
        lastName: cleanLast,
        phone: FirestoreParseUtils.cleanNullableText(phone),
        createdAt: DateTime.now().toUtc(),
      );
      final dto = CustomerFirestoreDto.fromDomain(customer);
      await _customers.doc(customer.customerId).set(dto.toFirestore());
      return customer;
    });
  }

  @override
  Future<Result<Customer>> getCustomerById(String customerId) {
    return FirestoreErrorMapper.guard(() async {
      final doc = await _customers.doc(customerId).get();
      if (!doc.exists || doc.data() == null) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }
      return CustomerFirestoreDto.fromFirestore(doc.id, doc.data()!).toDomain();
    });
  }

  @override
  Future<Result<List<Customer>>> getCustomers({String? searchQuery}) {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _customers.orderBy('lastName').get();
      var list = snap.docs
          .map(
            (doc) =>
                CustomerFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);

      final needle = searchQuery?.trim().toLowerCase();
      if (needle != null && needle.isNotEmpty) {
        list = list
            .where(
              (c) =>
                  c.firstName.toLowerCase().contains(needle) ||
                  c.lastName.toLowerCase().contains(needle) ||
                  c.fullName.toLowerCase().contains(needle) ||
                  (c.phone?.toLowerCase().contains(needle) ?? false),
            )
            .toList(growable: false);
      }

      list.sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
      return list;
    });
  }

  @override
  Stream<Result<List<Customer>>> watchCustomers() {
    final stream = _customers.orderBy('lastName').snapshots().map((snap) {
      final list = snap.docs
          .map(
            (doc) =>
                CustomerFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
      list.sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
      return list;
    });
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Customer>> updateCustomer(Customer customer) {
    return FirestoreErrorMapper.guard(() async {
      final ref = _customers.doc(customer.customerId);
      final snap = await ref.get();
      if (!snap.exists) {
        throw NotFoundFailure(
          message: 'Customer ${customer.customerId} not found.',
          entityName: 'Customer',
          entityId: customer.customerId,
        );
      }
      final dto = CustomerFirestoreDto.fromDomain(customer);
      await ref.set(dto.toFirestore());
      return dto.toDomain();
    });
  }

  @override
  Future<Result<void>> deleteCustomer(String customerId) {
    return FirestoreErrorMapper.guard(() async {
      final customerRef = _customers.doc(customerId);
      final customerSnap = await customerRef.get();
      if (!customerSnap.exists) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }

      // Emulate SQL `ON DELETE SET NULL` on linked transactions via WriteBatches.
      final linkedTxs = await _transactions
          .where('customerId', isEqualTo: customerId)
          .get();

      const maxOpsPerBatch = 450;
      var batch = _firestore.batch();
      var opCount = 0;

      for (final txDoc in linkedTxs.docs) {
        batch.update(txDoc.reference, <String, dynamic>{
          'customerId': null,
          'customerName': null,
        });
        opCount++;
        if (opCount >= maxOpsPerBatch) {
          await batch.commit();
          batch = _firestore.batch();
          opCount = 0;
        }
      }

      batch.delete(customerRef);
      await batch.commit();
    });
  }
}
