import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/services/domain/models/service.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:barbershop_management_app/features/users/domain/models/user.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';

/// Baseline shop entities seeded strictly through abstract domain repositories.
final class SeededShopFixture {
  const SeededShopFixture({
    required this.owner,
    required this.staff,
    required this.barber,
    required this.haircutService,
    required this.shaveService,
  });

  final User owner;
  final User staff;
  final BarberWithUser barber;
  final Service haircutService;
  final Service shaveService;
}

/// Backend-agnostic harness used by every shared repository contract suite.
///
/// Any implementation (In-Memory, Supabase, or Firebase Emulator) that builds
/// this harness can run all 10 contract test suites unchanged.
final class ContractTestHarness {
  const ContractTestHarness({
    required this.roles,
    required this.users,
    required this.auth,
    required this.barbers,
    required this.customers,
    required this.services,
    required this.attendance,
    required this.transactions,
    required this.payments,
    required this.payroll,
    required this.dispose,
  });

  final RoleRepository roles;
  final UserRepository users;
  final AuthRepository auth;
  final BarberRepository barbers;
  final CustomerRepository customers;
  final ServiceRepository services;
  final AttendanceRepository attendance;
  final TransactionRepository transactions;
  final PaymentRepository payments;
  final PayrollRepository payroll;
  final Future<void> Function() dispose;

  Future<SeededShopFixture> seedShopFixture() async {
    (await roles.seedDefaultRoles()).getOrThrow();

    final owner = (await auth.registerLoginAccount(
      roleName: RoleName.owner,
      firstName: 'Elena',
      lastName: 'Reyes',
      username: 'owner_elena',
      email: 'owner@shop.test',
      password: 'Password123!',
    ))
        .getOrThrow();

    final staff = (await auth.registerLoginAccount(
      roleName: RoleName.staff,
      firstName: 'Carlo',
      lastName: 'Mendoza',
      username: 'staff_carlo',
      email: 'staff@shop.test',
      password: 'Password123!',
      createdByOwnerId: owner.userId,
    ))
        .getOrThrow();

    final barber = (await barbers.createBarberWithProfile(
      firstName: 'Mark',
      lastName: 'Santos',
      username: 'barber_mark',
      hireDate: DateTime.utc(2026, 1, 10),
      specialty: 'Fades & Classic Cuts',
      actingOwnerId: owner.userId,
    ))
        .getOrThrow();

    final haircutService = (await services.createService(
      serviceName: 'Classic Haircut',
      isHaircut: true,
      price: 150.0,
      actingOwnerId: owner.userId,
    ))
        .getOrThrow();

    final shaveService = (await services.createService(
      serviceName: 'Beard Trim',
      isHaircut: false,
      price: 100.0,
      actingOwnerId: owner.userId,
    ))
        .getOrThrow();

    return SeededShopFixture(
      owner: owner,
      staff: staff,
      barber: barber,
      haircutService: haircutService,
      shaveService: shaveService,
    );
  }
}
