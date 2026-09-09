import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/core/services/db/tables/accounting_tables.dart';
import 'package:yalla_accounts/core/services/db/tables/hr_tables.dart';
// 📁 lib/features/employees/services/payroll_database_service.dart
//
// PayrollDatabaseService — إدارة استحقاق وصرف الرواتب وربطها بالـ GL (v30)
// متوافق مع مخطط DBService.payroll_runs كما هو حرفيًا.
//
// GL Sources:
//   PAYROLL_ACCRUAL → source_id = run.id
//   Salary payment: PAYMENT voucher with source=PAYROLL_ENTITLEMENT, source_id=run.id
//
// سياسة GL عند الإثبات:
//   Dr 5100 = gross + allowances + paidHolidayPay + overtimePay
//   Cr 2145 = deductions + latePenalty + unpaidAbsencePenalty   (إن وُجد)
//   Cr 2140.E<emp> = preNet  (preNet بعد طرح خصومات الحضور وقبل تطبيق السلف)
//   Apply advances: Dr 2140.E / Cr 1120.E = applied
//   net = preNet - applied
//
// سياسة الدفع:
//   VoucherPaymentService posts Dr 2140.E / Cr cash or bank.
//   No direct payroll-payment GL is created here.
//
// الحمايات:
// - PayrollPeriodsService.assertAccrualAllowed(...)
// - PayrollPeriodsService.ensureOpen(...)
// - منع عكس الإثبات إن وُجدت دفعات.
//
// الواجهة:
// - accrue(...)
// - pay(...)
// - reverseAccrual(runId)
// - listByEmployee(...), listByMonth(...)
// - getById(...)

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';
import 'package:yalla_accounts/features/employees/services/salary_database_service.dart';
import 'package:yalla_accounts/features/employees/models/salary.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';

class PayrollRun {
  final String id;
  final String employeeId;
  final double gross;
  final double allowances;
  final double deductions;
  final double advanceApplied;
  final double net;
  final double amountPaid;
  final String status; // 'ACCRUED' | 'PAID' | 'REVERSED'
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime accrualDate;
  final String? method;
  final String? note;

  const PayrollRun({
    required this.id,
    required this.employeeId,
    required this.gross,
    required this.allowances,
    required this.deductions,
    required this.advanceApplied,
    required this.net,
    required this.amountPaid,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.accrualDate,
    this.method,
    this.note,
  });

  PayrollRun copyWith({
    String? id,
    String? employeeId,
    double? gross,
    double? allowances,
    double? deductions,
    double? advanceApplied,
    double? net,
    double? amountPaid,
    String? status,
    DateTime? periodStart,
    DateTime? periodEnd,
    DateTime? accrualDate,
    String? method,
    String? note,
  }) {
    return PayrollRun(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      gross: gross ?? this.gross,
      allowances: allowances ?? this.allowances,
      deductions: deductions ?? this.deductions,
      advanceApplied: advanceApplied ?? this.advanceApplied,
      net: net ?? this.net,
      amountPaid: amountPaid ?? this.amountPaid,
      status: status ?? this.status,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      accrualDate: accrualDate ?? this.accrualDate,
      method: method ?? this.method,
      note: note ?? this.note,
    );
  }

  static PayrollRun fromMap(Map<String, Object?> m) {
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse((v ?? '0').toString()) ?? 0.0;
    DateTime p(Object? v, {DateTime? fallback}) => v is DateTime
        ? v
        : (DateTime.tryParse((v ?? '').toString()) ??
            (fallback ?? DateTime.now()));

    final ps = p(m['period_start']);
    final pe = p(m['period_end']);

    return PayrollRun(
      id: (m['id'] ?? '').toString(),
      employeeId: (m['employee_id'] ?? '').toString(),
      gross: d(m['gross']),
      allowances: d(m['allowances']),
      deductions: d(m['deductions']),
      advanceApplied: d(m['advance_applied']),
      net: d(m['net']),
      amountPaid: d(m['amount_paid']),
      status: (m['status'] ?? 'ACCRUED').toString(),
      periodStart: ps,
      periodEnd: pe,
      accrualDate: p(m['accrual_date'], fallback: pe),
      method: (m['method']?.toString().trim().isEmpty ?? true)
          ? null
          : m['method']!.toString(),
      note: (m['note']?.toString().trim().isEmpty ?? true)
          ? null
          : m['note']!.toString(),
    );
  }

  Map<String, Object?> toDbMap() => {
        'id': id,
        'employee_id': employeeId,
        'period_start': periodStart.toIso8601String(),
        'period_end': periodEnd.toIso8601String(),
        'gross': gross,
        'allowances': allowances,
        'deductions': deductions,
        'advance_applied': advanceApplied,
        'net': net,
        'amount_paid': amountPaid,
        'status': status,
        'accrual_date': accrualDate.toIso8601String(),
        'method': method,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      };
}

class PayrollDatabaseService {
  static const table = 'payroll_runs';
  static const paymentsTable = 'payroll_payments';

  static Future<void> ensureTables() async {
    final db = await DBService.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $paymentsTable (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        method TEXT,
        note TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_payroll_payments_run ON $paymentsTable(run_id);');
    await _ensureColumn(db, table, 'created_at', 'TEXT');
    await _ensureColumn(db, table, 'attendance_snapshot', 'TEXT');
    await _ensureColumn(db, table, 'entitlement_basis', 'TEXT');
    await _ensureColumn(db, paymentsTable, 'voucher_id', 'TEXT');
  }

  static Future<void> _ensureColumn(
    DatabaseExecutor db,
    String tableName,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($tableName)');
    if (!info.any((r) => r['name'] == column)) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN $column $type');
    }
  }

  // ===== Accounts helpers =====
  static Future<int> _salariesExpenseId() async =>
      await DBService.getAccountIdByCode('5100') ??
      await DBService.ensureAccount(
          code: '5100',
          name: 'مصروف رواتب',
          type: 'EXPENSE',
          normalBalance: 'DEBIT');

  static Future<int> _withholdingsPayableId() async =>
      await DBService.getAccountIdByCode('2145') ??
      await DBService.ensureAccount(
          code: '2145',
          name: 'اقتطاعات مستحقة',
          type: 'LIABILITY',
          normalBalance: 'CREDIT');

  static String _empSub(String root, String empId) => '$root.E$empId';

  static Future<int> _payableSubId(String employeeId) async {
    final code = _empSub('2140', employeeId);
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: 'مستحقات رواتب - $employeeId',
      type: 'LIABILITY',
      normalBalance: 'CREDIT',
    );
  }

  static Future<int> _advanceSubId(String employeeId) async {
    final code = _empSub('1120', employeeId);
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: 'سلف موظف - $employeeId',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  static bool _isBankMethod(String? m) {
    final s = (m ?? '').toLowerCase();
    return s.contains('bank') ||
        s.contains('تحويل') ||
        s.contains('transfer') ||
        s.contains('visa') ||
        s.contains('master') ||
        s.contains('card') ||
        s.contains('بطاقة') ||
        s.contains('شيك') ||
        s.contains('cheque') ||
        s.contains('check');
  }

  static Future<int> _cashOrBankId(String? method) async {
    final viaBank = _isBankMethod(method);
    final code = viaBank ? '1010' : '1000';
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: viaBank ? 'البنك' : 'الصندوق',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  static double _fix2(num x) => double.parse(x.toStringAsFixed(2));
  static String _iso(Object? v) {
    if (v == null) return DateTime.now().toIso8601String();
    if (v is String) return DateTime.tryParse(v)?.toIso8601String() ?? v;
    if (v is DateTime) return v.toIso8601String();
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v).toIso8601String();
    }
    return DateTime.now().toIso8601String();
  }

  // ===== Commands =====

  /// إثبات راتب فترة مع تعديلات الحضور الاختيارية.
  ///
  /// attendance adjustments:
  /// - overtimePay:        زيادات بسبب ساعات إضافية.
  /// - latePenalty:        خصومات تأخير.
  /// - unpaidAbsencePenalty: خصومات غياب غير مدفوع.
  /// - paidHolidayPay:     بدل عطلات رسمية مدفوعة.
  ///
  /// إن تُركت صفرًا يبقى السلوك السابق كما هو.
  static Future<String> accrue({
    required String employeeId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime accrualDate,
    required double gross,
    double allowances = 0,
    double deductions = 0,
    double? advanceApplied, // إن لم يُمرر: يُحسب من GL pending
    String? method,
    String? note,
    String? attendanceSnapshot,
    String? entitlementBasis,

    // === attendance-driven deltas ===
    double overtimePay = 0, // + إلى المصروف
    double latePenalty = 0, // + إلى الاقتطاعات
    double unpaidAbsencePenalty = 0, // + إلى الاقتطاعات
    double paidHolidayPay = 0, // + إلى المصروف
  }) async {
    await ensureTables();
    final db = await DBService.database;

    await PayrollPeriodsService.assertAccrualAllowed(
      employeeId: employeeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );

    if (gross <= 0) throw ArgumentError('gross must be > 0');
    if (allowances < 0 || deductions < 0) {
      throw ArgumentError('allowances/deductions must be >= 0');
    }
    if (overtimePay < 0 ||
        latePenalty < 0 ||
        unpaidAbsencePenalty < 0 ||
        paidHolidayPay < 0) {
      throw ArgumentError('attendance adjustments must be >= 0');
    }

    // إجماليات المصروف والاقتطاع قبل السلف
    final totalExpenseSide =
        _fix2(gross + allowances + paidHolidayPay + overtimePay);
    final totalDeductSide =
        _fix2(deductions + latePenalty + unpaidAbsencePenalty);

    final preNet = _fix2(totalExpenseSide - totalDeductSide);
    if (preNet < 0) {
      throw ArgumentError('preNet cannot be negative');
    }

    // 2) GL
    final drExpense = await _salariesExpenseId(); // 5100
    final crWithhold = await _withholdingsPayableId(); // 2145
    final crPayable = await _payableSubId(employeeId); // 2140.E
    final drPayable = crPayable; // 2140.E
    final crAdvance = await _advanceSubId(employeeId); // 1120.E

    await SalaryDatabaseService.ensureTable();
    await PayrollPeriodsService.ensurePeriodRow(
        periodStart.year, periodStart.month);
    return SyncFoundationService.transaction(db, (txn) async {
      final duplicate = await txn.rawQuery(
          "SELECT id FROM payroll_runs WHERE employee_id=? AND status<>'REVERSED' AND substr(period_start,1,10)<=? AND substr(period_end,1,10)>=? LIMIT 1",
          [
            employeeId,
            periodEnd.toIso8601String().substring(0, 10),
            periodStart.toIso8601String().substring(0, 10)
          ]);
      if (duplicate.isNotEmpty)
        throw StateError('يوجد استحقاق مسجل لهذه الفترة.');
      // سلف معلّقة
      final pendingAdv =
          _fix2(await HRTables.getEmployeeAdvancesTotal(txn, employeeId));
      final applied = _fix2(
        advanceApplied == null
            ? (pendingAdv <= 0
                ? 0
                : (pendingAdv > preNet ? preNet : pendingAdv))
            : (advanceApplied < 0
                ? 0
                : (advanceApplied > preNet ? preNet : advanceApplied)),
      );
      final net = _fix2(preNet - applied);

      final runId = const Uuid().v4();

      // 1) سجل التشغيل
      try {
        await txn.insert(
          table,
          {
            'id': runId,
            'employee_id': employeeId,
            'period_start': periodStart.toIso8601String(),
            'period_end': periodEnd.toIso8601String(),
            'gross': _fix2(gross),
            'allowances': _fix2(allowances),
            'deductions':
                _fix2(deductions + latePenalty + unpaidAbsencePenalty),
            'advance_applied': applied,
            'net': net,
            'amount_paid': 0.0,
            'status': 'ACCRUED',
            'accrual_date': _iso(accrualDate),
            'method': method,
            'note': note,
            'attendance_snapshot': attendanceSnapshot,
            'entitlement_basis': entitlementBasis,
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } on DatabaseException catch (e) {
        if (e.isUniqueConstraintError()) {
          throw StateError('تم إثبات راتب هذا الموظف لنفس الفترة مسبقًا.');
        }
        rethrow;
      }

      final lines = <Map<String, Object?>>[
        // Dr: Expense for base + allowances + paidHoliday + overtime
        {
          'account_id': drExpense,
          'debit': totalExpenseSide,
          'credit': 0.0,
          'party_type': 'EMPLOYEE',
          'party_id': employeeId,
          'invoice_id': null,
          'repair_id': null,
        },
        // Cr: Withholdings for statutory + lateness + unpaid absence
        if (totalDeductSide > 0)
          {
            'account_id': crWithhold,
            'debit': 0.0,
            'credit': totalDeductSide,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
        // Cr: Payable before advances
        if (preNet > 0)
          {
            'account_id': crPayable,
            'debit': 0.0,
            'credit': preNet,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
        // Apply advances: Dr 2140 / Cr 1120
        if (applied > 0)
          {
            'account_id': drPayable,
            'debit': applied,
            'credit': 0.0,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
        if (applied > 0)
          {
            'account_id': crAdvance,
            'debit': 0.0,
            'credit': applied,
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
            'invoice_id': null,
            'repair_id': null,
          },
      ];

      await AccountingTables.postEntryGLOn(
        ex: txn,
        date: accrualDate,
        source: 'PAYROLL_ACCRUAL',
        sourceId: runId,
        note: note ?? 'استحقاق راتب',
        lines: lines,
      );
      // ================================
      // ربط الاستحقاق بسجل الرواتب (Salary)
      // ================================
      final monthKey =
          '${periodStart.year.toString().padLeft(4, '0')}-${periodStart.month.toString().padLeft(2, '0')}';

      await SalaryDatabaseService.upsertSalary(
        Salary(
          id: 'SAL-$employeeId-$monthKey',
          employeeId: employeeId,
          month: monthKey,
          date: DateTime(periodStart.year, periodStart.month, 1),
          gross: totalExpenseSide,
          advancesApplied: applied,
          deductions: totalDeductSide,
          net: net,
          status: 'ACCRUED',
          note: note,
        ),
        executor: txn,
      );
      return runId;
    });
  }

  /// دفع جزئي/كامل حصراً من خلال سند صرف رسمي.
  /// لا يتم إنشاء أي GL مباشر هنا؛ VoucherPaymentService هو بوابة الدفع الوحيدة.
  static Future<void> pay({
    required String runId,
    required double amount,
    required DateTime date,
    String? method,
    String? note,
  }) async {
    await ensureTables();
    final db = await DBService.database;

    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final rows =
        await db.query(table, where: 'id=?', whereArgs: [runId], limit: 1);
    if (rows.isEmpty) throw StateError('Payroll run not found');
    final run = PayrollRun.fromMap(rows.first);

    await PayrollPeriodsService.ensureOpen(
      run.periodStart.year,
      run.periodStart.month,
    );

    if (run.status == 'REVERSED') {
      throw StateError('Cannot pay a reversed payroll run');
    }

    await syncPaymentState(runId);
    final refreshed = await getById(runId);
    if (refreshed == null) throw StateError('Payroll run disappeared');
    final remaining = _fix2(refreshed.net - refreshed.amountPaid);
    if (remaining <= 0) {
      throw StateError('Payroll entitlement is already fully paid.');
    }
    if (amount - remaining > 0.01) {
      throw StateError('Payment exceeds payroll entitlement remaining amount.');
    }

    final paymentId = const Uuid().v4();
    final voucher = VoucherPayment(
      id: paymentId,
      voucherType: 'PAYMENT',
      voucherNumber: null,
      voucherCode: null,
      partyType: 'EMPLOYEE',
      partyId: refreshed.employeeId,
      amount: _fix2(amount),
      currency: 'ILS',
      date: date,
      method: (method ?? 'cash').toUpperCase(),
      chequeId: null,
      reference: runId,
      source: 'PAYROLL_ENTITLEMENT',
      sourceId: runId,
      notes: note ??
          'دفع راتب ${refreshed.periodStart.year}-${refreshed.periodStart.month.toString().padLeft(2, '0')}',
      isPosted: false,
      attachments: null,
    );

    final posted = await VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: refreshed.employeeId,
    );

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              paymentsTable,
              {
                'id': paymentId,
                'run_id': runId,
                'amount': _fix2(amount),
                'date': _iso(date),
                'method': method,
                'note': note,
                'voucher_id': posted.id,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            ));

    await syncPaymentState(runId);
  }

  /// amount_paid/status are compatibility mirrors derived from posted vouchers.
  static Future<void> syncPaymentState(String runId) async {
    await ensureTables();
    final db = await DBService.database;
    final runRows =
        await db.query(table, where: 'id=?', whereArgs: [runId], limit: 1);
    if (runRows.isEmpty) return;
    final net = (runRows.first['net'] as num?)?.toDouble() ?? 0.0;
    final sumRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount),0) AS paid
      FROM vouchers
      WHERE source = 'PAYROLL_ENTITLEMENT'
        AND source_id = ?
        AND UPPER(COALESCE(status,'POSTED')) <> 'REVERSED'
        AND gl_entry_id IS NOT NULL
    ''', [runId]);
    final paid = _fix2((sumRows.first['paid'] as num?)?.toDouble() ?? 0.0);
    final status = paid + 0.01 >= net ? 'PAID' : 'ACCRUED';
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              table,
              {'amount_paid': paid, 'status': status},
              where: 'id=?',
              whereArgs: [runId],
            ));
  }

  /// عكس قيد الإثبات فقط. يُمنع إن وُجدت دفعات.
  static Future<void> reverseAccrual(String runId, {String? note}) async {
    await ensureTables();
    final db = await DBService.database;

    final pays = await db.query(
      'vouchers',
      columns: const ['id'],
      where:
          "source='PAYROLL_ENTITLEMENT' AND source_id=? AND UPPER(COALESCE(status,'POSTED')) <> 'REVERSED'",
      whereArgs: [runId],
      limit: 1,
    );
    if (pays.isNotEmpty) {
      throw StateError(
        'Cannot reverse accrual while posted salary payment vouchers exist.',
      );
    }

    final head = await db.query(
      'gl_entries',
      columns: ['id'],
      where: 'source=? AND source_id=?',
      whereArgs: ['PAYROLL_ACCRUAL', runId],
      limit: 1,
    );

    if (head.isNotEmpty) {
      final entryId = head.first['id'] as int;
      try {
        await DBService.reverseEntryGL(entryId,
            note: note ?? 'Reverse payroll accrual');
      } catch (_) {}
    }

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              table,
              {'status': 'REVERSED'},
              where: 'id=?',
              whereArgs: [runId],
            ));
  }

  // ===== Queries =====

  static Future<List<PayrollRun>> listByEmployee(String employeeId) async {
    await ensureTables();
    final db = await DBService.database;
    final rows = await db.query(
      table,
      where: 'employee_id=?',
      whereArgs: [employeeId],
      orderBy: 'period_start DESC',
    );
    return rows.map(PayrollRun.fromMap).toList();
  }

  /// يجلب كل رواتب شهر محدد 'yyyy-MM' باستخدام period_start.
  static Future<List<PayrollRun>> listByMonth(String ym) async {
    await ensureTables();
    final db = await DBService.database;

    final parts = ym.split('-');
    if (parts.length != 2) {
      throw ArgumentError('format must be yyyy-MM');
    }
    final year = int.tryParse(parts[0]) ?? 0;
    final month = int.tryParse(parts[1]) ?? 0;
    if (year <= 0 || month <= 0 || month > 12) {
      throw ArgumentError('invalid year/month');
    }

    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);

    final rows = await db.query(
      table,
      where: 'period_start >= ? AND period_start < ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'employee_id ASC, period_start DESC',
    );
    return rows.map(PayrollRun.fromMap).toList();
  }

  static Future<PayrollRun?> getById(String runId) async {
    await ensureTables();
    final db = await DBService.database;
    final rows =
        await db.query(table, where: 'id=?', whereArgs: [runId], limit: 1);
    if (rows.isEmpty) return null;
    return PayrollRun.fromMap(rows.first);
  }
}
