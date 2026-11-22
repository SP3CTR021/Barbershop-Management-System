/// Accepted tender types mapped to `payments.payment_method` (`CASH`, `GCASH`, `CARD`).
enum PaymentMethod {
  cash('CASH'),
  gcash('GCASH'),
  card('CARD');

  const PaymentMethod(this.dbValue);

  final String dbValue;

  static PaymentMethod fromDbValue(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final value in PaymentMethod.values) {
      if (value.dbValue == normalized) return value;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown PaymentMethod value.');
  }
}
