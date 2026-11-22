import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/data/supabase/attendance_supabase_dto.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [AttendanceRepository].
/// Relies on `UNIQUE (barber_id, work_date)` and `chk_attendance_times` in SQL.
final class SupabaseAttendanceRepository implements AttendanceRepository {
  SupabaseAttendanceRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<Attendance>> checkInBarber({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required ShopTime timeIn,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: recordedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      await _assertBarberActive(barberId);

      final inserted = await _client
          .from('attendance')
          .insert(<String, dynamic>{
            'barber_id': barberId,
            'recorded_by': recordedByStaffId,
            'work_date': ShopDateUtils.formatIsoDate(workDate),
            'time_in': timeIn.toIsoTimeString(),
            'time_out': null,
            'status': AttendanceStatus.present.dbValue,
          })
          .select()
          .single();
      return AttendanceSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  @override
  Future<Result<Attendance>> checkOutBarber({
    required String attendanceId,
    required ShopTime timeOut,
    required String actingStaffId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: actingStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      final existingRow = await _client
          .from('attendance')
          .select()
          .eq('attendance_id', attendanceId)
          .maybeSingle();
      if (existingRow == null) {
        throw NotFoundFailure(
          message: 'Attendance $attendanceId not found.',
          entityName: 'Attendance',
          entityId: attendanceId,
        );
      }

      final existing =
          AttendanceSupabaseDto.fromSupabase(existingRow).toDomain();
      if (existing.status != AttendanceStatus.present ||
          existing.timeIn == null) {
        throw const ValidationFailure(
          message: 'Only PRESENT attendance records can be checked out.',
        );
      }
      if (timeOut.isBefore(existing.timeIn!)) {
        throw const ValidationFailure(
          message: 'timeOut cannot be earlier than timeIn.',
          field: 'timeOut',
        );
      }

      final updated = await _client
          .from('attendance')
          .update(<String, dynamic>{'time_out': timeOut.toIsoTimeString()})
          .eq('attendance_id', attendanceId)
          .select()
          .single();
      return AttendanceSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<Attendance>> markNonPresent({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required AttendanceStatus status,
  }) {
    return SupabaseErrorMapper.guard(() async {
      if (status == AttendanceStatus.present) {
        throw const ValidationFailure(
          message: 'Use checkInBarber() to record PRESENT attendance.',
          field: 'status',
        );
      }

      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: recordedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      await _assertBarberExists(barberId);

      final inserted = await _client
          .from('attendance')
          .insert(<String, dynamic>{
            'barber_id': barberId,
            'recorded_by': recordedByStaffId,
            'work_date': ShopDateUtils.formatIsoDate(workDate),
            'time_in': null,
            'time_out': null,
            'status': status.dbValue,
          })
          .select()
          .single();
      return AttendanceSupabaseDto.fromSupabase(inserted).toDomain();
    });
  }

  @override
  Future<Result<Attendance?>> getBarberAttendanceForDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('attendance')
          .select()
          .eq('barber_id', barberId)
          .eq('work_date', ShopDateUtils.formatIsoDate(workDate))
          .maybeSingle();
      if (row == null) return null;
      return AttendanceSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<bool>> isBarberPresentOnDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('attendance')
          .select('status')
          .eq('barber_id', barberId)
          .eq('work_date', ShopDateUtils.formatIsoDate(workDate))
          .maybeSingle();
      if (row == null) return false;
      return AttendanceStatus.fromDbValue(row['status'] as String) ==
          AttendanceStatus.present;
    });
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceByDate(DateTime workDate) {
    return SupabaseErrorMapper.guard(() async {
      final rows = await _client
          .from('attendance')
          .select()
          .eq('work_date', ShopDateUtils.formatIsoDate(workDate))
          .order('time_in', ascending: true);
      return rows
          .map((row) => AttendanceSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<Attendance>>> watchAttendanceByDate(DateTime workDate) {
    final targetDate = ShopDateUtils.formatIsoDate(workDate);
    final stream = _client
        .from('attendance')
        .stream(primaryKey: <String>['attendance_id'])
        .eq('work_date', targetDate)
        .order('time_in', ascending: true)
        .map(
          (rows) => rows
              .map((row) => AttendanceSupabaseDto.fromSupabase(row).toDomain())
              .toList(growable: false),
        );
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceForBarber({
    required String barberId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final normalizedStart = ShopDateUtils.normalizeDate(startDate);
      final normalizedEnd = ShopDateUtils.normalizeDate(endDate);
      if (normalizedEnd.isBefore(normalizedStart)) {
        throw const ValidationFailure(
          message: 'endDate cannot precede startDate.',
        );
      }

      final rows = await _client
          .from('attendance')
          .select()
          .eq('barber_id', barberId)
          .gte('work_date', ShopDateUtils.formatIsoDate(normalizedStart))
          .lte('work_date', ShopDateUtils.formatIsoDate(normalizedEnd))
          .order('work_date', ascending: true);
      return rows
          .map((row) => AttendanceSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  Future<void> _assertBarberExists(String barberId) async {
    final row = await _client
        .from('barbers')
        .select('barber_id')
        .eq('barber_id', barberId)
        .maybeSingle();
    if (row == null) {
      throw NotFoundFailure(
        message: 'Barber $barberId not found.',
        entityName: 'Barber',
        entityId: barberId,
      );
    }
  }

  Future<void> _assertBarberActive(String barberId) async {
    final row = await _client
        .from('barbers')
        .select('status, users!inner(is_active)')
        .eq('barber_id', barberId)
        .maybeSingle();
    if (row == null) {
      throw NotFoundFailure(
        message: 'Barber $barberId not found.',
        entityName: 'Barber',
        entityId: barberId,
      );
    }
    final status = row['status'] as String;
    final userActive = (row['users'] as Map<String, dynamic>)['is_active'] as bool;
    if (status != 'ACTIVE' || !userActive) {
      throw ValidationFailure(
        message: 'Inactive barber $barberId cannot be checked in.',
        field: 'barberId',
      );
    }
  }
}
