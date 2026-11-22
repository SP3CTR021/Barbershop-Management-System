import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';

/// Backend-agnostic contract for daily barber attendance.
/// Per Business Rule #1, attendance is recorded by `STAFF` (or `OWNER`).
abstract interface class AttendanceRepository {
  /// Marks an active barber as `PRESENT` for [workDate] with [timeIn].
  /// Enforces `UNIQUE (barber_id, work_date)` and rejects inactive barbers.
  Future<Result<Attendance>> checkInBarber({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required ShopTime timeIn,
  });

  /// Sets [timeOut] on an existing `PRESENT` attendance record.
  Future<Result<Attendance>> checkOutBarber({
    required String attendanceId,
    required ShopTime timeOut,
    required String actingStaffId,
  });

  /// Records `ABSENT` or `LEAVE` for [barberId] on [workDate] (rejects `PRESENT`,
  /// which must use [checkInBarber] with a valid [ShopTime]).
  Future<Result<Attendance>> markNonPresent({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required AttendanceStatus status,
  });

  Future<Result<Attendance?>> getBarberAttendanceForDate({
    required String barberId,
    required DateTime workDate,
  });

  /// Fast check used to enforce Business Rule #3 before creating a transaction.
  Future<Result<bool>> isBarberPresentOnDate({
    required String barberId,
    required DateTime workDate,
  });

  Future<Result<List<Attendance>>> getAttendanceByDate(DateTime workDate);

  Stream<Result<List<Attendance>>> watchAttendanceByDate(DateTime workDate);

  Future<Result<List<Attendance>>> getAttendanceForBarber({
    required String barberId,
    required DateTime startDate,
    required DateTime endDate,
  });
}
