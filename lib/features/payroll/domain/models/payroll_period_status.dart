/// Lifecycle status mapped to `payroll_periods.status` (`DRAFT`, `APPROVED`, `PAID`).
enum PayrollPeriodStatus {
  draft('DRAFT'),
  approved('APPROVED'),
  paid('PAID');

  const PayrollPeriodStatus(this.dbValue);

  final String dbValue;

  static PayrollPeriodStatus fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in PayrollPeriodStatus.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown PayrollPeriodStatus value.');
  }
}
