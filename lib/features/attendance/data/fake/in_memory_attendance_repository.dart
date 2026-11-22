import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';

/// In-memory fake implementation of [AttendanceRepository].
final class InMemoryAttendanceRepository implements AttendanceRepository {
  InMemoryAttendanceRepository(this._db);

  final InMemoryDatabase _db;

  @override
  Future<Result<Attendance>> checkInBarber({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required ShopTime timeIn,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: recordedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      final barber = _db.barbers[barberId];
      if (barber == null) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }
      final barberUser = _db.users[barber.userId];
      if (barber.status != BarberStatus.active ||
          !(barberUser?.isActive ?? false)) {
        throw ValidationFailure(
          message: 'Inactive barber $barberId cannot be checked in.',
          field: 'barberId',
        );
      }

      final normalizedDate = ShopDateUtils.normalizeDate(workDate);
      final key = _db.attendanceKey(barberId, normalizedDate);
      if (_db.attendance.containsKey(key)) {
        throw DuplicateEntryFailure(
          message:
              'Attendance already recorded for barber $barberId on ${ShopDateUtils.formatIsoDate(normalizedDate)}.',
          field: 'workDate',
          value: ShopDateUtils.formatIsoDate(normalizedDate),
        );
      }

      final record = Attendance(
        attendanceId: key,
        barberId: barberId,
        recordedBy: recordedByStaffId,
        workDate: normalizedDate,
        timeIn: timeIn,
        timeOut: null,
        status: AttendanceStatus.present,
      );
      _db.attendance[key] = record;
      _db.notifyChanged();
      return record;
    });
  }

  @override
  Future<Result<Attendance>> checkOutBarber({
    required String attendanceId,
    required ShopTime timeOut,
    required String actingStaffId,
  }) {
    return _db.guard(() {
      _db.assertActiveUserRole(
        actingUserId: actingStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      final existing = _db.attendance[attendanceId];
      if (existing == null) {
        throw NotFoundFailure(
          message: 'Attendance $attendanceId not found.',
          entityName: 'Attendance',
          entityId: attendanceId,
        );
      }
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

      final updated = existing.copyWith(timeOut: timeOut);
      _db.attendance[attendanceId] = updated;
      _db.notifyChanged();
      return updated;
    });
  }

  @override
  Future<Result<Attendance>> markNonPresent({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required AttendanceStatus status,
  }) {
    return _db.guard(() {
      if (status == AttendanceStatus.present) {
        throw const ValidationFailure(
          message: 'Use checkInBarber() to record PRESENT attendance.',
          field: 'status',
        );
      }

      _db.assertActiveUserRole(
        actingUserId: recordedByStaffId,
        allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
      );

      if (!_db.barbers.containsKey(barberId)) {
        throw NotFoundFailure(
          message: 'Barber $barberId not found.',
          entityName: 'Barber',
          entityId: barberId,
        );
      }

      final normalizedDate = ShopDateUtils.normalizeDate(workDate);
      final key = _db.attendanceKey(barberId, normalizedDate);
      if (_db.attendance.containsKey(key)) {
        throw DuplicateEntryFailure(
          message:
              'Attendance already recorded for barber $barberId on ${ShopDateUtils.formatIsoDate(normalizedDate)}.',
          field: 'workDate',
          value: ShopDateUtils.formatIsoDate(normalizedDate),
        );
      }

      final record = Attendance(
        attendanceId: key,
        barberId: barberId,
        recordedBy: recordedByStaffId,
        workDate: normalizedDate,
        timeIn: null,
        timeOut: null,
        status: status,
      );
      _db.attendance[key] = record;
      _db.notifyChanged();
      return record;
    });
  }

  @override
  Future<Result<Attendance?>> getBarberAttendanceForDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return _db.guard(() => _db.attendance[_db.attendanceKey(barberId, workDate)]);
  }

  @override
  Future<Result<bool>> isBarberPresentOnDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return _db.guard(() {
      final record = _db.attendance[_db.attendanceKey(barberId, workDate)];
      return record?.status == AttendanceStatus.present;
    });
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceByDate(DateTime workDate) {
    return _db.guard(() => _listByDate(workDate));
  }

  @override
  Stream<Result<List<Attendance>>> watchAttendanceByDate(DateTime workDate) {
    return _db.watchQuery(() => _listByDate(workDate));
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceForBarber({
    required String barberId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _db.guard(() {
      final normalizedStart = ShopDateUtils.normalizeDate(startDate);
      final normalizedEnd = ShopDateUtils.normalizeDate(endDate);
      if (normalizedEnd.isBefore(normalizedStart)) {
        throw const ValidationFailure(
          message: 'endDate cannot precede startDate.',
        );
      }

      final list = _db.attendance.values.where((record) {
        return record.barberId == barberId &&
            !record.workDate.isBefore(normalizedStart) &&
            !record.workDate.isAfter(normalizedEnd);
      }).toList(growable: false)
        ..sort((a, b) => a.workDate.compareTo(b.workDate));
      return list;
    });
  }

  List<Attendance> _listByDate(DateTime workDate) {
    final normalized = ShopDateUtils.normalizeDate(workDate);
    final list = _db.attendance.values
        .where((record) => record.workDate == normalized)
        .toList(growable: false)
      ..sort((a, b) {
        if (a.timeIn == null && b.timeIn == null) {
          return a.barberId.compareTo(b.barberId);
        }
        if (a.timeIn == null) return 1;
        if (b.timeIn == null) return -1;
        return a.timeIn!.compareTo(b.timeIn!);
      });
    return list;
  }
}
