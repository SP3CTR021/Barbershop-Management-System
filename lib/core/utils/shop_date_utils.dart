/// Timezone-safe helpers for shop-local `DATE` columns (`work_date`, `hire_date`,
/// `start_date`, `end_date`, `effective_from`, `effective_to`) normalized to UTC
/// midnight, plus conversion between UTC timestamps and shop-local `+08:00` days.
abstract final class ShopDateUtils {
  /// Default Philippine Standard Time (`+08:00`) offset used to align payroll
  /// period boundaries with the barbershop's business day.
  static const Duration defaultShopUtcOffset = Duration(hours: 8);

  static final RegExp _isoDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Normalizes a calendar date to UTC midnight (`YYYY-MM-DD 00:00:00Z`) so
  /// SQL `DATE` comparisons and equality checks never depend on device timezone.
  static DateTime normalizeDate(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Converts an instant [timestamp] into the shop-local calendar date
  /// (returned normalized at UTC midnight).
  static DateTime toShopLocalDate(
    DateTime timestamp, {
    Duration shopOffset = defaultShopUtcOffset,
  }) {
    final shifted = timestamp.toUtc().add(shopOffset);
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }

  /// Computes exact half-open `[startUtcInclusive, endUtcExclusive)` timestamp
  /// bounds covering `[startDate, endDate]` inclusive in the shop's local day.
  static ({DateTime startUtcInclusive, DateTime endUtcExclusive})
      utcRangeForShopDateRange({
    required DateTime startDate,
    required DateTime endDate,
    Duration shopOffset = defaultShopUtcOffset,
  }) {
    final normalizedStart = normalizeDate(startDate);
    final normalizedEnd = normalizeDate(endDate);
    if (normalizedEnd.isBefore(normalizedStart)) {
      throw ArgumentError(
        'endDate ($normalizedEnd) cannot precede startDate ($normalizedStart).',
      );
    }
    final startUtcInclusive = normalizedStart.subtract(shopOffset);
    final endUtcExclusive =
        normalizedEnd.add(const Duration(days: 1)).subtract(shopOffset);
    return (
      startUtcInclusive: startUtcInclusive,
      endUtcExclusive: endUtcExclusive,
    );
  }

  /// Formats [date] as `'YYYY-MM-DD'` using its calendar components.
  static String formatIsoDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Parses strict `'YYYY-MM-DD'` (or leading `'YYYY-MM-DD'` of an ISO string)
  /// into a normalized UTC midnight [DateTime].
  static DateTime parseIsoDate(String isoDate) {
    final trimmed = isoDate.trim();
    final datePart = trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
    final match = _isoDatePattern.firstMatch(datePart);
    if (match == null) {
      throw FormatException('Invalid ISO date "$isoDate"; expected YYYY-MM-DD.');
    }
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw FormatException('Calendar date out of range: "$isoDate".');
    }
    return parsed;
  }
}
