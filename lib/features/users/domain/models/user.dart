const Object _unset = Object();

/// Domain model for `users` representing every shop member (`OWNER`, `STAFF`, `BARBER`).
///
/// Relationship:
/// - `roles` (1) -> `users` (M) via [roleId].
/// - `users` (1) -> `barbers` (0..1) when the user's role is `BARBER`.
/// - Audit parent (1:M) for `attendance.recorded_by`, `transactions.logged_by`,
///   `payments.received_by`, `payroll_settings.created_by`, `payroll_periods.generated_by`.
///
/// Auth & security note: `password_hash` from the relational ERD is intentionally
/// omitted from this domain model and public tables/collections; login credentials
/// for `OWNER` and `STAFF` live strictly inside Supabase Auth / Firebase Auth,
/// while `BARBER` users do not sign in directly (checked in by `STAFF`).
final class User {
  const User({
    required this.userId,
    required this.roleId,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.phone,
    this.email,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// String UUID (Supabase `auth.users.id` for login roles) or Firestore document ID.
  final String userId;

  /// FK -> `roles.role_id`.
  final String roleId;

  final String firstName;
  final String lastName;

  /// Unique handle (`users.username`).
  final String username;

  final String? phone;

  /// Optional unique email (`users.email`). Required for `OWNER`/`STAFF` login accounts.
  final String? email;

  /// Soft-delete flag (Business Rule #7: preserve financial/audit history).
  final bool isActive;

  final DateTime createdAt;
  final DateTime updatedAt;

  String get fullName => '$firstName $lastName'.trim();

  User copyWith({
    String? userId,
    String? roleId,
    String? firstName,
    String? lastName,
    String? username,
    Object? phone = _unset,
    Object? email = _unset,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      userId: userId ?? this.userId,
      roleId: roleId ?? this.roleId,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      phone: identical(phone, _unset) ? this.phone : phone as String?,
      email: identical(email, _unset) ? this.email : email as String?,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is User &&
            other.userId == userId &&
            other.roleId == roleId &&
            other.firstName == firstName &&
            other.lastName == lastName &&
            other.username == username &&
            other.phone == phone &&
            other.email == email &&
            other.isActive == isActive &&
            other.createdAt == createdAt &&
            other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        userId,
        roleId,
        firstName,
        lastName,
        username,
        phone,
        email,
        isActive,
        createdAt,
        updatedAt,
      );

  @override
  String toString() =>
      'User(userId: $userId, roleId: $roleId, username: $username, isActive: $isActive)';
}
