import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/attendance/data/firestore/attendance_firestore_dto.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

/// Cloud Firestore implementation of [AttendanceRepository].
///
/// Firestore workaround: uses deterministic document IDs
/// `${barberId}_${yyyy-MM-dd}` inside `runTransaction` to enforce the
/// relational `UNIQUE (barber_id, work_date)` constraint atomically and support
/// direct `O(1)` lookup when validating Business Rule #3 on transactions.
final class FirestoreAttendanceRepository implements AttendanceRepository {
  FirestoreAttendanceRepository(this._firestore);

  final fs.FirebaseFirestore _firestore;

  fs.CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('attendance');
  fs.CollectionReference<Map<String, dynamic>> get _barbers =>
      _firestore.collection('barbers');
  fs.CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  @override
  Future<Result<Attendance>> checkInBarber({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required ShopTime timeIn,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final normalizedDate = ShopDateUtils.normalizeDate(workDate);
      final docId =
          FirestoreParseUtils.attendanceDocId(barberId, normalizedDate);

      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: recordedByStaffId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
          tx: tx,
        );

        final barberSnap = await tx.get(_barbers.doc(barberId));
        if (!barberSnap.exists || barberSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Barber $barberId not found.',
            entityName: 'Barber',
            entityId: barberId,
          );
        }

        final barberData = barberSnap.data()!;
        bool userActive;
        if (barberData['userIsActive'] is bool) {
          userActive = barberData['userIsActive'] as bool;
        } else {
          final userSnap =
              await tx.get(_users.doc(barberData['userId'] as String));
          userActive = userSnap.data()?['isActive'] as bool? ?? false;
        }

        final attendanceRef = _attendance.doc(docId);
        final existingSnap = await tx.get(attendanceRef);

        // 2. Validations:
        if (barberData['status'] != BarberStatus.active.dbValue || !userActive) {
          throw ValidationFailure(
            message: 'Inactive barber $barberId cannot be checked in.',
            field: 'barberId',
          );
        }
        if (existingSnap.exists) {
          throw DuplicateEntryFailure(
            message:
                'Attendance already recorded for barber $barberId on ${ShopDateUtils.formatIsoDate(normalizedDate)}.',
            field: 'workDate',
            value: ShopDateUtils.formatIsoDate(normalizedDate),
          );
        }

        // 3. Write:
        final attendance = Attendance(
          attendanceId: docId,
          barberId: barberId,
          recordedBy: recordedByStaffId,
          workDate: normalizedDate,
          timeIn: timeIn,
          timeOut: null,
          status: AttendanceStatus.present,
        );
        final dto = AttendanceFirestoreDto.fromDomain(attendance);
        tx.set(attendanceRef, dto.toFirestore());
        return attendance;
      });
    });
  }

  @override
  Future<Result<Attendance>> checkOutBarber({
    required String attendanceId,
    required ShopTime timeOut,
    required String actingStaffId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: actingStaffId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
          tx: tx,
        );

        final attendanceRef = _attendance.doc(attendanceId);
        final snap = await tx.get(attendanceRef);
        if (!snap.exists || snap.data() == null) {
          throw NotFoundFailure(
            message: 'Attendance $attendanceId not found.',
            entityName: 'Attendance',
            entityId: attendanceId,
          );
        }

        final existing =
            AttendanceFirestoreDto.fromFirestore(snap.id, snap.data()!)
                .toDomain();
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

        tx.update(attendanceRef, <String, dynamic>{
          'timeOut': timeOut.toIsoTimeString(),
        });
        return existing.copyWith(timeOut: timeOut);
      });
    });
  }

  @override
  Future<Result<Attendance>> markNonPresent({
    required String barberId,
    required String recordedByStaffId,
    required DateTime workDate,
    required AttendanceStatus status,
  }) {
    return FirestoreErrorMapper.guard(() async {
      if (status == AttendanceStatus.present) {
        throw const ValidationFailure(
          message: 'Use checkInBarber() to record PRESENT attendance.',
          field: 'status',
        );
      }

      final normalizedDate = ShopDateUtils.normalizeDate(workDate);
      final docId =
          FirestoreParseUtils.attendanceDocId(barberId, normalizedDate);

      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: recordedByStaffId,
          allowedRoles: const <RoleName>[RoleName.staff, RoleName.owner],
          tx: tx,
        );

        final barberSnap = await tx.get(_barbers.doc(barberId));
        if (!barberSnap.exists) {
          throw NotFoundFailure(
            message: 'Barber $barberId not found.',
            entityName: 'Barber',
            entityId: barberId,
          );
        }

        final attendanceRef = _attendance.doc(docId);
        final existingSnap = await tx.get(attendanceRef);
        if (existingSnap.exists) {
          throw DuplicateEntryFailure(
            message:
                'Attendance already recorded for barber $barberId on ${ShopDateUtils.formatIsoDate(normalizedDate)}.',
            field: 'workDate',
            value: ShopDateUtils.formatIsoDate(normalizedDate),
          );
        }

        final attendance = Attendance(
          attendanceId: docId,
          barberId: barberId,
          recordedBy: recordedByStaffId,
          workDate: normalizedDate,
          timeIn: null,
          timeOut: null,
          status: status,
        );
        tx.set(
          attendanceRef,
          AttendanceFirestoreDto.fromDomain(attendance).toFirestore(),
        );
        return attendance;
      });
    });
  }

  @override
  Future<Result<Attendance?>> getBarberAttendanceForDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final docId = FirestoreParseUtils.attendanceDocId(barberId, workDate);
      final doc = await _attendance.doc(docId).get();
      if (!doc.exists || doc.data() == null) return null;
      return AttendanceFirestoreDto.fromFirestore(doc.id, doc.data()!)
          .toDomain();
    });
  }

  @override
  Future<Result<bool>> isBarberPresentOnDate({
    required String barberId,
    required DateTime workDate,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final docId = FirestoreParseUtils.attendanceDocId(barberId, workDate);
      final doc = await _attendance.doc(docId).get();
      if (!doc.exists || doc.data() == null) return false;
      final status =
          AttendanceStatus.fromDbValue(doc.data()!['status'] as String);
      return status == AttendanceStatus.present;
    });
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceByDate(DateTime workDate) {
    return FirestoreErrorMapper.guard(() async {
      final isoDate = ShopDateUtils.formatIsoDate(workDate);
      final snap = await _attendance.where('workDate', isEqualTo: isoDate).get();
      final list = snap.docs
          .map(
            (doc) =>
                AttendanceFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
      list.sort(_compareAttendanceByTimeIn);
      return list;
    });
  }

  @override
  Stream<Result<List<Attendance>>> watchAttendanceByDate(DateTime workDate) {
    final isoDate = ShopDateUtils.formatIsoDate(workDate);
    final stream = _attendance
        .where('workDate', isEqualTo: isoDate)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map(
            (doc) =>
                AttendanceFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
      list.sort(_compareAttendanceByTimeIn);
      return list;
    });
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<List<Attendance>>> getAttendanceForBarber({
    required String barberId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final normalizedStart = ShopDateUtils.normalizeDate(startDate);
      final normalizedEnd = ShopDateUtils.normalizeDate(endDate);
      if (normalizedEnd.isBefore(normalizedStart)) {
        throw const ValidationFailure(
          message: 'endDate cannot precede startDate.',
        );
      }

      final snap = await _attendance
          .where('barberId', isEqualTo: barberId)
          .where(
            'workDate',
            isGreaterThanOrEqualTo: ShopDateUtils.formatIsoDate(normalizedStart),
          )
          .where(
            'workDate',
            isLessThanOrEqualTo: ShopDateUtils.formatIsoDate(normalizedEnd),
          )
          .orderBy('workDate')
          .get();

      return snap.docs
          .map(
            (doc) =>
                AttendanceFirestoreDto.fromFirestore(doc.id, doc.data()).toDomain(),
          )
          .toList(growable: false);
    });
  }

  int _compareAttendanceByTimeIn(Attendance a, Attendance b) {
    if (a.timeIn == null && b.timeIn == null) {
      return a.barberId.compareTo(b.barberId);
    }
    if (a.timeIn == null) return 1;
    if (b.timeIn == null) return -1;
    return a.timeIn!.compareTo(b.timeIn!);
  }
}
