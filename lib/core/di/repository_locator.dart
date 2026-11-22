import 'package:barbershop_management_app/core/config/backend_config.dart';
import 'package:barbershop_management_app/core/config/backend_initializer.dart';
import 'package:barbershop_management_app/core/data/fake/in_memory_database.dart';
import 'package:barbershop_management_app/features/attendance/data/fake/in_memory_attendance_repository.dart';
import 'package:barbershop_management_app/features/attendance/data/firestore/firestore_attendance_repository.dart';
import 'package:barbershop_management_app/features/attendance/data/supabase/supabase_attendance_repository.dart';
import 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:barbershop_management_app/features/barbers/data/fake/in_memory_barber_repository.dart';
import 'package:barbershop_management_app/features/barbers/data/firestore/firestore_barber_repository.dart';
import 'package:barbershop_management_app/features/barbers/data/supabase/supabase_barber_repository.dart';
import 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';
import 'package:barbershop_management_app/features/customers/data/fake/in_memory_customer_repository.dart';
import 'package:barbershop_management_app/features/customers/data/firestore/firestore_customer_repository.dart';
import 'package:barbershop_management_app/features/customers/data/supabase/supabase_customer_repository.dart';
import 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';
import 'package:barbershop_management_app/features/payroll/data/fake/in_memory_payroll_repository.dart';
import 'package:barbershop_management_app/features/payroll/data/firestore/firestore_payroll_repository.dart';
import 'package:barbershop_management_app/features/payroll/data/supabase/supabase_payroll_repository.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/services/data/fake/in_memory_service_repository.dart';
import 'package:barbershop_management_app/features/services/data/firestore/firestore_service_repository.dart';
import 'package:barbershop_management_app/features/services/data/supabase/supabase_service_repository.dart';
import 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/fake/in_memory_payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/fake/in_memory_transaction_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/firestore_payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/firestore/firestore_transaction_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/supabase_payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/data/supabase/supabase_transaction_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
import 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:barbershop_management_app/features/users/data/fake/in_memory_auth_repository.dart';
import 'package:barbershop_management_app/features/users/data/fake/in_memory_role_repository.dart';
import 'package:barbershop_management_app/features/users/data/fake/in_memory_user_repository.dart';
import 'package:barbershop_management_app/features/users/data/firestore/firestore_auth_repository.dart';
import 'package:barbershop_management_app/features/users/data/firestore/firestore_role_repository.dart';
import 'package:barbershop_management_app/features/users/data/firestore/firestore_user_repository.dart';
import 'package:barbershop_management_app/features/users/data/supabase/supabase_auth_repository.dart';
import 'package:barbershop_management_app/features/users/data/supabase/supabase_role_repository.dart';
import 'package:barbershop_management_app/features/users/data/supabase/supabase_user_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
import 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

export 'package:barbershop_management_app/core/config/backend_config.dart'
    show BackendType;

/// ============================================================================
/// SINGLE-LINE BACKEND SWITCH
/// Change ONLY this line between [BackendType.supabase] and [BackendType.firebase]
/// to switch the entire data layer with zero changes to Domain, ViewModels, or UI.
/// ============================================================================
const BackendType activeBackend = BackendType.supabase;

/// Global service locator exposing only domain repository abstractions.
final GetIt sl = GetIt.instance;

/// Initializes the selected backend SDK and registers all 10 domain repository
/// interfaces in [GetIt].
///
/// Typical `main()` usage:
/// ```dart
/// Future<void> main() async {
///   await RepositoryLocator.bootstrap();
///   runApp(const MyApp());
/// }
/// ```
abstract final class RepositoryLocator {
  static Future<void> bootstrap({
    BackendType backend = activeBackend,
    SupabaseConfig supabase = const SupabaseConfig.fromEnvironment(),
    FirebaseConfig firebase = const FirebaseConfig(),
    bool ensureFlutterBinding = true,
  }) async {
    await BackendInitializer.initialize(
      backend: backend,
      supabase: supabase,
      firebase: firebase,
      ensureFlutterBinding: ensureFlutterBinding,
    );
    await configureRepositories(backend: backend);
  }

  static Future<void> configureRepositories({
    BackendType backend = activeBackend,
    GetIt? locator,
    sb.SupabaseClient? supabaseClient,
    fs.FirebaseFirestore? firestore,
    fa.FirebaseAuth? firebaseAuth,
  }) async {
    final target = locator ?? sl;
    await target.reset();
    target.registerSingleton<BackendType>(backend);

    switch (backend) {
      case BackendType.supabase:
        final client = supabaseClient ?? sb.Supabase.instance.client;
        target
          ..registerLazySingleton<RoleRepository>(
            () => SupabaseRoleRepository(client),
          )
          ..registerLazySingleton<UserRepository>(
            () => SupabaseUserRepository(client),
          )
          ..registerLazySingleton<AuthRepository>(
            () => SupabaseAuthRepository(client),
          )
          ..registerLazySingleton<BarberRepository>(
            () => SupabaseBarberRepository(client),
          )
          ..registerLazySingleton<CustomerRepository>(
            () => SupabaseCustomerRepository(client),
          )
          ..registerLazySingleton<ServiceRepository>(
            () => SupabaseServiceRepository(client),
          )
          ..registerLazySingleton<AttendanceRepository>(
            () => SupabaseAttendanceRepository(client),
          )
          ..registerLazySingleton<TransactionRepository>(
            () => SupabaseTransactionRepository(client),
          )
          ..registerLazySingleton<PaymentRepository>(
            () => SupabasePaymentRepository(client),
          )
          ..registerLazySingleton<PayrollRepository>(
            () => SupabasePayrollRepository(client),
          );

      case BackendType.firebase:
        final db = firestore ?? fs.FirebaseFirestore.instance;
        final auth = firebaseAuth ?? fa.FirebaseAuth.instance;
        target
          ..registerLazySingleton<RoleRepository>(
            () => FirestoreRoleRepository(db),
          )
          ..registerLazySingleton<UserRepository>(
            () => FirestoreUserRepository(db),
          )
          ..registerLazySingleton<AuthRepository>(
            () => FirestoreAuthRepository(auth, db),
          )
          ..registerLazySingleton<BarberRepository>(
            () => FirestoreBarberRepository(db),
          )
          ..registerLazySingleton<CustomerRepository>(
            () => FirestoreCustomerRepository(db),
          )
          ..registerLazySingleton<ServiceRepository>(
            () => FirestoreServiceRepository(db),
          )
          ..registerLazySingleton<AttendanceRepository>(
            () => FirestoreAttendanceRepository(db),
          )
          ..registerLazySingleton<TransactionRepository>(
            () => FirestoreTransactionRepository(db),
          )
          ..registerLazySingleton<PaymentRepository>(
            () => FirestorePaymentRepository(db),
          )
          ..registerLazySingleton<PayrollRepository>(
            () => FirestorePayrollRepository(db),
          );
    }
  }

  /// Registers fast pure-Dart in-memory fakes for unit & contract tests without
  /// touching Supabase or Firebase SDKs.
  static Future<InMemoryDatabase> configureInMemory({
    InMemoryDatabase? database,
    GetIt? locator,
  }) async {
    final target = locator ?? sl;
    final db = database ?? InMemoryDatabase();
    await target.reset();
    target
      ..registerSingleton<InMemoryDatabase>(db)
      ..registerLazySingleton<RoleRepository>(() => InMemoryRoleRepository(db))
      ..registerLazySingleton<UserRepository>(() => InMemoryUserRepository(db))
      ..registerLazySingleton<AuthRepository>(() => InMemoryAuthRepository(db))
      ..registerLazySingleton<BarberRepository>(
        () => InMemoryBarberRepository(db),
      )
      ..registerLazySingleton<CustomerRepository>(
        () => InMemoryCustomerRepository(db),
      )
      ..registerLazySingleton<ServiceRepository>(
        () => InMemoryServiceRepository(db),
      )
      ..registerLazySingleton<AttendanceRepository>(
        () => InMemoryAttendanceRepository(db),
      )
      ..registerLazySingleton<TransactionRepository>(
        () => InMemoryTransactionRepository(db),
      )
      ..registerLazySingleton<PaymentRepository>(
        () => InMemoryPaymentRepository(db),
      )
      ..registerLazySingleton<PayrollRepository>(
        () => InMemoryPayrollRepository(db),
      );
    return db;
  }

  static BackendType get currentBackend => sl<BackendType>();
  static RoleRepository get roles => sl<RoleRepository>();
  static UserRepository get users => sl<UserRepository>();
  static AuthRepository get auth => sl<AuthRepository>();
  static BarberRepository get barbers => sl<BarberRepository>();
  static CustomerRepository get customers => sl<CustomerRepository>();
  static ServiceRepository get services => sl<ServiceRepository>();
  static AttendanceRepository get attendance => sl<AttendanceRepository>();
  static TransactionRepository get transactions => sl<TransactionRepository>();
  static PaymentRepository get payments => sl<PaymentRepository>();
  static PayrollRepository get payroll => sl<PayrollRepository>();
}
