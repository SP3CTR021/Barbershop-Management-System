import 'package:barbershop_management_app/core/data/supabase/supabase_error_mapper.dart';
import 'package:barbershop_management_app/core/data/supabase/supabase_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/payroll/data/supabase/payroll_period_supabase_dto.dart';
import 'package:barbershop_management_app/features/payroll/data/supabase/payroll_record_supabase_dto.dart';
import 'package:barbershop_management_app/features/payroll/data/supabase/payroll_setting_supabase_dto.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_with_records.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// PostgreSQL implementation of [PayrollRepository] delegating 5-table payroll
/// aggregation (`transactions -> transaction_items -> barbers -> payroll_periods
/// -> payroll_settings`) to `rpc_generate_payroll_period`.
final class SupabasePayrollRepository implements PayrollRepository {
  SupabasePayrollRepository(this._client);

  final sb.SupabaseClient _client;

  @override
  Future<Result<PayrollSetting>> getActivePayrollSetting() {
    return SupabaseErrorMapper.guard(() async {
      final row = await _client
          .from('payroll_settings')
          .select()
          .isFilter('effective_to', null)
          .order('effective_from', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) {
        throw const NotFoundFailure(
          message: 'No active payroll setting is configured.',
          entityName: 'PayrollSetting',
        );
      }
      return PayrollSettingSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<PayrollSetting>>> getPayrollSettingsHistory() {
    return SupabaseErrorMapper.guard(() async {
      final rows = await _client
          .from('payroll_settings')
          .select()
          .order('effective_from', ascending: false);
      return rows
          .map((row) => PayrollSettingSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Future<Result<PayrollSetting>> createPayrollSetting({
    required String createdByOwnerId,
    required double ownerSharePct,
    required double barberSharePct,
    int periodDays = 15,
    required DateTime effectiveFrom,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final settingId = await _client.rpc(
        'rpc_create_payroll_setting',
        params: <String, dynamic>{
          'p_created_by_owner_id': createdByOwnerId,
          'p_owner_share_pct': ownerSharePct,
          'p_barber_share_pct': barberSharePct,
          'p_period_days': periodDays,
          'p_effective_from': ShopDateUtils.formatIsoDate(effectiveFrom),
        },
      );

      final row = await _client
          .from('payroll_settings')
          .select()
          .eq('setting_id', settingId as String)
          .single();
      return PayrollSettingSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> generatePayrollPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required String generatedByUserId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final periodId = await _client.rpc(
        'rpc_generate_payroll_period',
        params: <String, dynamic>{
          'p_start_date': ShopDateUtils.formatIsoDate(startDate),
          'p_end_date': ShopDateUtils.formatIsoDate(endDate),
          'p_generated_by_user_id': generatedByUserId,
        },
      );
      return _fetchPeriodWithRecordsOrThrow(periodId as String);
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> getPayrollPeriodWithRecords(
    String periodId,
  ) {
    return SupabaseErrorMapper.guard(
      () => _fetchPeriodWithRecordsOrThrow(periodId),
    );
  }

  @override
  Future<Result<List<PayrollPeriod>>> getPayrollPeriods({
    PayrollPeriodStatus? status,
  }) {
    return SupabaseErrorMapper.guard(() async {
      var query = _client.from('payroll_periods').select();
      if (status != null) {
        query = query.eq('status', status.dbValue);
      }
      final rows = await query.order('start_date', ascending: false);
      return rows
          .map((row) => PayrollPeriodSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<PayrollPeriod>>> watchPayrollPeriods() {
    final stream = _client
        .from('payroll_periods')
        .stream(primaryKey: <String>['period_id'])
        .order('start_date', ascending: false)
        .map(
          (rows) => rows
              .map(
                (row) => PayrollPeriodSupabaseDto.fromSupabase(row).toDomain(),
              )
              .toList(growable: false),
        );
    return SupabaseErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<PayrollPeriod>> approvePayrollPeriod({
    required String periodId,
    required String ownerUserId,
  }) {
    return SupabaseErrorMapper.guard(() async {
      await SupabaseParseUtils.assertActiveUserRole(
        _client,
        actingUserId: ownerUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final existingRow = await _client
          .from('payroll_periods')
          .select()
          .eq('period_id', periodId)
          .maybeSingle();
      if (existingRow == null) {
        throw NotFoundFailure(
          message: 'Payroll period $periodId not found.',
          entityName: 'PayrollPeriod',
          entityId: periodId,
        );
      }
      final existing =
          PayrollPeriodSupabaseDto.fromSupabase(existingRow).toDomain();
      if (existing.status != PayrollPeriodStatus.draft) {
        throw ConflictFailure(
          message:
              'Only DRAFT payroll periods can be approved (current: ${existing.status.dbValue}).',
        );
      }

      final updated = await _client
          .from('payroll_periods')
          .update(<String, dynamic>{'status': PayrollPeriodStatus.approved.dbValue})
          .eq('period_id', periodId)
          .select()
          .single();
      return PayrollPeriodSupabaseDto.fromSupabase(updated).toDomain();
    });
  }

  @override
  Future<Result<PayrollRecord>> markPayrollRecordPaid({
    required String payrollId,
    required String ownerUserId,
    DateTime? paidAt,
  }) {
    return SupabaseErrorMapper.guard(() async {
      final effectivePaidAt = (paidAt ?? DateTime.now()).toUtc();
      await _client.rpc(
        'rpc_mark_payroll_record_paid',
        params: <String, dynamic>{
          'p_payroll_id': payrollId,
          'p_owner_user_id': ownerUserId,
          'p_paid_at': effectivePaidAt.toIso8601String(),
        },
      );

      final row = await _client
          .from('payroll_records')
          .select()
          .eq('payroll_id', payrollId)
          .single();
      return PayrollRecordSupabaseDto.fromSupabase(row).toDomain();
    });
  }

  @override
  Future<Result<List<PayrollRecord>>> getPayrollRecordsForBarber(
    String barberId,
  ) {
    return SupabaseErrorMapper.guard(() async {
      final rows = await _client
          .from('payroll_records')
          .select('*, payroll_periods!inner(start_date)')
          .eq('barber_id', barberId);

      final sorted = List<Map<String, dynamic>>.from(rows)
        ..sort((a, b) {
          final aStart =
              (a['payroll_periods'] as Map<String, dynamic>)['start_date']
                  as String;
          final bStart =
              (b['payroll_periods'] as Map<String, dynamic>)['start_date']
                  as String;
          return bStart.compareTo(aStart);
        });

      return sorted
          .map((row) => PayrollRecordSupabaseDto.fromSupabase(row).toDomain())
          .toList(growable: false);
    });
  }

  @override
  Future<Result<bool>> isDateLockedByPayroll(DateTime shopDate) {
    return SupabaseErrorMapper.guard(() async {
      final isoDate = ShopDateUtils.formatIsoDate(shopDate);
      final rows = await _client
          .from('payroll_periods')
          .select('period_id')
          .inFilter('status', <String>[
            PayrollPeriodStatus.approved.dbValue,
            PayrollPeriodStatus.paid.dbValue,
          ])
          .lte('start_date', isoDate)
          .gte('end_date', isoDate)
          .limit(1);
      return rows.isNotEmpty;
    });
  }

  Future<PayrollPeriodWithRecords> _fetchPeriodWithRecordsOrThrow(
    String periodId,
  ) async {
    final row = await _client
        .from('payroll_periods')
        .select('*, payroll_settings!inner(*), payroll_records(*)')
        .eq('period_id', periodId)
        .maybeSingle();

    if (row == null) {
      throw NotFoundFailure(
        message: 'Payroll period $periodId not found.',
        entityName: 'PayrollPeriod',
        entityId: periodId,
      );
    }

    final period = PayrollPeriodSupabaseDto.fromSupabase(row).toDomain();
    final setting = PayrollSettingSupabaseDto.fromSupabase(
      row['payroll_settings'] as Map<String, dynamic>,
    ).toDomain();

    final rawRecords = (row['payroll_records'] as List<dynamic>? ?? const []);
    final records = rawRecords
        .map(
          (item) => PayrollRecordSupabaseDto.fromSupabase(
            item as Map<String, dynamic>,
          ).toDomain(),
        )
        .toList(growable: false)
      ..sort((a, b) => a.barberId.compareTo(b.barberId));

    return PayrollPeriodWithRecords(
      period: period,
      setting: setting,
      records: records,
    );
  }
}
