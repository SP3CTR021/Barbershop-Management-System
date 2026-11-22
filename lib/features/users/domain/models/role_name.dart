/// Fixed authorization roles mapped to `roles.role_name` (`OWNER`, `STAFF`, `BARBER`).
enum RoleName {
  owner('OWNER'),
  staff('STAFF'),
  barber('BARBER');

  const RoleName(this.dbValue);

  final String dbValue;

  static RoleName fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in RoleName.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown RoleName value.');
  }
}
