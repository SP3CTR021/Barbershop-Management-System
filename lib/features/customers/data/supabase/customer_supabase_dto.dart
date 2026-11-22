import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';

/// Supabase DTO mapping `public.customers` snake_case rows to domain [Customer].
final class CustomerSupabaseDto {
  const CustomerSupabaseDto({
    required this.customerId,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.createdAt,
  });

  factory CustomerSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return CustomerSupabaseDto(
      customerId: map['customer_id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      phone: map['phone'] as String?,
      createdAt: SupabaseParseUtils.parseTimestamp(map['created_at']),
    );
  }

  factory CustomerSupabaseDto.fromDomain(Customer customer) {
    return CustomerSupabaseDto(
      customerId: customer.customerId,
      firstName: customer.firstName,
      lastName: customer.lastName,
      phone: customer.phone,
      createdAt: customer.createdAt,
    );
  }

  final String customerId;
  final String firstName;
  final String lastName;
  final String? phone;
  final DateTime createdAt;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'customer_id': customerId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      'phone': SupabaseParseUtils.cleanNullableText(phone),
    };
  }

  Customer toDomain() {
    return Customer(
      customerId: customerId,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      createdAt: createdAt,
    );
  }
}
