import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';

/// Supabase DTO mapping `public.attendance` (`DATE` + `TIME`) to domain [Attendance].
final class AttendanceSupabaseDto {
  const AttendanceSupabaseDto({
    required this.attendanceId,
    required this.barberId,
    required this.recordedBy,
    required this.workDate,
    this.timeIn,
    this.timeOut,
    required this.status,
  });

  factory AttendanceSupabaseDto.fromSupabase(Map<String, dynamic> map) {
    return AttendanceSupabaseDto(
      attendanceId: map['attendance_id'] as String,
      barberId: map['barber_id'] as String,
      recordedBy: map['recorded_by'] as String,
      workDate: SupabaseParseUtils.parseDate(map['work_date']),
      timeIn: SupabaseParseUtils.parseNullableTime(map['time_in']),
      timeOut: SupabaseParseUtils.parseNullableTime(map['time_out']),
      status: map['status'] as String,
    );
  }

  factory AttendanceSupabaseDto.fromDomain(Attendance attendance) {
    return AttendanceSupabaseDto(
      attendanceId: attendance.attendanceId,
      barberId: attendance.barberId,
      recordedBy: attendance.recordedBy,
      workDate: attendance.workDate,
      timeIn: attendance.timeIn,
      timeOut: attendance.timeOut,
      status: attendance.status.dbValue,
    );
  }

  final String attendanceId;
  final String barberId;
  final String recordedBy;
  final DateTime workDate;
  final ShopTime? timeIn;
  final ShopTime? timeOut;
  final String status;

  Map<String, dynamic> toSupabase({bool includeId = false}) {
    return <String, dynamic>{
      if (includeId) 'attendance_id': attendanceId,
      'barber_id': barberId,
      'recorded_by': recordedBy,
      'work_date': ShopDateUtils.formatIsoDate(workDate),
      'time_in': timeIn?.toIsoTimeString(),
      'time_out': timeOut?.toIsoTimeString(),
      'status': status,
    };
  }

  Attendance toDomain() {
    return Attendance(
      attendanceId: attendanceId,
      barberId: barberId,
      recordedBy: recordedBy,
      workDate: workDate,
      timeIn: timeIn,
      timeOut: timeOut,
      status: AttendanceStatus.fromDbValue(status),
    );
  }
}
