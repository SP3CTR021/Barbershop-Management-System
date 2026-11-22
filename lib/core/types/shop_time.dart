/// Pure-Dart wall-clock time-of-day value object representing SQL `TIME`
/// (e.g., `attendance.time_in` and `attendance.time_out`) without Flutter UI deps.
final class ShopTime implements Comparable<ShopTime> {
  const ShopTime({
    required this.hour,
    required this.minute,
    this.second = 0,
  })  : assert(hour >= 0 && hour <= 23, 'hour must be 0..23'),
        assert(minute >= 0 && minute <= 59, 'minute must be 0..59'),
        assert(second >= 0 && second <= 59, 'second must be 0..59');

  /// Validates bounds at runtime when constructing from external input.
  factory ShopTime.validated({
    required int hour,
    required int minute,
    int second = 0,
  }) {
    if (hour < 0 || hour > 23) {
      throw FormatException('Invalid hour "$hour"; expected 0..23.');
    }
    if (minute < 0 || minute > 59) {
      throw FormatException('Invalid minute "$minute"; expected 0..59.');
    }
    if (second < 0 || second > 59) {
      throw FormatException('Invalid second "$second"; expected 0..59.');
    }
    return ShopTime(hour: hour, minute: minute, second: second);
  }

  /// Parses `'HH:mm'`, `'HH:mm:ss'`, or `'HH:mm:ss.SSSSSS'` (ignoring fractions).
  factory ShopTime.parse(String value) {
    final trimmed = value.trim();
    final match = _timePattern.firstMatch(trimmed);
    if (match == null) {
      throw FormatException(
        'Invalid ShopTime "$value"; expected HH:mm or HH:mm:ss.',
      );
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final secondGroup = match.group(3);
    final second = secondGroup == null ? 0 : int.parse(secondGroup);
    return ShopTime.validated(hour: hour, minute: minute, second: second);
  }

  factory ShopTime.fromDateTime(DateTime dateTime) {
    return ShopTime(
      hour: dateTime.hour,
      minute: dateTime.minute,
      second: dateTime.second,
    );
  }

  static final RegExp _timePattern = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$',
  );

  final int hour;
  final int minute;
  final int second;

  int get totalSeconds => hour * 3600 + minute * 60 + second;

  /// Formats as zero-padded `'HH:mm:ss'` for Postgres `TIME` and Firestore strings.
  String toIsoTimeString() {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    final s = second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  bool isBefore(ShopTime other) => totalSeconds < other.totalSeconds;

  bool isAfter(ShopTime other) => totalSeconds > other.totalSeconds;

  ShopTime copyWith({
    int? hour,
    int? minute,
    int? second,
  }) {
    return ShopTime.validated(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      second: second ?? this.second,
    );
  }

  @override
  int compareTo(ShopTime other) => totalSeconds.compareTo(other.totalSeconds);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ShopTime &&
            other.hour == hour &&
            other.minute == minute &&
            other.second == second;
  }

  @override
  int get hashCode => Object.hash(hour, minute, second);

  @override
  String toString() => toIsoTimeString();
}
