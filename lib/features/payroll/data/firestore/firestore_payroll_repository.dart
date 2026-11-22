import 'package:barbershop_management_app/core/data/firestore/firestore_error_mapper.dart';
import 'package:barbershop_management_app/core/data/firestore/firestore_parse_utils.dart';
import 'package:barbershop_management_app/core/errors/app_failure.dart';
import 'package:barbershop_management_app/core/types/result.dart';
import 'package:barbershop_management_app/core/utils/money_math.dart';
import 'package:barbershop_management_app/core/utils/shop_date_utils.dart';
import 'package:barbershop_management_app/features/barbers/domain/models/barber_status.dart';
import 'package:barbershop_management_app/features/payroll/data/firestore/payroll_period_firestore_dto.dart';
import 'package:barbershop_management_app/features/payroll/data/firestore/payroll_record_firestore_dto.dart';
import 'package:barbershop_management_app/features/payroll/data/firestore/payroll_setting_firestore_dto.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_period_with_records.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_record_status.dart';
import 'package:barbershop_management_app/features/payroll/domain/models/payroll_setting.dart';
import 'package:barbershop_management_app/features/payroll/domain/repositories/payroll_repository.dart';
import 'package:barbershop_management_app/features/payroll/domain/services/payroll_calculator.dart';
import 'package:barbershop_management_app/features/transactions/domain/models/transaction_status.dart';
import 'package:barbershop_management_app/features/users/domain/models/role_name.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:uuid/uuid.dart';

/// Cloud Firestore implementation of [PayrollRepository].
///
/// Firestore workarounds implemented here:
/// - `_unique_constraints/active_payroll_setting` ensures at most one active
///   `payroll_settings` doc (`effectiveTo == null`) inside `runTransaction`.
/// - `generatePayrollPeriod` queries `PAID` `transactions` once using the
///   denormalized `haircutCount` & `haircutGrossSales` summary fields (avoiding
///   500+ subcollection reads) and delegates split math to [PayrollCalculator].
/// - Deterministic join doc IDs `payroll_records/{periodId}_{barberId}` enforce
///   `UNIQUE (period_id, barber_id)` and support queries by period or barber.
final class FirestorePayrollRepository implements PayrollRepository {
  FirestorePayrollRepository(this._firestore, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final fs.FirebaseFirestore _firestore;
  final Uuid _uuid;

  fs.CollectionReference<Map<String, dynamic>> get _settings =>
      _firestore.collection('payroll_settings');
  fs.CollectionReference<Map<String, dynamic>> get _periods =>
      _firestore.collection('payroll_periods');
  fs.CollectionReference<Map<String, dynamic>> get _records =>
      _firestore.collection('payroll_records');
  fs.CollectionReference<Map<String, dynamic>> get _barbers =>
      _firestore.collection('barbers');
  fs.CollectionReference<Map<String, dynamic>> get _transactions =>
      _firestore.collection('transactions');
  fs.CollectionReference<Map<String, dynamic>> get _locks =>
      _firestore.collection(FirestoreParseUtils.uniqueConstraintsCollection);

  @override
  Future<Result<PayrollSetting>> getActivePayrollSetting() {
    return FirestoreErrorMapper.guard(() async {
      final setting = await _findActiveSetting();
      if (setting == null) {
        throw const NotFoundFailure(
          message: 'No active payroll setting is configured.',
          entityName: 'PayrollSetting',
        );
      }
      return setting;
    });
  }

  @override
  Future<Result<List<PayrollSetting>>> getPayrollSettingsHistory() {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _settings
          .orderBy('effectiveFrom', descending: true)
          .get();
      return snap.docs
          .map(
            (doc) =>
                PayrollSettingFirestoreDto.fromFirestore(doc.id, doc.data())
                    .toDomain(),
          )
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
    return FirestoreErrorMapper.guard(() async {
      final roundedOwner = MoneyMath.round2(ownerSharePct);
      final roundedBarber = MoneyMath.round2(barberSharePct);
      if (roundedOwner < 0 ||
          roundedBarber < 0 ||
          !MoneyMath.sharesSumTo100(roundedOwner, roundedBarber)) {
        throw const ValidationFailure(
          message: 'Owner and barber share percentages must sum to 100.00.',
        );
      }
      if (periodDays <= 0) {
        throw const ValidationFailure(
          message: 'periodDays must be greater than zero.',
          field: 'periodDays',
        );
      }

      final normalizedEffectiveFrom =
          ShopDateUtils.normalizeDate(effectiveFrom);
      final newSettingId = _uuid.v4();

      return _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: createdByOwnerId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final activeLockRef =
            _locks.doc(FirestoreParseUtils.activePayrollSettingLockId);
        final activeLockSnap = await tx.get(activeLockRef);

        fs.DocumentReference<Map<String, dynamic>>? prevRef;
        fs.DocumentSnapshot<Map<String, dynamic>>? prevSnap;
        if (activeLockSnap.exists && activeLockSnap.data() != null) {
          final prevId = activeLockSnap.data()!['settingId'] as String?;
          if (prevId != null && prevId.isNotEmpty) {
            prevRef = _settings.doc(prevId);
            prevSnap = await tx.get(prevRef);
          }
        }

        // 2. Writes:
        if (prevRef != null &&
            prevSnap != null &&
            prevSnap.exists &&
            prevSnap.data() != null) {
          final prev = PayrollSettingFirestoreDto.fromFirestore(
            prevSnap.id,
            prevSnap.data()!,
          ).toDomain();
          final dayBefore =
              normalizedEffectiveFrom.subtract(const Duration(days: 1));
          final closedEffectiveTo = dayBefore.isBefore(prev.effectiveFrom)
              ? prev.effectiveFrom
              : dayBefore;
          tx.update(prevRef, <String, dynamic>{
            'effectiveTo': ShopDateUtils.formatIsoDate(closedEffectiveTo),
          });
        }

        final newSetting = PayrollSetting(
          settingId: newSettingId,
          createdBy: createdByOwnerId,
          ownerSharePct: roundedOwner,
          barberSharePct: roundedBarber,
          periodDays: periodDays,
          effectiveFrom: normalizedEffectiveFrom,
          effectiveTo: null,
        );

        tx.set(
          _settings.doc(newSettingId),
          PayrollSettingFirestoreDto.fromDomain(newSetting).toFirestore(),
        );
        tx.set(activeLockRef, <String, dynamic>{'settingId': newSettingId});

        return newSetting;
      });
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> generatePayrollPeriod({
    required DateTime startDate,
    required DateTime endDate,
    required String generatedByUserId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      await FirestoreParseUtils.assertActiveUserRole(
        _firestore,
        actingUserId: generatedByUserId,
        allowedRoles: const <RoleName>[RoleName.owner],
      );

      final normalizedStart = ShopDateUtils.normalizeDate(startDate);
      final normalizedEnd = ShopDateUtils.normalizeDate(endDate);
      if (normalizedEnd.isBefore(normalizedStart)) {
        throw const ValidationFailure(
          message: 'endDate cannot precede startDate.',
        );
      }

      final activeSetting = await _findActiveSetting();
      if (activeSetting == null) {
        throw const NotFoundFailure(
          message: 'No active payroll setting is configured.',
          entityName: 'PayrollSetting',
        );
      }

      // Check for overlapping payroll periods (emulates SQL EXCLUDE constraint).
      final existingPeriodsSnap = await _periods.get();
      for (final doc in existingPeriodsSnap.docs) {
        final existing =
            PayrollPeriodFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain();
        final overlaps = !normalizedEnd.isBefore(existing.startDate) &&
            !normalizedStart.isAfter(existing.endDate);
        if (overlaps) {
          throw ConflictFailure(
            message:
                'Payroll period ${ShopDateUtils.formatIsoDate(normalizedStart)}..${ShopDateUtils.formatIsoDate(normalizedEnd)} overlaps an existing period.',
          );
        }
      }

      // Gather active barbers + single-query PAID transactions in the window.
      final activeBarbersSnap = await _barbers
          .where('status', isEqualTo: BarberStatus.active.dbValue)
          .get();
      final activeBarberIds =
          activeBarbersSnap.docs.map((doc) => doc.id).toSet();

      final utcRange = ShopDateUtils.utcRangeForShopDateRange(
        startDate: normalizedStart,
        endDate: normalizedEnd,
      );
      final paidTxSnap = await _transactions
          .where('status', isEqualTo: TransactionStatus.paid.dbValue)
          .where(
            'transactionDate',
            isGreaterThanOrEqualTo:
                fs.Timestamp.fromDate(utcRange.startUtcInclusive),
          )
          .where(
            'transactionDate',
            isLessThan: fs.Timestamp.fromDate(utcRange.endUtcExclusive),
          )
          .get();

      final haircutsByBarber = <String, int>{};
      final centavosByBarber = <String, int>{};

      for (final txDoc in paidTxSnap.docs) {
        final data = txDoc.data();
        final barberId = data['barberId'] as String;

        int txHaircuts;
        int txHaircutCentavos;
        if (data['haircutCount'] != null && data['haircutGrossSales'] != null) {
          txHaircuts = FirestoreParseUtils.parseInt(data['haircutCount']);
          txHaircutCentavos = MoneyMath.toCentavos(
            FirestoreParseUtils.parseDecimal(data['haircutGrossSales']),
          );
        } else {
          // Fallback if a doc was seeded without denormalized haircut totals.
          final itemsSnap = await txDoc.reference.collection('items').get();
          txHaircuts = 0;
          txHaircutCentavos = 0;
          for (final itemDoc in itemsSnap.docs) {
            final itemData = itemDoc.data();
            if (itemData['isHaircut'] == true) {
              txHaircuts += FirestoreParseUtils.parseInt(itemData['quantity']);
              txHaircutCentavos += MoneyMath.toCentavos(
                FirestoreParseUtils.parseDecimal(itemData['subtotal']),
              );
            }
          }
        }

        haircutsByBarber[barberId] =
            (haircutsByBarber[barberId] ?? 0) + txHaircuts;
        centavosByBarber[barberId] =
            (centavosByBarber[barberId] ?? 0) + txHaircutCentavos;
      }

      final summaries = <String, BarberSalesSummary>{};
      for (final barberId in haircutsByBarber.keys) {
        summaries[barberId] = BarberSalesSummary(
          barberId: barberId,
          totalHaircuts: haircutsByBarber[barberId] ?? 0,
          grossSales: MoneyMath.fromCentavos(centavosByBarber[barberId] ?? 0),
        );
      }

      final periodId = _uuid.v4();
      final period = PayrollPeriod(
        periodId: periodId,
        settingId: activeSetting.settingId,
        generatedBy: generatedByUserId,
        startDate: normalizedStart,
        endDate: normalizedEnd,
        status: PayrollPeriodStatus.draft,
        generatedAt: DateTime.now().toUtc(),
      );

      final records = PayrollCalculator.computeFromSummaries(
        periodId: periodId,
        setting: activeSetting,
        summariesByBarberId: summaries,
        barberIdsToInclude: activeBarberIds,
        payrollIdGenerator: (barberId) =>
            FirestoreParseUtils.payrollRecordDocId(periodId, barberId),
      );

      // Persist period header and all barber records in WriteBatches.
      const maxOpsPerBatch = 450;
      var batch = _firestore.batch();
      batch.set(
        _periods.doc(periodId),
        PayrollPeriodFirestoreDto.fromDomain(period).toFirestore(),
      );
      var opCount = 1;

      for (final record in records) {
        final dto = PayrollRecordFirestoreDto.fromDomain(
          record,
          periodStartDate: normalizedStart,
        );
        batch.set(_records.doc(record.payrollId), dto.toFirestore());
        opCount++;
        if (opCount >= maxOpsPerBatch) {
          await batch.commit();
          batch = _firestore.batch();
          opCount = 0;
        }
      }
      if (opCount > 0) {
        await batch.commit();
      }

      return PayrollPeriodWithRecords(
        period: period,
        setting: activeSetting,
        records: records,
      );
    });
  }

  @override
  Future<Result<PayrollPeriodWithRecords>> getPayrollPeriodWithRecords(
    String periodId,
  ) {
    return FirestoreErrorMapper.guard(() async {
      final periodDoc = await _periods.doc(periodId).get();
      if (!periodDoc.exists || periodDoc.data() == null) {
        throw NotFoundFailure(
          message: 'Payroll period $periodId not found.',
          entityName: 'PayrollPeriod',
          entityId: periodId,
        );
      }

      final period = PayrollPeriodFirestoreDto.fromFirestore(
        periodDoc.id,
        periodDoc.data()!,
      ).toDomain();

      final settingDoc = await _settings.doc(period.settingId).get();
      if (!settingDoc.exists || settingDoc.data() == null) {
        throw NotFoundFailure(
          message: 'Payroll setting ${period.settingId} not found.',
          entityName: 'PayrollSetting',
          entityId: period.settingId,
        );
      }
      final setting = PayrollSettingFirestoreDto.fromFirestore(
        settingDoc.id,
        settingDoc.data()!,
      ).toDomain();

      final recordsSnap =
          await _records.where('periodId', isEqualTo: periodId).get();
      final records = recordsSnap.docs
          .map(
            (doc) => PayrollRecordFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false)
        ..sort((a, b) => a.barberId.compareTo(b.barberId));

      return PayrollPeriodWithRecords(
        period: period,
        setting: setting,
        records: records,
      );
    });
  }

  @override
  Future<Result<List<PayrollPeriod>>> getPayrollPeriods({
    PayrollPeriodStatus? status,
  }) {
    return FirestoreErrorMapper.guard(() async {
      fs.Query<Map<String, dynamic>> query = _periods;
      if (status != null) {
        query = query.where('status', isEqualTo: status.dbValue);
      }
      final snap = await query.orderBy('startDate', descending: true).get();
      return snap.docs
          .map(
            (doc) => PayrollPeriodFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false);
    });
  }

  @override
  Stream<Result<List<PayrollPeriod>>> watchPayrollPeriods() {
    final stream = _periods
        .orderBy('startDate', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(
                (doc) =>
                    PayrollPeriodFirestoreDto.fromFirestore(doc.id, doc.data())
                        .toDomain(),
              )
              .toList(growable: false),
        );
    return FirestoreErrorMapper.guardStream(stream);
  }

  @override
  Future<Result<PayrollPeriod>> approvePayrollPeriod({
    required String periodId,
    required String ownerUserId,
  }) {
    return FirestoreErrorMapper.guard(() async {
      return _firestore.runTransaction((tx) async {
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: ownerUserId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final periodRef = _periods.doc(periodId);
        final periodSnap = await tx.get(periodRef);
        if (!periodSnap.exists || periodSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Payroll period $periodId not found.',
            entityName: 'PayrollPeriod',
            entityId: periodId,
          );
        }

        final existing = PayrollPeriodFirestoreDto.fromFirestore(
          periodSnap.id,
          periodSnap.data()!,
        ).toDomain();
        if (existing.status != PayrollPeriodStatus.draft) {
          throw ConflictFailure(
            message:
                'Only DRAFT payroll periods can be approved (current: ${existing.status.dbValue}).',
          );
        }

        tx.update(periodRef, <String, dynamic>{
          'status': PayrollPeriodStatus.approved.dbValue,
        });
        return existing.copyWith(status: PayrollPeriodStatus.approved);
      });
    });
  }

  @override
  Future<Result<PayrollRecord>> markPayrollRecordPaid({
    required String payrollId,
    required String ownerUserId,
    DateTime? paidAt,
  }) {
    return FirestoreErrorMapper.guard(() async {
      final effectivePaidAt = (paidAt ?? DateTime.now()).toUtc();

      final updatedRecord = await _firestore.runTransaction((tx) async {
        // 1. All reads before writes:
        await FirestoreParseUtils.assertActiveUserRole(
          _firestore,
          actingUserId: ownerUserId,
          allowedRoles: const <RoleName>[RoleName.owner],
          tx: tx,
        );

        final recordRef = _records.doc(payrollId);
        final recordSnap = await tx.get(recordRef);
        if (!recordSnap.exists || recordSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Payroll record $payrollId not found.',
            entityName: 'PayrollRecord',
            entityId: payrollId,
          );
        }

        final existing = PayrollRecordFirestoreDto.fromFirestore(
          recordSnap.id,
          recordSnap.data()!,
        ).toDomain();

        final periodRef = _periods.doc(existing.periodId);
        final periodSnap = await tx.get(periodRef);
        if (!periodSnap.exists || periodSnap.data() == null) {
          throw NotFoundFailure(
            message: 'Payroll period ${existing.periodId} not found.',
            entityName: 'PayrollPeriod',
            entityId: existing.periodId,
          );
        }
        final period = PayrollPeriodFirestoreDto.fromFirestore(
          periodSnap.id,
          periodSnap.data()!,
        ).toDomain();

        // 2. Validations:
        if (period.status != PayrollPeriodStatus.approved &&
            period.status != PayrollPeriodStatus.paid) {
          throw const ValidationFailure(
            message:
                'Payroll period must be APPROVED before paying barbers.',
          );
        }
        if (existing.status == PayrollRecordStatus.paid) {
          throw ConflictFailure(
            message: 'Payroll record $payrollId is already marked PAID.',
          );
        }

        // 3. Write:
        tx.update(recordRef, <String, dynamic>{
          'status': PayrollRecordStatus.paid.dbValue,
          'paidAt': fs.Timestamp.fromDate(effectivePaidAt),
        });
        return existing.copyWith(
          status: PayrollRecordStatus.paid,
          paidAt: effectivePaidAt,
        );
      });

      // Auto-transition parent period to PAID once zero PENDING records remain.
      final remainingPending = await _records
          .where('periodId', isEqualTo: updatedRecord.periodId)
          .where('status', isEqualTo: PayrollRecordStatus.pending.dbValue)
          .limit(1)
          .get();

      if (remainingPending.docs.isEmpty) {
        await _periods.doc(updatedRecord.periodId).update(<String, dynamic>{
          'status': PayrollPeriodStatus.paid.dbValue,
        });
      }

      return updatedRecord;
    });
  }

  @override
  Future<Result<List<PayrollRecord>>> getPayrollRecordsForBarber(
    String barberId,
  ) {
    return FirestoreErrorMapper.guard(() async {
      final snap = await _records
          .where('barberId', isEqualTo: barberId)
          .orderBy('periodStartDate', descending: true)
          .get();
      return snap.docs
          .map(
            (doc) => PayrollRecordFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain(),
          )
          .toList(growable: false);
    });
  }

  @override
  Future<Result<bool>> isDateLockedByPayroll(DateTime shopDate) {
    return FirestoreErrorMapper.guard(() async {
      final normalized = ShopDateUtils.normalizeDate(shopDate);
      final snap = await _periods.where(
        'status',
        whereIn: <String>[
          PayrollPeriodStatus.approved.dbValue,
          PayrollPeriodStatus.paid.dbValue,
        ],
      ).get();

      for (final doc in snap.docs) {
        final period =
            PayrollPeriodFirestoreDto.fromFirestore(doc.id, doc.data())
                .toDomain();
        if (!normalized.isBefore(period.startDate) &&
            !normalized.isAfter(period.endDate)) {
          return true;
        }
      }
      return false;
    });
  }

  Future<PayrollSetting?> _findActiveSetting() async {
    final snap = await _settings
        .where('effectiveTo', isNull: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return PayrollSettingFirestoreDto.fromFirestore(doc.id, doc.data())
        .toDomain();
  }
}
