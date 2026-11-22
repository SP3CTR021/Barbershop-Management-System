/// Daily attendance status mapped to `attendance.status` (`PRESENT`, `ABSENT`, `LEAVE`).
enum AttendanceStatus {
  present('PRESENT'),
  absent('ABSENT'),
  leave('LEAVE');

  const AttendanceStatus(this.dbValue);

  final String dbValue;

  static AttendanceStatus fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in AttendanceStatus.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown AttendanceStatus value.');
  }
}
