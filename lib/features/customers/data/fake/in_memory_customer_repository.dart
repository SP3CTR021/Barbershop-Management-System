import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';

/// In-memory fake implementation of [CustomerRepository].
final class InMemoryCustomerRepository implements CustomerRepository {
  InMemoryCustomerRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<Customer>> createCustomer({
    required String firstName,
    required String lastName,
    String? phone,
  }) {
    return _db.guard(() {
      final cleanFirst = firstName.trim();
      final cleanLast = lastName.trim();
      if (cleanFirst.isEmpty || cleanLast.isEmpty) {
        throw const ValidationFailure(
          message: 'Customer first and last name are required.',
        );
      }
      final cleanPhone = phone?.trim();
      final customer = Customer(
        customerId: _db.nextId(),
        firstName: cleanFirst,
        lastName: cleanLast,
        phone: (cleanPhone == null || cleanPhone.isEmpty) ? null : cleanPhone,
        createdAt: DateTime.now().toUtc(),
      );
      _db.customers[customer.customerId] = customer;
      _db.notifyChanged();
      return customer;
    });
  }

  @override
  Future<Result<Customer>> getCustomerById(String customerId) {
    return _db.guard(() {
      final customer = _db.customers[customerId];
      if (customer == null) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }
      return customer;
    });
  }

  @override
  Future<Result<List<Customer>>> getCustomers({String? searchQuery}) {
    return _db.guard(() => _listCustomers(searchQuery: searchQuery));
  }

  @override
  Stream<Result<List<Customer>>> watchCustomers() {
    return _db.watchQuery(() => _listCustomers());
  }

  @override
  Future<Result<Customer>> updateCustomer(Customer customer) {
    return _db.guard(() {
      if (!_db.customers.containsKey(customer.customerId)) {
        throw NotFoundFailure(
          message: 'Customer ${customer.customerId} not found.',
          entityName: 'Customer',
          entityId: customer.customerId,
        );
      }
      _db.customers[customer.customerId] = customer;
      _db.notifyChanged();
      return customer;
    });
  }

  @override
  Future<Result<void>> deleteCustomer(String customerId) {
    return _db.guard(() {
      final removed = _db.customers.remove(customerId);
      if (removed == null) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }

      // Emulate SQL `ON DELETE SET NULL` on linked transactions.
      for (final entry in _db.transactions.entries.toList(growable: false)) {
        if (entry.value.customerId == customerId) {
          _db.transactions[entry.key] = entry.value.copyWith(customerId: null);
        }
      }
      _db.notifyChanged();
    });
  }

  List<Customer> _listCustomers({String? searchQuery}) {
    final needle = searchQuery?.trim().toLowerCase();
    final list = _db.customers.values.where((c) {
      if (needle == null || needle.isEmpty) return true;
      return c.firstName.toLowerCase().contains(needle) ||
          c.lastName.toLowerCase().contains(needle) ||
          c.fullName.toLowerCase().contains(needle) ||
          (c.phone?.toLowerCase().contains(needle) ?? false);
    }).toList(growable: false)
      ..sort((a, b) {
        final byLast = a.lastName.compareTo(b.lastName);
        return byLast != 0 ? byLast : a.firstName.compareTo(b.firstName);
      });
    return list;
  }
}
