/// Employment/availability status mapped to `barbers.status` (`ACTIVE`, `INACTIVE`).
enum BarberStatus {
  active('ACTIVE'),
  inactive('INACTIVE');

  const BarberStatus(this.dbValue);

  final String dbValue;

  static BarberStatus fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in BarberStatus.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown BarberStatus value.');
  }
}
