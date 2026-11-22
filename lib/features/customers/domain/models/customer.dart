const Object _unset = Object();

/// Domain model for `customers`.
/// Relationship: `customers` (0..1) -> `transactions` (M); walk-in visits
/// leave `transactions.customer_id` null.
final class Customer {
  const Customer({
    required this.customerId,
    required this.firstName,
    required this.lastName,
    this.phone,
    required this.createdAt,
  });

  final String customerId;
  final String firstName;
  final String lastName;
  final String? phone;
  final DateTime createdAt;

  String get fullName => '$firstName $lastName'.trim();

  Customer copyWith({
    String? customerId,
    String? firstName,
    String? lastName,
    Object? phone = _unset,
    DateTime? createdAt,
  }) {
    return Customer(
      customerId: customerId ?? this.customerId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: identical(phone, _unset) ? this.phone : phone as String?,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Customer &&
            other.customerId == customerId &&
            other.firstName == firstName &&
            other.lastName == lastName &&
            other.phone == phone &&
            other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(customerId, firstName, lastName, phone, createdAt);

  @override
  String toString() =>
      'Customer(customerId: $customerId, fullName: $fullName, phone: $phone)';
}
