import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';

const Object _unset = Object();

/// Domain model for `attendance`.
///
/// Relationships:
/// - `barbers` (1) -> `attendance` (M) via [barberId].
/// - `users` (`STAFF`, 1) -> `attendance` (M) via [recordedBy].
///
/// Uniqueness: `UNIQUE (barber_id, work_date)` — one row per barber per day.
/// Schema refinement: [timeIn] is nullable so `ABSENT` and `LEAVE` rows do not
/// require a clock-in time, whereas `PRESENT` requires non-null [timeIn].
final class Attendance {
  Attendance({
    required this.attendanceId,
    required this.barberId,
    required this.recordedBy,
    required DateTime workDate,
    this.timeIn,
    this.timeOut,
    required this.status,
  }) : workDate = ShopDateUtils.normalizeDate(workDate);

  final String attendanceId;

  /// FK -> `barbers.barber_id`.
  final String barberId;

  /// FK -> `users.user_id` (front-desk `STAFF` who logged the record).
  final String recordedBy;

  /// Normalized shop-local date (UTC midnight).
  final DateTime workDate;

  final ShopTime? timeIn;
  final ShopTime? timeOut;
  final AttendanceStatus status;

  Attendance copyWith({
    String? attendanceId,
    String? barberId,
    String? recordedBy,
    DateTime? workDate,
    Object? timeIn = _unset,
    Object? timeOut = _unset,
    AttendanceStatus? status,
  }) {
    return Attendance(
      attendanceId: attendanceId ?? this.attendanceId,
      barberId: barberId ?? this.barberId,
      recordedBy: recordedBy ?? this.recordedBy,
      workDate: workDate ?? this.workDate,
      timeIn: identical(timeIn, _unset) ? this.timeIn : timeIn as ShopTime?,
      timeOut: identical(timeOut, _unset) ? this.timeOut : timeOut as ShopTime?,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Attendance &&
            other.attendanceId == attendanceId &&
            other.barberId == barberId &&
            other.recordedBy == recordedBy &&
            other.workDate == workDate &&
            other.timeIn == timeIn &&
            other.timeOut == timeOut &&
            other.status == status;
  }

  @override
  int get hashCode => Object.hash(
        attendanceId,
        barberId,
        recordedBy,
        workDate,
        timeIn,
        timeOut,
        status,
      );

  @override
  String toString() =>
      'Attendance(attendanceId: $attendanceId, barberId: $barberId, workDate: ${ShopDateUtils.formatIsoDate(workDate)}, status: ${status.dbValue})';
}
