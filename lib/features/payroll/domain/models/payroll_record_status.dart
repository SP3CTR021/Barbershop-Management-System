/// Disbursement status mapped to `payroll_records.status` (`PENDING`, `PAID`).
enum PayrollRecordStatus {
  pending('PENDING'),
  paid('PAID');

  const PayrollRecordStatus(this.dbValue);

  final String dbValue;

  static PayrollRecordStatus fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in PayrollRecordStatus.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown PayrollRecordStatus value.');
  }
}
