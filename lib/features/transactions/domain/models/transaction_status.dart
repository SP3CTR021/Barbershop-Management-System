/// Lifecycle state mapped to `transactions.status` (`PENDING`, `PAID`, `VOID`).
/// Named `voided` in Dart because `void` is a reserved keyword.
enum TransactionStatus {
  pending('PENDING'),
  paid('PAID'),
  voided('VOID');

  const TransactionStatus(this.dbValue);

  final String dbValue;

  static TransactionStatus fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in TransactionStatus.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown TransactionStatus value.');
  }
}
