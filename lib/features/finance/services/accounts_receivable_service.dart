import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
// 📁 lib/features/finance/services/accounts_receivable_service.dart
//
// AccountsReceivableService — مصدر موحّد وخفيف للذمم + تكامل كامل مع GL.
// - يعتمد حصريًا على PaymentService لإدراج/تعديل/حذف الدفعات حتى تُدار Reverse/Adjust على GL.
// - يبقي سجل AR داخليًا كـ snapshot + تصحيحات شفافية.
// - يحافظ على camelCase في relatedRepairId.
// - يضيف فهارس مساعدة عند توفر جدول payments.
//
// © Yallah Accounts.

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/accounts_receivable_entry.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

class AccountsReceivableService {
  AccountsReceivableService._();
  static final AccountsReceivableService instance =
      AccountsReceivableService._();

  Future<Database> get _db async => DBService.database;

  //──────────────────────────────────────────────────────────────
  // Schema

  Future<void> ensureTable() async {
    final db = await _db;

    // جدول الذمم
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accounts_receivable (
        id TEXT PRIMARY KEY,
        repairId TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        isPaid INTEGER NOT NULL,
        paidDate TEXT,
        dueDate TEXT,
        customer TEXT,
        method TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ar_repair ON accounts_receivable(repairId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ar_date ON accounts_receivable(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ar_repair_date ON accounts_receivable(repairId, date DESC)');

    // إن وُجد جدول payments أضف فهارس الأداء عليه
    final hasPayments = await _tableExists(db, 'payments');
    if (hasPayments) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_repair ON payments(repair_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_related_repair ON payments(relatedRepairId)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments(invoice_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_payments_date ON payments(date)');
    }
  }

  Future<bool> _tableExists(Database db, String table) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return r.isNotEmpty;
  }

  //──────────────────────────────────────────────────────────────
  // Helpers

  Future<double> _sumPaidForRepair(Database db, String repairId) async =>
      RepairFinancialTruthService.paidForRepair(repairId, executor: db);

  Future<Repair?> _getRepairById(Database db, String id) async {
    final rows =
        await db.query('repairs', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Repair.fromMap(rows.first);
  }

  Future<void> _updateOutstandingAR({
    required Database db,
    required Repair repair,
    required double currentPaid,
  }) async {
    final total = repair.totalFileValue;
    final remaining = (total - currentPaid);

    // إن انتهى الاستحقاق احذف سجل AR
    if (remaining <= 0) {
      await db.delete('accounts_receivable',
          where: 'repairId = ?', whereArgs: [repair.id]);
      return;
    }

    final entry = AccountsReceivableEntry(
      id: 'AR_${repair.id}',
      repairId: repair.id,
      amount: double.parse(remaining.toStringAsFixed(2)),
      date: DateTime.now().toIso8601String(),
      dueDate: repair.receivedDate.toIso8601String(),
      isPaid: false,
      paidDate: null,
      customer: repair.beneficiaryName,
      method: 'تحديث استحقاق',
    );

    await db.insert(
      'accounts_receivable',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _resyncForRepair(Database db, Repair repair) async {
    final currentPaid = await _sumPaidForRepair(db, repair.id);

    // 1) تأكيد وجود فاتورة مرتبطة
    final inv = await InvoiceService.I.getByRepairId(repair.id);
    if (inv == null) {
      await InvoiceService.I.createInvoice(
        repairId: repair.id,
        date: repair.receivedDate,
        total: repair.totalFileValue,
        status: 'unpaid',
        clientId: repair.clientId,
        postToGL: false, // GL يُنشر من مسار الفواتير الرسمي
        notes: 'فاتورة ملف إصلاح (${repair.id})',
      );
    }

    // 2) إعادة احتساب المدفوع من جدول payments
    final inv2 = await InvoiceService.I.getByRepairId(repair.id);
    if (inv2 != null) {
      await InvoiceService.I.recomputePaidFromPayments('${inv2['id']}');
    }

    // 3) تحديث رصيد الذمة المتبقي
    await _updateOutstandingAR(
        db: db, repair: repair, currentPaid: currentPaid);
  }

  //──────────────────────────────────────────────────────────────
  // API

  /// تسجيل استحقاق أولي عند إنشاء إصلاح (اختياري)
  Future<void> recordInitialAR(Repair repair) async {
    await ensureTable();
    final db = await _db;

    final due = repair.remainingAmount;
    if (due <= 0) return;

    final entry = AccountsReceivableEntry(
      id: 'AR_${repair.id}',
      repairId: repair.id,
      amount: double.parse(due.toStringAsFixed(2)),
      date: DateTime.now().toIso8601String(),
      dueDate: repair.receivedDate.toIso8601String(),
      isPaid: false,
      paidDate: null,
      customer: repair.beneficiaryName,
      method: 'استحقاق أولي',
    );

    await db.insert('accounts_receivable', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// مزامنة الذمم مع ملف إصلاح
  Future<void> syncARWithRepair(Repair repair) async {
    await ensureTable();
    final db = await _db;

    final paid = await _sumPaidForRepair(db, repair.id);
    await _updateOutstandingAR(db: db, repair: repair, currentPaid: paid);
  }

  /// تسجيل دفعة جديدة عبر PaymentService ثم تحديث AR.
  Future<void> recordPayment({
    required Repair repair,
    required double amount,
    required String method, // 'نقداً' / 'شيك' / 'تحويل' ...
    DateTime? date,
    String? descriptionOverride,
    Map<String, dynamic>? chequeDraft,
  }) async {
    await ensureTable();
    final db = await _db;
    final now = date ?? DateTime.now();

    final p = Payment(
      id: const Uuid().v4(),
      clientId: repair.clientId,
      invoiceId: null,
      repairId: repair.id,
      relatedRepairId: repair.id,
      amount: double.parse(amount.toStringAsFixed(2)),
      date: now,
      method: method,
      accountName: null,
      status: "confirmed", // ← ليس Enum
      notes: 'دفعة على ملف إصلاح: ${repair.id}',
      attachments: null,
      glEntryId: null,

      // REQUIRED by model
      isIncome: true, // ← لأنها دفعة قبض للعميل
    );

    await PaymentService.insertAndPostReceipt(
      payment: p,
      customerName: repair.beneficiaryName,
      method: method,
      updateInvoice: true,
      descriptionOverride: descriptionOverride,
      chequeDraft: chequeDraft,
    );

    await _resyncForRepair(db, repair);
  }

  /// تعديل دفعة عبر PaymentService مع Reverse/Adjust للـ GL تلقائيًا ثم إعادة مزامنة AR.
  Future<void> editPaymentAndResync({
    required String paymentId, // UUID
    double? newAmount,
    String? newMethod,
    String? newAccountName,
    String? newNotes,
    DateTime? newDate,
    String? newRepairId, // نقل الدفعة لملف آخر
  }) async {
    await ensureTable();
    final db = await _db;

    final rows = await db.query('payments',
        where: 'id=?', whereArgs: [paymentId], limit: 1);
    if (rows.isEmpty) {
      throw StateError('لم يتم العثور على الدفعة المطلوبة (id=$paymentId).');
    }

    final old = Payment.fromMap(rows.first);
    final targetRepairId =
        (newRepairId ?? old.repairId ?? old.relatedRepairId ?? '').trim();
    if (targetRepairId.isEmpty) {
      throw StateError('الدفعة غير مرتبطة بأي ملف إصلاح.');
    }

    // ابنِ نسخة محدثة ثم مررها إلى PaymentService.update ليعالج Reverse/Adjust
    final updated = old.copyWith(
      amount: newAmount ?? old.amount,
      method: newMethod ?? old.method,
      accountName: (newAccountName ?? old.accountName)?.trim().isEmpty == true
          ? null
          : (newAccountName ?? old.accountName),
      notes: (newNotes ?? old.notes)?.trim().isEmpty == true
          ? null
          : (newNotes ?? old.notes),
      date: newDate ?? old.date,
      repairId: targetRepairId,
      relatedRepairId: targetRepairId, // توحيد المؤشر
    );

    await PaymentService.update(updated);

    // إعادة مزامنة AR للطرفين إذا تحركت الدفعة
    final oldRepairId = (old.repairId ?? old.relatedRepairId ?? '').trim();
    final oldRepair =
        oldRepairId.isNotEmpty ? await _getRepairById(db, oldRepairId) : null;
    final newRepair = await _getRepairById(db, targetRepairId);

    if (newRepair != null) {
      await _resyncForRepair(db, newRepair);
    }
    if (oldRepair != null && oldRepair.id != targetRepairId) {
      await _resyncForRepair(db, oldRepair);
    }
  }

  /// حذف دفعة عبر PaymentService.delete الذي ينفّذ Reverse ثم حذف، ثم إعادة مزامنة AR.
  Future<void> deletePaymentAndResync(String paymentId) async {
    await ensureTable();
    final db = await _db;

    // تعرّف ملف الإصلاح قبل الحذف للمزامنة بعد العملية
    final oldRows = await db.query('payments',
        where: 'id=?', whereArgs: [paymentId], limit: 1);
    String? repairId;
    if (oldRows.isNotEmpty) {
      final pm = Payment.fromMap(oldRows.first);
      repairId = (pm.repairId ?? pm.relatedRepairId ?? '').trim();
    }

    await PaymentService.delete(paymentId);

    if (repairId != null && repairId.isNotEmpty) {
      final repair = await _getRepairById(db, repairId);
      if (repair != null) {
        await _resyncForRepair(db, repair);
      }
    }
  }

  /// حذف كل قيود AR لملف إصلاح
  Future<void> deleteAllForRepair(String repairId) async {
    final db = await _db;
    await db.delete('accounts_receivable',
        where: 'repairId = ?', whereArgs: [repairId]);
  }

  //──────────────────────────────────────────────────────────────
  // قراءة

  Future<List<AccountsReceivableEntry>> getEntriesByRepair(
      String repairId) async {
    await ensureTable();
    final db = await _db;
    final rows = await db.query(
      'accounts_receivable',
      where: 'repairId = ?',
      whereArgs: [repairId],
      orderBy: 'date DESC',
    );
    return rows.map(AccountsReceivableEntry.fromMap).toList();
  }

  /// مجموع المدفوع الحقيقي — من payments الموحّد
  Future<double> totalPaidForRepair(String repairId) async {
    final db = await _db;
    return _sumPaidForRepair(db, repairId);
  }
}
