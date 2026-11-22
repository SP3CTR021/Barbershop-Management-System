/// Centavo-based financial arithmetic helpers that normalize `double` monetary
/// amounts to 2 decimal places so 60/40 payroll splits never drift.
abstract final class MoneyMath {
  static int toCentavos(double amount) => (amount * 100).round();

  static double fromCentavos(int centavos) => centavos / 100.0;

  static double round2(double amount) => fromCentavos(toCentavos(amount));

  static double multiply(double unitPrice, int quantity) {
    return fromCentavos(toCentavos(unitPrice) * quantity);
  }

  static double sum(Iterable<double> amounts) {
    final totalCentavos = amounts.fold<int>(
      0,
      (acc, value) => acc + toCentavos(value),
    );
    return fromCentavos(totalCentavos);
  }

  /// Splits [grossSales] cleanly by centavos so `ownerShareAmount + barberPayAmount`
  /// always equals `grossSales` exactly without losing a centavo to rounding.
  static ({double ownerShareAmount, double barberPayAmount}) splitSales({
    required double grossSales,
    required double ownerSharePct,
    required double barberSharePct,
  }) {
    assert(
      sharesSumTo100(ownerSharePct, barberSharePct),
      'ownerSharePct + barberSharePct must equal 100.00',
    );
    final grossCentavos = toCentavos(grossSales);
    final barberCentavos = ((grossCentavos * barberSharePct) / 100.0).round();
    final ownerCentavos = grossCentavos - barberCentavos;
    return (
      ownerShareAmount: fromCentavos(ownerCentavos),
      barberPayAmount: fromCentavos(barberCentavos),
    );
  }

  /// Matches the SQL constraint `CHECK (owner_share_pct + barber_share_pct = 100)`.
  static bool sharesSumTo100(double ownerSharePct, double barberSharePct) {
    return ((ownerSharePct + barberSharePct) * 100).round() == 10000;
  }
}
