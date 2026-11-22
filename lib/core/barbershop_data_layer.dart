/// Public barrel for ViewModels and UI.
///
/// Deliberately exports ONLY core types, DI wiring, pure-Dart domain models,
/// enums, domain services, and abstract repository interfaces — never concrete
/// Supabase or Firestore classes/DTOs.
library;

// Core errors, types & utils
export 'package:barbershop_management_app/core/errors/app_failure.dart';
export 'package:barbershop_management_app/core/types/result.dart';
export 'package:barbershop_management_app/core/types/shop_time.dart';
export 'package:barbershop_management_app/core/utils/money_math.dart';
export 'package:barbershop_management_app/core/utils/shop_date_utils.dart';

// Config & DI
export 'package:barbershop_management_app/core/config/backend_config.dart';
export 'package:barbershop_management_app/core/config/backend_initializer.dart';
export 'package:barbershop_management_app/core/di/repository_locator.dart';

// Users & Auth domain
export 'package:barbershop_management_app/features/users/domain/models/role.dart';
export 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
export 'package:barbershop_management_app/features/users/domain/models/user.dart';
export 'package:barbershop_management_app/features/users/domain/repositories/auth_repository.dart';
export 'package:barbershop_management_app/features/users/domain/repositories/role_repository.dart';
export 'package:barbershop_management_app/features/users/domain/repositories/user_repository.dart';

// Barbers domain
export 'package:barbershop_management_app/features/barbers/domain/models/barber.dart';
export 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
export 'package:barbershop_management_app/features/barbers/domain/models/barber_with_user.dart';
export 'package:barbershop_management_app/features/barbers/domain/repositories/barber_repository.dart';

// Customers domain
export 'package:barbershop_management_app/features/customers/domain/models/customer.dart';
export 'package:barbershop_management_app/features/customers/domain/repositories/customer_repository.dart';

// Services domain
export 'package:barbershop_management_app/features/services/domain/models/service.dart';
export 'package:barbershop_management_app/features/services/domain/repositories/service_repository.dart';

// Attendance domain
export 'package:barbershop_management_app/features/attendance/domain/models/attendance.dart';
export 'package:barbershop_management_app/features/attendance/domain/models/attendance_status.dart';
export 'package:barbershop_management_app/features/attendance/domain/repositories/attendance_repository.dart';

// Transactions & Payments domain
export 'package:barbershop_management_app/features/transactions/domain/models/payment.dart';
export 'package:barbershop_management_app/features/transactions/domain/models/payment_method.dart';
export 'package:barbershop_management_app/features/transactions/domain/models/transaction.dart';
export 'package:barbershop_management_app/features/transactions/domain/models/transaction_item.dart';
export 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
export 'package:barbershop_management_app/features/transactions/domain/models/transaction_with_details.dart';
export 'package:barbershop_management_app/features/transactions/domain/repositories/payment_repository.dart';
export 'package:barbershop_management_app/features/transactions/domain/repositories/transaction_repository.dart';

// Payroll domain
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_with_records.dart';
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
export 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
export 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
export 'package:barbershop_management_app/features/payroll/domain/services/payroll_calculator.dart';
