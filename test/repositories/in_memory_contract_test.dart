import 'package:barbershop_management_app/core/di/repository_locator.dart';
import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';
import 'package:get_it/get_it.dart';

import '../contracts/attendance_repository_contract.dart';
import '../contracts/auth_repository_contract.dart';
import '../contracts/barber_repository_contract.dart';
import '../contracts/contract_test_harness.dart';
import '../contracts/customer_repository_contract.dart';
import '../contracts/payment_repository_contract.dart';
import '../contracts/payroll_repository_contract.dart';
import '../contracts/role_repository_contract.dart';
import '../contracts/service_repository_contract.dart';
import '../contracts/transaction_repository_contract.dart';
import '../contracts/user_repository_contract.dart';

/// Runs all 10 shared abstract repository contract suites against the fast
/// pure-Dart [InMemoryDatabase] implementation.
///
/// To run these exact same contract suites against a live local Supabase or
/// Firebase Emulator instance, supply a [ContractTestHarness] wired via
/// `RepositoryLocator.configureRepositories(backend: BackendType.supabase, ...)`
/// or `BackendType.firebase`.
void main() {
  Future<ContractTestHarness> createInMemoryHarness() async {
    final locator = GetIt.asNewInstance();
    final db = await RepositoryLocator.configureInMemory(locator: locator);

    return ContractTestHarness(
      roles: locator<RoleRepository>(),
      users: locator<UserRepository>(),
      auth: locator<AuthRepository>(),
      barbers: locator<BarberRepository>(),
      customers: locator<CustomerRepository>(),
      services: locator<ServiceRepository>(),
      attendance: locator<AttendanceRepository>(),
      transactions: locator<TransactionRepository>(),
      payments: locator<PaymentRepository>(),
      payroll: locator<PayrollRepository>(),
      dispose: () async {
        await locator.reset();
        await db.dispose();
      },
    );
  }

  runRoleRepositoryContract(createInMemoryHarness);
  runAuthRepositoryContract(createInMemoryHarness);
  runUserRepositoryContract(createInMemoryHarness);
  runBarberRepositoryContract(createInMemoryHarness);
  runCustomerRepositoryContract(createInMemoryHarness);
  runServiceRepositoryContract(createInMemoryHarness);
  runAttendanceRepositoryContract(createInMemoryHarness);
  runTransactionRepositoryContract(createInMemoryHarness);
  runPaymentRepositoryContract(createInMemoryHarness);
  runPayrollRepositoryContract(createInMemoryHarness);
}
