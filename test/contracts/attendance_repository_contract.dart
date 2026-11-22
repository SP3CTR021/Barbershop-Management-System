import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/shop_time.dart';
import 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'contract_test_harness.dart';

void runAttendanceRepositoryContract(
  Future<ContractTestHarness> Function() createHarness,
) {
  group('AttendanceRepository contract', () {
    test('checkInBarber, duplicate date guard, checkOut validation, and queries',
        () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      final day1 = DateTime.utc(2026, 11, 12);

      expect(
        (await harness.attendance.isBarberPresentOnDate(
          barberId: fixture.barber.barberId,
          workDate: day1,
        ))
            .getOrThrow(),
        isFalse,
      );

      final checkedIn = (await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: day1,
        timeIn: const ShopTime(hour: 9, minute: 0),
      ))
          .getOrThrow();
      expect(checkedIn.status, AttendanceStatus.present);
      expect(checkedIn.timeIn, const ShopTime(hour: 9, minute: 0));
      expect(checkedIn.timeOut, isNull);

      expect(
        (await harness.attendance.isBarberPresentOnDate(
          barberId: fixture.barber.barberId,
          workDate: day1,
        ))
            .getOrThrow(),
        isTrue,
      );

      final duplicate = await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: day1,
        timeIn: const ShopTime(hour: 10, minute: 0),
      );
      expect(duplicate.failureOrNull, isA<DuplicateEntryFailure>());

      final badCheckout = await harness.attendance.checkOutBarber(
        attendanceId: checkedIn.attendanceId,
        timeOut: const ShopTime(hour: 8, minute: 30),
        actingStaffId: fixture.staff.userId,
      );
      expect(badCheckout.failureOrNull, isA<ValidationFailure>());

      final checkedOut = (await harness.attendance.checkOutBarber(
        attendanceId: checkedIn.attendanceId,
        timeOut: const ShopTime(hour: 18, minute: 0),
        actingStaffId: fixture.staff.userId,
      ))
          .getOrThrow();
      expect(checkedOut.timeOut, const ShopTime(hour: 18, minute: 0));

      final day2 = DateTime.utc(2026, 11, 13);
      final leave = (await harness.attendance.markNonPresent(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: day2,
        status: AttendanceStatus.leave,
      ))
          .getOrThrow();
      expect(leave.status, AttendanceStatus.leave);
      expect(leave.timeIn, isNull);

      final invalidPresentViaMark = await harness.attendance.markNonPresent(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: DateTime.utc(2026, 11, 14),
        status: AttendanceStatus.present,
      );
      expect(invalidPresentViaMark.failureOrNull, isA<ValidationFailure>());

      final history = (await harness.attendance.getAttendanceForBarber(
        barberId: fixture.barber.barberId,
        startDate: day1,
        endDate: day2,
      ))
          .getOrThrow();
      expect(history.length, 2);
      expect((await harness.attendance.getAttendanceByDate(day1)).getOrThrow().length, 1);
    });

    test('rejects checking in an inactive barber', () async {
      final harness = await createHarness();
      addTearDown(harness.dispose);

      final fixture = await harness.seedShopFixture();
      (await harness.barbers.setBarberStatus(
        barberId: fixture.barber.barberId,
        status: BarberStatus.inactive,
        actingOwnerId: fixture.owner.userId,
      ))
          .getOrThrow();

      final res = await harness.attendance.checkInBarber(
        barberId: fixture.barber.barberId,
        recordedByStaffId: fixture.staff.userId,
        workDate: DateTime.utc(2026, 11, 14),
        timeIn: const ShopTime(hour: 9, minute: 0),
      );
      expect(res.failureOrNull, isA<ValidationFailure>());
    });
  });
}
