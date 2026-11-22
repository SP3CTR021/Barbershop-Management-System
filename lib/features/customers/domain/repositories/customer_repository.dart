import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';

/// Backend-agnostic contract for `customers`.
abstract interface class CustomerRepository {
  Future<Result<Customer>> createCustomer({
    required String firstName,
    required String lastName,
    String? phone,
  });

  Future<Result<Customer>> getCustomerById(String customerId);

  Future<Result<List<Customer>>> getCustomers({String? searchQuery});

  Stream<Result<List<Customer>>> watchCustomers();

  Future<Result<Customer>> updateCustomer(Customer customer);

  /// Deletes a customer record and sets `customer_id = null` on any linked
  /// `transactions` (`ON DELETE SET NULL`) so walk-in sales history stays valid.
  Future<Result<void>> deleteCustomer(String customerId);
}
