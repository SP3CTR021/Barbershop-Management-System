import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';

/// Firestore DTO mapping `attendance/{barberId}_{yyyy-MM-dd}` documents to
/// domain [Attendance].
final class AttendanceFirestoreDto {
  const AttendanceFirestoreDto({
    required this.attendanceId,
    required this.barberId,
    required this.recordedBy,
    required this.workDate,
    this.timeIn,
    this.timeOut,
    required this.status,
  });

  factory AttendanceFirestoreDto.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    return AttendanceFirestoreDto(
      attendanceId: (data['attendanceId'] as String?) ?? id,
      barberId: data['barberId'] as String,
      recordedBy: data['recordedBy'] as String,
      workDate: FirestoreParseUtils.parseDate(data['workDate']),
      timeIn: FirestoreParseUtils.parseNullableTime(data['timeIn']),
      timeOut: FirestoreParseUtils.parseNullableTime(data['timeOut']),
      status: data['status'] as String,
    );
  }

  factory AttendanceFirestoreDto.fromDomain(Attendance attendance) {
    return AttendanceFirestoreDto(
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

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'attendanceId': attendanceId,
      'barberId': barberId,
      'recordedBy': recordedBy,
      'workDate': ShopDateUtils.formatIsoDate(workDate),
      'timeIn': timeIn?.toIsoTimeString(),
      'timeOut': timeOut?.toIsoTimeString(),
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
