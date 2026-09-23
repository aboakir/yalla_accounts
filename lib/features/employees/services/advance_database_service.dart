import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
// 📁 lib/features/employees/services/advance_database_service.dart
//
// AdvanceDatabaseService — Employee Advances / Bonuses / Repayments → GL (DB v30)
//
// القيود المحاسبية:
// - Advance:   Dr 1120.E[emp] / Cr 1000|1010
// - Bonus:     Dr 5100        / Cr 1000|1010
// - Repayment: Dr 1000|1010   / Cr 1120.E[emp]
//
// GL:
//   source = 'EMP_ADV', source_id = advance.id  (محمي بفهرس uq_gl_source على gl_entries)
//   party_type='EMPLOYEE', party_id=<employeeId>
//
// هذا الإصدار:
// - ensureTable(): إنشاء الجدول + فهارس التاريخ والطريقة والنوع.
// - insertAdvance(...): يكتب السجل (advance/bonus) ثم ينشر GL ويربط gl_entry_id.
// - updateAdvance(...): يعكس القيد القديم ثم يعيد نشر GL لنفس السجل دون إعادة إدراج الصف.
// - reverseAdvance(id): يعكس القيد فقط ويصفر gl_entry_id.
// - deleteAdvance(id) / deleteByEmployee(employeeId): حذف + عكس آمن.
// - listByEmployee(employeeId, {from,to,method}): فلترة مرنة مع شمول يوم النهاية.
// - pendingBalance(employeeId): رصيد السلف الحالي عبر GL.
// - recentForEmployee(...): آخر الحركات.
// - repayAdvanceCashBank(...): تسديد السلفة نقد/بنك + GL + إنشاء سجل type='repayment'.
//
// Notes:
// - subaccount 1120.E<empId> للسلف لتوافق الرواتب 2140.E[emp].
// - source_id = advance.id لتمكين منع التكرار عبر uq_gl_source.
// - لا بيانات وهمية. كل الأرقام من التطبيق.
// - النوع 'repayment' مدعوم.
//
// ---------------------------------------------------------------
// EN: Bilingual comments enforced per project rules.

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/employees/models/advance.dart';
import 'package:yalla_accounts/features/vouchers/services/voucher_payment_service.dart';
import 'package:yalla_accounts/features/vouchers/models/voucher_payment_model.dart';

class AdvanceDatabaseService {
  static const _table = 'employee_advances';

  // ================= Schema =================

  /// إنشاء جدول السلف/المكافآت/التسديدات + فهارس
  static Future<void> ensureTable() async {
    final db = await DBService.database;

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table(
        id TEXT PRIMARY KEY,              -- UUID
        employee_id TEXT NOT NULL,
        amount REAL NOT NULL,
        type TEXT NOT NULL,               -- 'advance' | 'bonus' | 'repayment'
        date TEXT NOT NULL,               -- ISO 8601
        method TEXT,                      -- 'cash' | 'bank' | 'cheque' ...
        note TEXT,
        gl_entry_id INTEGER,              -- linked GL entry
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_emp   ON $_table(employee_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_date  ON $_table(date);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_type  ON $_table(type);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_method ON $_table(method);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_emp_adv_gl    ON $_table(gl_entry_id);');
  }

  // ================= Helpers =================

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

  /// تطبيع طريقة الدفع إلى قيم معروفة
  static String? _normalizeMethod(String? m) {
    if (m == null) return null;
    final s = m.trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s.contains('bank')) return 'bank';
    if (s.contains('transfer') || s.contains('تحويل')) return 'transfer';
    if (s.contains('cheque') || s.contains('check') || s.contains('شيك')) {
      return 'cheque';
    }
    return 'cash';
  }

  static Future<int> _cashOrBankAccountId(String? method) async {
    final bank = _isBankMethod(method);
    final code = bank ? '1010' : '1000';
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: bank ? 'البنك' : 'الصندوق',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  static Future<int> _empAdvanceSubAccountId(String employeeId) async {
    // يضمن 1120.E<empId> أو ينشئه
    final code = '1120.E$employeeId';
    final id = await DBService.getAccountIdByCode(code);
    if (id != null) return id;
    return DBService.ensureAccount(
      code: code,
      name: 'سلف موظف - $employeeId',
      type: 'ASSET',
      normalBalance: 'DEBIT',
    );
  }

  static Future<int> _salariesExpenseAccountId() async {
    final id = await DBService.getAccountIdByCode('5100');
    if (id != null) return id;
    return DBService.ensureAccount(
      code: '5100',
      name: 'مصروف رواتب',
      type: 'EXPENSE',
      normalBalance: 'DEBIT',
    );
  }

  static String _isoString(Object? v) {
    if (v == null) return DateTime.now().toIso8601String();
    if (v is String) return DateTime.tryParse(v)?.toIso8601String() ?? v;
    if (v is DateTime) return v.toIso8601String();
    if (v is int) {
      return DateTime.fromMillisecondsSinceEpoch(v).toIso8601String();
    }
    return DateTime.now().toIso8601String();
  }

  static double _fix2(num x) => double.parse(x.toStringAsFixed(2));

  // ================= Commands =================

  /// إدخال سلفة/مكافأة + نشر GL + تحديث gl_entry_id.
  ///
  /// advance: Dr 1120.E[emp] / Cr 1000|1010
  /// bonus:   Dr 5100       / Cr 1000|1010
  static Future<String> insertAdvance({
    required Advance advance,
    String? method,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    final t = advance.type.toLowerCase().trim();
    if (t != 'advance' && t != 'bonus') {
      throw ArgumentError('type must be "advance" or "bonus"');
    }
    if (advance.amount <= 0) {
      throw ArgumentError('amount must be > 0');
    }

    final id = advance.id.isNotEmpty ? advance.id : const Uuid().v4();
    final adv = advance.copyWith(id: id, type: t);
    final iso = _isoString(adv.date);
    final normalizedMethod = _normalizeMethod(method ?? adv.method);

    // 1) كتابة السجل
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              _table,
              {
                ...adv.toMap(),
                'type': t,
                'date': iso,
                'method': normalizedMethod,
                'gl_entry_id': null,
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            ));
// 2) إنشاء سند صرف رسمي للسلفة / المكافأة
    final voucher = VoucherPayment(
      id: '',
      voucherType: 'PAYMENT',
      partyType: 'EMPLOYEE',
      partyId: adv.employeeId,
      amount: _fix2(adv.amount),
      currency: 'ILS',
      date: DateTime.parse(iso),
      method: normalizedMethod ?? 'cash',
      reference: adv.id,
      source: 'EMP_ADV',
      sourceId: adv.id,
      notes: t == 'bonus' ? 'مكافأة موظف' : 'سلفة موظف',
    );

    final savedVoucher = await VoucherPaymentService.insertAndPost(
      voucher: voucher,
      partyName: adv.employeeId,
    );

// ربط gl_entry_id مع سجل السلفة
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              _table,
              {'gl_entry_id': savedVoucher.glEntryId},
              where: 'id = ?',
              whereArgs: [adv.id],
            ));

    return id;
  }

  /// تعديل: عكس القيد القديم ثم إعادة نشر GL لنفس السجل دون إعادة إدراج الصف.
  static Future<void> updateAdvance({
    required Advance advance,
    String? method,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    final t = advance.type.toLowerCase().trim();
    if (t == 'repayment') {
      throw ArgumentError(
          'repayment update is not supported. delete and re-create.');
    }
    if (t != 'advance' && t != 'bonus') {
      throw ArgumentError('type must be "advance" or "bonus"');
    }
    if (advance.amount <= 0) {
      throw ArgumentError('amount must be > 0');
    }
    if (advance.id.isEmpty) {
      throw ArgumentError('advance.id required for update');
    }

    final normalizedMethod = _normalizeMethod(method ?? advance.method);
    final iso = _isoString(advance.date);

    // 1) اعكس القديم وحدّث الصف
    await SyncFoundationService.transaction(db, (txn) async {
      final old = await txn.query(
        _table,
        where: 'id=?',
        whereArgs: [advance.id],
        limit: 1,
      );
      if (old.isEmpty) throw StateError('advance not found');

      final glOld = old.first['gl_entry_id'];
      final oldGlId = glOld == null ? null : int.tryParse(glOld.toString());
      if (oldGlId != null) {
        try {
          await DBService.reverseEntryGL(oldGlId,
              note: 'Reverse EMP_ADV ${advance.id}');
        } catch (_) {}
      }

      await txn.update(
        _table,
        {
          ...advance.copyWith(type: t, method: normalizedMethod).toMap(),
          'type': t,
          'date': iso,
          'method': normalizedMethod,
          'gl_entry_id': null,
        },
        where: 'id=?',
        whereArgs: [advance.id],
      );
    });

    // 2) أنشر GL من جديد لنفس الـ id
    final isBonus = t == 'bonus';
    final drId = isBonus
        ? await _salariesExpenseAccountId() // 5100
        : await _empAdvanceSubAccountId(advance.employeeId); // 1120.E[emp]
    final crId = await _cashOrBankAccountId(normalizedMethod); // 1000|1010

    int entryId;
    try {
      entryId = await DBService.postEntryGL(
        date: DateTime.parse(iso),
        source: 'EMP_ADV',
        sourceId: advance.id, // نفس الـ id يمنع التكرار
        note: isBonus ? 'Employee Bonus' : 'Employee Advance',
        lines: [
          {
            'account_id': drId,
            'debit': _fix2(advance.amount),
            'credit': 0.0,
            'party_type': 'EMPLOYEE',
            'party_id': advance.employeeId,
          },
          {
            'account_id': crId,
            'debit': 0.0,
            'credit': _fix2(advance.amount),
          },
        ],
      );
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      final existing =
          await DBService.getGlEntryIdBySource('EMP_ADV', advance.id);
      if (existing == null) rethrow;
      entryId = existing;
    }

    // 3) أربط gl_entry_id
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              _table,
              {'gl_entry_id': entryId},
              where: 'id=?',
              whereArgs: [advance.id],
            ));
  }

  /// عكس القيد فقط بدون حذف السجل. يبقي السجل ويصفر gl_entry_id.
  static Future<void> reverseAdvance(String id) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    final row = await db.query(
      _table,
      columns: ['gl_entry_id'],
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isEmpty) return;

    final glId = row.first['gl_entry_id'];
    final entryId = glId == null ? null : int.tryParse(glId.toString());
    if (entryId == null) return;

    try {
      await DBService.reverseEntryGL(entryId, note: 'Reverse EMP_ADV $id');
    } catch (_) {}

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              _table,
              {'gl_entry_id': null},
              where: 'id=?',
              whereArgs: [id],
            ));
  }

  /// حذف سجل + عكس قيده إن وجد.
  static Future<void> deleteAdvance(String id) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    await SyncFoundationService.transaction(db, (txn) async {
      final head = await txn.query(
        'gl_entries',
        where: 'source=? AND source_id=?',
        whereArgs: ['EMP_ADV', id],
        limit: 1,
      );

      if (head.isNotEmpty) {
        final entryId = head.first['id'] as int;
        try {
          await DBService.reverseEntryGL(entryId, note: 'Reverse EMP_ADV $id');
        } catch (_) {}
      }

      await txn.delete(_table, where: 'id=?', whereArgs: [id]);
    });
  }

  /// حذف كل سلف/مكافآت/تسديدات موظف + عكس قيودهم.
  static Future<void> deleteByEmployee(String employeeId) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    await SyncFoundationService.transaction(db, (txn) async {
      final rows = await txn.query(
        _table,
        columns: ['id'],
        where: 'employee_id=?',
        whereArgs: [employeeId],
      );

      for (final r in rows) {
        final id = r['id'] as String;
        final head = await txn.query(
          'gl_entries',
          where: 'source=? AND source_id=?',
          whereArgs: ['EMP_ADV', id],
          limit: 1,
        );
        if (head.isNotEmpty) {
          final entryId = head.first['id'] as int;
          try {
            await DBService.reverseEntryGL(entryId,
                note: 'Reverse EMP_ADV $id');
          } catch (_) {}
        }
      }

      await txn.delete(_table, where: 'employee_id=?', whereArgs: [employeeId]);
    });
  }

  /// تسديد سلفة نقد/بنك + GL + إنشاء سجل type='repayment'
  ///
  /// GL: Dr 1000|1010 / Cr 1120.E[emp]
  static Future<String> repayAdvanceCashBank({
    required String employeeId,
    required double amount,
    required DateTime date,
    String? method,
    String? note,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.payrollManage);
    await ensureTable();
    final db = await DBService.database;

    if (amount <= 0) {
      throw ArgumentError('amount must be > 0');
    }

    // 1) أنشئ سجل repayment
    final id = const Uuid().v4();
    final iso = _isoString(date);
    final normalizedMethod = _normalizeMethod(method);

    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.insert(
              _table,
              {
                'id': id,
                'employee_id': employeeId,
                'amount': _fix2(amount),
                'type': 'repayment',
                'date': iso,
                'method': normalizedMethod,
                'note': note,
                'gl_entry_id': null,
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            ));

    // 2) GL
    final drCashBank =
        await _cashOrBankAccountId(normalizedMethod); // 1000/1010
    final crAdvance = await _empAdvanceSubAccountId(employeeId); // 1120.E[emp]

    int glId;
    try {
      glId = await DBService.postEntryGL(
        date: DateTime.parse(iso),
        source: 'EMP_ADV',
        sourceId: id, // يمنع التكرار
        note: note ?? 'Repayment of employee advance',
        lines: [
          {
            'account_id': drCashBank,
            'debit': _fix2(amount),
            'credit': 0.0,
          },
          {
            'account_id': crAdvance,
            'debit': 0.0,
            'credit': _fix2(amount),
            'party_type': 'EMPLOYEE',
            'party_id': employeeId,
          },
        ],
      );
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
      final existing = await DBService.getGlEntryIdBySource('EMP_ADV', id);
      if (existing == null) rethrow;
      glId = existing;
    }

    // 3) اربط gl_entry_id
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              _table,
              {'gl_entry_id': glId},
              where: 'id=?',
              whereArgs: [id],
            ));

    return id;
  }

  // ================= Queries =================

  static Future<List<Advance>> listAll() async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    await ensureTable();
    final db = await DBService.database;
    final rows = await db.query(_table, orderBy: 'date DESC');
    return rows.map((m) => Advance.fromMap(m)).toList();
  }

  /// قائمة سلف/مكافآت/تسديدات موظف مع فلاتر اختيارية
  /// from/to بصيغة 'yyyy-MM-dd'، نهاية اليوم مشمولة.
  static Future<List<Advance>> listByEmployee(
    String employeeId, {
    String? from, // 'yyyy-MM-dd'
    String? to, // 'yyyy-MM-dd'
    String? method,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    await ensureTable();
    final db = await DBService.database;

    final where = <String>['employee_id=?'];
    final args = <Object?>[employeeId];

    if (from != null && from.trim().isNotEmpty) {
      where.add('date >= ?');
      args.add(from.trim());
    }
    if (to != null && to.trim().isNotEmpty) {
      // شمول يوم النهاية كاملًا
      where.add('date <= ?');
      args.add('${to.trim()}T23:59:59.999');
    }
    if (method != null && method.trim().isNotEmpty) {
      where.add('LOWER(method) = LOWER(?)');
      args.add(_normalizeMethod(method) ?? 'cash');
    }

    final rows = await db.query(
      _table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'date DESC',
    );
    final advances = rows.map((m) => Advance.fromMap(m)).toList();

    // =====================================================
// 🔁 Bridge: جلب سلف قديمة من vouchers (قبل نظام employee_advances)
// =====================================================
    final voucherRows = await db.rawQuery('''
  SELECT
    id,
    party_id,
    amount,
    date,
    method,
    notes,
    gl_entry_id
  FROM vouchers
  WHERE voucher_type = 'PAYMENT'
    AND party_type = 'EMPLOYEE'
AND party_id = ?
AND (source IS NULL OR source = '')
AND (? IS NULL OR date >= ?)
AND (? IS NULL OR date <= ?)
AND (? IS NULL OR LOWER(method) = LOWER(?))
''', [
      employeeId,
      from,
      from,
      to == null ? null : '${to}T23:59:59.999',
      method,
      method,
    ]);
    for (final v in voucherRows) {
      // تجنب التكرار إذا كانت السلفة موجودة أصلاً
      final exists = advances.any((a) => a.id == v['id']);
      if (exists) continue;

      advances.add(
        Advance(
          id: v['id'].toString(),
          employeeId: v['party_id'] as String,
          amount: (v['amount'] as num).toDouble(),
          type: 'advance', // كلهم سلف قديمة
          date: DateTime.parse(v['date'] as String),
          method: v['method'] as String?,
          note: v['notes'] as String?,
          glEntryId: v['gl_entry_id'] as int?,
        ),
      );
    }
    advances.sort((a, b) => b.date.compareTo(a.date));
    return advances;
  }

  static Future<Advance?> getById(String id) async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    await ensureTable();
    final db = await DBService.database;
    final rows =
        await db.query(_table, where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Advance.fromMap(rows.first);
  }

  /// رصيد السلف الحالي لموظف من GL
  static Future<double> pendingBalance(String employeeId) async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    return DBService.getEmployeeAdvancePending(employeeId);
  }

  /// Alias للتوافق السابق
  static Future<double> getEmployeeAdvanceBalance(String employeeId) {
    return pendingBalance(employeeId);
  }

  /// كشف سريع: آخر حركات لموظف
  static Future<List<Map<String, Object?>>> recentForEmployee(
    String employeeId, {
    int limit = 20,
  }) async {
    await AuthorizationGuard.require(PermissionKeys.payrollView);
    await ensureTable();
    final db = await DBService.database;
    return db.query(
      _table,
      where: 'employee_id=?',
      whereArgs: [employeeId],
      orderBy: 'date DESC',
      limit: limit,
    );
  }
}
