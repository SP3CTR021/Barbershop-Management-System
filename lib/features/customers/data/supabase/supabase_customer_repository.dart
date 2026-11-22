import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/features/customers/data/supabase/customer_supabase_dto.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [CustomerRepository].
/// Deleting a customer automatically relies on `ON DELETE SET NULL` in
/// `transactions.customer_id` so historical visits stay valid as walk-ins.
final class SupabaseCustomerRepository implements CustomerRepository {
  SupabaseCustomerRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<Customer>> createCustomer({
    required String firstName,
    required String lastName,
    String? phone,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final fName = firstName.trim();
      final lName = lastName.trim();
      if (fName.isEmpty || lName.isEmpty) {
        throw const ValidationFailure(
          message: 'Customer first and last name are required.',
        );
      }

      final inserted = await _client
          .from('customers')
          .insert(<String, dynamic>{
            'first_name': fName,
            'last_name': lName,
            'phone': SupabaseParseUtils.cleanNullableText(phone),
          })
          .select()
          .single();
      return CustomerSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  @override
  Future<Result<Customer>> getCustomerById(String customerId) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('customers')
          .select()
          .eq('customer_id', customerId)
          .maybeSingle();
      if (row == null) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }
      return CustomerSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<Customer>>> getCustomers({String? searchQuery}) {
    return SupabaseErrorMapper.guard(() async {
      var query = _client.from('customers').select();
      final trimmed = searchQuery?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        final escaped = trimmed.replaceAll(',', '');
        query = query.or(
          'first_name.ilike.%$escaped%,last_name.ilike.%$escaped%,phone.ilike.%$escaped%',
        );
      }
      final rows = await query
          .order('last_name', ascending: true)
          .order('first_name', ascending: true);
      return rows
          .map((row) => CustomerSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<Customer>>> watchCustomers() {
    final stream = _client
        .from('customers')
        .stream(primaryKey: <String>['customer_id'])
        .order('last_name', ascending: true)
        .map(
          (rows) => rows
              .map((row) => CustomerSupabaseDto.fromSupabase(row).toDomain())
              .toList(growable: false),
        );
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<Customer>> updateCustomer(Customer customer) {
    return SupabaseErrorMapper.guard(() async {
      final dto = CustomerSupabaseDto.fromDomain(customer);
      final updated = await _client
          .from('customers')
          .update(dto.toSupabase())
          .eq('customer_id', customer.customerId)
          .select()
          .maybeSingle();
      if (updated == null) {
        throw NotFoundFailure(
          message: 'Customer ${customer.customerId} not found.',
          entityName: 'Customer',
          entityId: customer.customerId,
        );
      }
      return CustomerSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<void>> deleteCustomer(String customerId) {
    return SupabaseErrorMapper.guard(() async {
      final deleted = await _client
          .from('customers')
          .delete()
          .eq('customer_id', customerId)
          .select()
          .maybeSingle();
      if (deleted == null) {
        throw NotFoundFailure(
          message: 'Customer $customerId not found.',
          entityName: 'Customer',
          entityId: customerId,
        );
      }
    });
  }
}
