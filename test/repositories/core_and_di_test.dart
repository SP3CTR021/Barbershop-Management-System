import 'package:barbershop_management_app/core/barbershop_data_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MoneyMath', () {
    test('splitSales preserves exact centavo sum on odd amounts', () {
      final split = MoneyMath.splitSales(
        grossSales: 100.01,
        ownerSharePct: 60.0,
        barberSharePct: 40.0,
      );
      expect(split.barberPayAmount, 40.0);
      expect(split.ownerShareAmount, 60.01);
      expect(
        MoneyMath.round2(split.ownerShareAmount + split.barberPayAmount),
        100.01,
      );
    });

    test('sharesSumTo100 validates two-decimal splits', () {
      expect(MoneyMath.sharesSumTo100(60.0, 40.0), isTrue);
      expect(MoneyMath.sharesSumTo100(55.55, 44.45), isTrue);
      expect(MoneyMath.sharesSumTo100(60.0, 39.99), isFalse);
    });
  });

  group('ShopTime & ShopDateUtils', () {
    test('ShopTime parses HH:mm and HH:mm:ss.SSSSSS and compares correctly', () {
      final t1 = ShopTime.parse('08:30');
      final t2 = ShopTime.parse('17:45:12.123456');

      expect(t1.toIsoTimeString(), '08:30:00');
      expect(t2.toIsoTimeString(), '17:45:12');
      expect(t1.isBefore(t2), isTrue);
      expect(t2.isAfter(t1), isTrue);
      expect(() => ShopTime.parse('25:00'), throwsFormatException);
    });

    test('ShopDateUtils handles +08:00 UTC day boundaries accurately', () {
      // 2026-11-15T23:30:00Z is 2026-11-16 07:30:00 +08:00.
      final localDate =
          ShopDateUtils.toShopLocalDate(DateTime.utc(2026, 11, 15, 23, 30));
      expect(localDate, DateTime.utc(2026, 11, 16));

      final range = ShopDateUtils.utcRangeForShopDateRange(
        startDate: DateTime.utc(2026, 11, 1),
        endDate: DateTime.utc(2026, 11, 15),
      );
      expect(range.startUtcInclusive, DateTime.utc(2026, 10, 31, 16, 0));
      expect(range.endUtcExclusive, DateTime.utc(2026, 11, 15, 16, 0));
    });
  });

  group('RepositoryLocator DI', () {
    test('configureInMemory registers all 10 domain repository interfaces',
        () async {
      final db = await RepositoryLocator.configureInMemory();
      addTearDown(() async {
        await sl.reset();
        await db.dispose();
      });

      expect(RepositoryLocator.roles, isA<RoleRepository>());
      expect(RepositoryLocator.users, isA<UserRepository>());
      expect(RepositoryLocator.auth, isA<AuthRepository>());
      expect(RepositoryLocator.barbers, isA<BarberRepository>());
      expect(RepositoryLocator.customers, isA<CustomerRepository>());
      expect(RepositoryLocator.services, isA<ServiceRepository>());
      expect(RepositoryLocator.attendance, isA<AttendanceRepository>());
      expect(RepositoryLocator.transactions, isA<TransactionRepository>());
      expect(RepositoryLocator.payments, isA<PaymentRepository>());
      expect(RepositoryLocator.payroll, isA<PayrollRepository>());
    });
  });
}
