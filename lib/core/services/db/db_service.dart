// ============================================================================
// 📁 lib/core/services/db/db_service.dart
// DBService — Extended v41
//
// - نسخة محسّنة بالكامل بدون المساس بأي واجهة API مستخدمة في المشروع
// - لا يوجد أي تعديل يكسر GL أو Repairs أو Vouchers أو Employees
// - ترتيب داخلي أقوى، وثبات أعلى، ووضوح ودقة في المسؤوليات
// - محسنة للعمل مع DatabaseMigration v41 + AccountingTables v41
//
// ملاحظة: كل الدوال الأصلية موجودة كما هي 100%
// ============================================================================
import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

// البنية الأساسية للقاعدة
import 'database_migration.dart';
import 'database_constants.dart';

// الجداول الأساسية
import 'tables/user_tables.dart';
import 'tables/repair_tables.dart';
import 'tables/accounting_tables.dart';
import '../posting_engine.dart';
import 'tables/hr_tables.dart';
import 'tables/supplier_tables.dart';
import 'tables/cheque_tables.dart';
import 'tables/report_tables.dart';
import 'tables/technical_tables.dart';
import 'tables/purchase_invoices_table.dart';
import 'tables/purchase_payments_table.dart';

// المشاهد (Views)
import 'views/accounting_views.dart';

// ============================================================================
// Provider
// ============================================================================

final dbServiceProvider = Provider<DBService>((ref) => DBService.instance);

// ============================================================================
// DBService — الفاصل المركزي بين جميع أجزاء النظام وقاعدة البيانات
// ============================================================================

class DBService {
  DBService._internal();
  static final DBService instance = DBService._internal();

  // ==========================================================================
  // 🔌 أساسيات DB
  // ==========================================================================

  static Future<Database> get database async => DatabaseMigration.database;

  static Future<String> dbFilePath() async {
    final path = await DatabaseConstants.dbFilePath();
    debugPrint("📌 Using canonical DB path: $path");
    return path;
  }

  static Future<void> closeDatabase({bool checkpoint = true}) =>
      DatabaseMigration.closeDatabase(checkpoint: checkpoint);

  static Future<Database> reopenDatabase() =>
      DatabaseMigration.reopenDatabase();

  static Future<void> resetDatabase() => DatabaseMigration.resetDatabase();

  static String newUuid() => DatabaseConstants.newUuid();

  static Future<T> inTx<T>(
    Future<T> Function(DatabaseExecutor db) action,
  ) async {
    return DatabaseMigration.inTx(action);
  }

  // ==========================================================================
  // 👥 USERS & WORKSHOP SETTINGS
  // ==========================================================================

  static Future<Map<String, dynamic>> getUserById(String id) async {
    final db = await database;
    return UserTables.getUserById(db, id);
  }

  static Future<int> updateWorkshopSettings(Map<String, dynamic> data) async {
    final db = await database;
    return UserTables.updateWorkshopSettings(db, data);
  }

  static Future<Map<String, dynamic>> getWorkshopSettings() async {
    final db = await database;
    return UserTables.getWorkshopSettings(db);
  }

  // ==========================================================================
  // 🚗 REPAIRS
  // ==========================================================================

  static Future<Map<String, dynamic>> getRepairById(String id) async {
    final db = await database;
    return RepairTables.getRepairById(db, id);
  }

  static Future<void> updateRepairPaidAmount(
      String repairId, double amount) async {
    final db = await database;
    return RepairTables.updateRepairPaidAmount(db, repairId, amount);
  }

  static Future<void> setRepairThumbnailPath({
    required String repairId,
    String? path,
  }) async {
    final db = await database;
    return RepairTables.setRepairThumbnailPath(
      db: db,
      repairId: repairId,
      path: path,
    );
  }

  static Future<String?> getRepairThumbnailPath(String repairId) async {
    final db = await database;
    return RepairTables.getRepairThumbnailPath(db, repairId);
  }

  static Future<String> createInvoiceForRepair({
    required String repairId,
    required int? clientId,
    required double total,
  }) async {
    final db = await database;
    return RepairTables.createInvoiceForRepair(
      db: db,
      repairId: repairId,
      clientId: clientId,
      total: total,
    );
  }

  // ==========================================================================
  // 💰 ACCOUNTING / GL
  // ==========================================================================

  static Future<int> postEntryGL({
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    return PostingEngine.postEntry(
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      note: note,
      lines: lines,
    );
  }

  static Future<int> postEntryGLOn({
    required DatabaseExecutor ex,
    required DateTime date,
    String? ref,
    required String source,
    required String sourceId,
    String? sourceNumber,
    String? note,
    required List<Map<String, Object?>> lines,
  }) async {
    return PostingEngine.postEntryOn(
      ex: ex,
      date: date,
      ref: ref,
      source: source,
      sourceId: sourceId,
      sourceNumber: sourceNumber,
      note: note,
      lines: lines,
    );
  }

  static Future<int> ensureClientAccount(int clientId) async =>
      AccountingTables.ensureClientAccount(clientId);

  static Future<int> ensureSupplierAccount(String supplierId) async =>
      AccountingTables.ensureSupplierAccount(supplierId);

  static Future<int?> getAccountIdByCode(String code) async =>
      AccountingTables.getAccountIdByCode(code);

  static Future<int> postInvoiceGL({
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    String? note,
  }) async {
    return PostingEngine.postInvoice(
      invoiceId: invoiceId,
      date: date,
      clientId: clientId,
      total: total,
      vatAmount: vatAmount,
      repairId: repairId,
      ref: ref,
      sourceNumber: sourceNumber,
      note: note,
    );
  }

  static Future<int> postInvoiceGLOnTransaction({
    required DatabaseExecutor txn,
    required String invoiceId,
    required DateTime date,
    required int clientId,
    required double total,
    double vatAmount = 0.0,
    String? repairId,
    String? ref,
    String? sourceNumber,
    String? note,
  }) async {
    return PostingEngine.postInvoiceOn(
      txn: txn,
      invoiceId: invoiceId,
      date: date,
      clientId: clientId,
      total: total,
      vatAmount: vatAmount,
      repairId: repairId,
      ref: ref,
      sourceNumber: sourceNumber,
      note: note,
    );
  }

  static Future<int> postInvoiceGLFromId(String invoiceId) =>
      PostingEngine.postInvoiceFromId(invoiceId);

  static Future<int?> getGlEntryIdBySource(
          String source, String sourceId) async =>
      AccountingTables.getGlEntryIdBySource(source, sourceId);

  static Future<int?> getClientIdForRepair(
    DatabaseExecutor txn,
    String repairId,
  ) async =>
      AccountingTables.getClientIdForRepair(txn, repairId);

  // ==========================================================================
  // 💰 EXTRA ACCOUNTING APIs
  // ==========================================================================

  static Future<void> ensureDefaultAccountsExist() async =>
      AccountingTables.ensureDefaultAccountsExist();

  static Future<int?> accountIdForClient(int clientId) async =>
      AccountingTables.accountIdForClient(clientId);

  static Future<int?> accountIdForSupplier(String supplierId) async =>
      AccountingTables.accountIdForSupplier(supplierId);

  static Future<int> ensureAccount({
    required String code,
    required String name,
    required String type,
    required String normalBalance,
  }) async {
    return AccountingTables.ensureAccount(
      code: code,
      name: name,
      type: type,
      normalBalance: normalBalance,
    );
  }

  static Future<int> reverseEntryGL(int entryId, {String? note}) async =>
      PostingEngine.reverseEntry(entryId, note: note);

  static Future<int> reverseEntryGLOn(
    DatabaseExecutor ex,
    int entryId, {
    String? note,
  }) async {
    return PostingEngine.reverseEntryOn(ex, entryId, note: note);
  }

  // ==========================================================================
  // 👥 HR
  // ==========================================================================

  static Future<List<Map<String, dynamic>>> getEmployees() async {
    final db = await database;
    return HRTables.getEmployees(db);
  }

  static Future<Map<String, dynamic>> getEmployeeById(String id) async {
    final db = await database;
    return HRTables.getEmployeeById(db, id);
  }

  static Future<void> markAttendance(String employeeId, DateTime date) async {
    final db = await database;
    return HRTables.markAttendance(db, employeeId, date);
  }

  static Future<double> getEmployeeAdvancesTotal(String employeeId) async {
    final db = await database;
    return HRTables.getEmployeeAdvancesTotal(db, employeeId);
  }
// ============================================================================
// 🛒 SUPPLIERS (CLEAN — v41)
// ============================================================================

  static Future<List<Map<String, dynamic>>> getSuppliers() async {
    final db = await database;
    return SupplierTables.getSuppliers(db);
  }

  static Future<Map<String, dynamic>?> getSupplierById(int id) async {
    final db = await database;
    return SupplierTables.getSupplierById(db, id);
  }

  static Future<Map<String, dynamic>?> getSupplierByPid(String pid) async {
    final db = await database;
    return SupplierTables.getSupplierByPid(db, pid);
  }
// ---------------------------------------------------------------------------
// ❌ لا يوجد createPurchase
// ❌ لا يوجد getPurchasesBySupplier
// ❌ لا يوجد getPurchasesBySupplierPid
// لأن النظام الجديد يعتمد على purchase_invoices + purchase_payments فقط
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 🔢 رصيد المورد الرسمي — عبر الجداول الجديدة فقط
// ---------------------------------------------------------------------------
  static Future<double> getSupplierBalance(int supplierId) async {
    final db = await database;

    // مجموع الفواتير
    final inv = await db.rawQuery("""
    SELECT COALESCE(SUM(amount_total), 0) AS total
    FROM purchase_invoices
    WHERE supplier_id = ?;
  """, [supplierId]);

    final totalInvoices = (inv.first["total"] as num?)?.toDouble() ?? 0.0;

    // مجموع المدفوعات
    final pay = await db.rawQuery("""
    SELECT COALESCE(SUM(amount), 0) AS total
    FROM payments
    WHERE party_type = 'SUPPLIER' AND party_id = ?;
  """, [supplierId]);

    final totalPayments = (pay.first["total"] as num?)?.toDouble() ?? 0.0;

    return totalInvoices - totalPayments;
  }

  // ==========================================================================
  // 💳 CHEQUES
  // ==========================================================================

  static Future<void> checkAutoChequeReturns() async =>
      ChequeTables.checkAutoChequeReturns();

  static Future<List<Map<String, dynamic>>> getPendingCheques() async {
    final db = await database;
    return ChequeTables.getPendingCheques(db);
  }

  static Future<List<Map<String, dynamic>>> getChequesByClient(
      int clientId) async {
    final db = await database;
    return ChequeTables.getChequesByClient(db, clientId);
  }

  static Future<int> createCheque(Map<String, dynamic> data) async {
    final db = await database;
    return ChequeTables.createCheque(db, data);
  }

  static Future<void> updateChequeStatus(int chequeId, String status) async {
    final db = await database;
    return ChequeTables.updateChequeStatus(db, chequeId, status);
  }

  static Future<int> createVoucher(Map<String, dynamic> data) async {
    final db = await database;
    return ChequeTables.createVoucher(db, data);
  }

  // ==========================================================================
  // 📊 REPORTS
  // ==========================================================================

  static Future<Map<String, dynamic>> getMonthlyExpenses(
      int year, int month) async {
    final db = await database;
    return ReportTables.getMonthlyExpenses(db, year, month);
  }

  static Future<int> updateMonthlyExpenses(Map<String, dynamic> data) async {
    final db = await database;
    return ReportTables.updateMonthlyExpenses(db, data);
  }

  static Future<Map<String, dynamic>> getPerformanceReport(
      DateTime start, DateTime end) async {
    final db = await database;
    return ReportTables.getPerformanceReport(db, start, end);
  }

  // ==========================================================================
  // 🔧 TECHNICAL LOGS
  // ==========================================================================

  static Future<void> logDomainEvent(
      String type, Map<String, dynamic> payload) async {
    final db = await database;
    return TechnicalTables.logDomainEvent(db, type, payload);
  }

  static Future<List<Map<String, dynamic>>> getPendingDomainEvents() async {
    final db = await database;
    return TechnicalTables.getPendingDomainEvents(db);
  }

  static Future<Map<String, dynamic>> getSystemStats() async {
    final db = await database;
    return TechnicalTables.getSystemStats(db);
  }

  // ==========================================================================
  // 👀 ACCOUNTING VIEWS
  // ==========================================================================

  static Future<List<Map<String, dynamic>>> getClientAR() async {
    final db = await database;
    return AccountingViews.getClientAR(db);
  }

  static Future<List<Map<String, dynamic>>> getAgingReport() async {
    final db = await database;
    return AccountingViews.getAgingReport(db);
  }

  static Future<List<Map<String, dynamic>>> getTrialBalance(
      DateTime date) async {
    final db = await database;
    return AccountingViews.getTrialBalance(db, date);
  }

  // ==========================================================================
  // 🛠 COMPAT (للتوافق)
  // ==========================================================================

  @Deprecated('Use HRTables.getEmployeeAdvancesTotal instead')
  static Future<double> getEmployeeAdvancePending(
    String employeeId,
  ) async {
    final db = await database;
    return HRTables.getEmployeeAdvancesTotal(db, employeeId);
  }

  @Deprecated('Use PostingEngine through DBService instead')
  static Future<int> postEmployeeAdvanceGL({
    required String employeeId,
    required DateTime date,
    required double amount,
    required bool viaBank,
    String? ref,
    String? note,
  }) async {
    return PostingEngine.postEmployeeAdvance(
      employeeId: employeeId,
      date: date,
      amount: amount,
      viaBank: viaBank,
      ref: ref,
      note: note,
    );
  }
  // ==========================================================================
// 🛒 PURCHASE INVOICES
// ==========================================================================

  static Future<Map<String, dynamic>?> getPurchaseInvoiceById(String id) async {
    final db = await database;
    return PurchaseInvoicesTable.getById(db, id);
  }

  static Future<List<Map<String, dynamic>>> getAllPurchaseInvoices() async {
    final db = await database;
    return PurchaseInvoicesTable.getAll(db);
  }

  static Future<int> insertPurchaseInvoice(Map<String, dynamic> data) async {
    final db = await database;
    return PurchaseInvoicesTable.insert(db, data);
  }

// ==========================================================================
// 💵 PURCHASE PAYMENTS
// ==========================================================================

  static Future<List<Map<String, dynamic>>> getPaymentsForPurchase(
      String invoiceId) async {
    final db = await database;
    return PurchasePaymentsTable.getByInvoice(db, invoiceId);
  }

  static Future<int> insertPurchasePayment(Map<String, dynamic> data) async {
    final db = await database;
    return PurchasePaymentsTable.insert(db, data);
  }
}
