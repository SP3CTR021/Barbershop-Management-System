import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Firestore DTO mapping `customers/{customerId}` documents to domain [Customer].
final class CustomerFirestoreDto {
  const CustomerFirestoreDto({
    required this.customerId,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.createdAt,
  });

  factory CustomerFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return CustomerFirestoreDto(
      customerId: (data['customerId'] as String?) ?? id,
      firstName: data['firstName'] as String,
      lastName: data['lastName'] as String,
      phone: data['phone'] as String?,
      createdAt: FirestoreParseUtils.parseTimestamp(data['createdAt']),
    );
  }

  factory CustomerFirestoreDto.fromDomain(Customer customer) {
    return CustomerFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    final cleanFirst = firstName.trim();
    final cleanLast = lastName.trim();
    return <String, dynamic>{
      'customerId': customerId,
      'firstName': cleanFirst,
      'lastName': cleanLast,
      'fullNameLower': '$cleanFirst $cleanLast'.trim().toLowerCase(),
      'phone': FirestoreParseUtils.cleanNullableText(phone),
      'createdAt': fs.Timestamp.fromDate(createdAt.toUtc()),
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
