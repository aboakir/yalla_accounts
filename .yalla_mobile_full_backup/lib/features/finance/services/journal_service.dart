// 📁 lib/features/finance/services/journal_service.dart
//
// JournalService — يعتمد DBService المركزي.
// - ينشئ الجدول إن لم يوجد (بدون أي بيانات افتراضية).
// - دوال جاهزة لتسجيل "دفعة من الزبون" لملف إصلاح بصياغة إنسانية.
// - يحافظ على addDoubleEntry وواجهات CRUD المعتادة.

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/models/journal_entry.dart';

class JournalService {
  JournalService._();
  static final JournalService instance = JournalService._();

  Future<Database> get _db async => DBService.database;

  Future<void> _ensureTableIfNeeded(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT NOT NULL,
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        accountName TEXT NOT NULL,
        relatedRepairId TEXT
      )
    ''');

    // فهارس مفيدة لسرعة الاستعلام (لن تفشل إن وُجدت)
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_journal_date ON journal_entries(date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_journal_repair ON journal_entries(relatedRepairId)');
  }

  // =======================
  // CRUD الأساسي
  // =======================

  Future<void> addJournalEntry(JournalEntry entry) async {
    throw StateError(
      'Legacy journal_entries writes are disabled by P1.005. '
      'Use a canonical business document that posts through PostingEngine.',
    );
  }

  Future<void> addDoubleEntry({
    required DateTime date,
    required String description,
    required double amount,
    required String debitAccount,
    required String creditAccount,
    required String relatedRepairId,
  }) async {
    throw StateError(
      'Legacy journal_entries writes are disabled by P1.005. '
      'Use PostingEngine through the owning business service.',
    );
  }

  Future<List<JournalEntry>> getEntriesByRepairId(String repairId) async {
    final db = await _db;
    await _ensureTableIfNeeded(db);
    final maps = await db.query(
      'journal_entries',
      where: 'relatedRepairId = ?',
      whereArgs: [repairId],
      orderBy: 'date DESC, id DESC',
    );
    return maps.map(JournalEntry.fromMap).toList();
  }

  Future<List<JournalEntry>> getAllEntries() async {
    final db = await _db;
    await _ensureTableIfNeeded(db);
    final maps =
        await db.query('journal_entries', orderBy: 'date DESC, id DESC');
    return maps.map(JournalEntry.fromMap).toList();
  }

  Future<void> deleteEntry(int id) async {
    throw StateError('Legacy journal_entries mutation is disabled by P1.005.');
  }

  Future<void> clearAllEntries() async {
    throw StateError('Legacy journal_entries mutation is disabled by P1.005.');
  }

  // =======================
  // أدوات داخلية بسيطة
  // =======================

  /// يحوّل طريقة الدفع النصية إلى اسم الحساب المناسب في اليومية.
  /// أمثلة مدعومة: "نقد", "نقدًا", "كاش" -> "الصندوق" ،
  ///               "تحويل", "بنك", "بطاقة" -> "البنك".
  String _resolveDebitAccountFromMethod(String method) {
    final m = method.trim();
    final cashWords = {'نقد', 'نقدا', 'نقدًا', 'كاش'};
    final bankWords = {'تحويل', 'بنك', 'بطاقة', 'فيزا', 'ماستر', 'شيك'};

    if (cashWords.contains(m)) return 'الصندوق';
    if (bankWords.contains(m)) return 'البنك';
    // fallback: اعتبرها صندوق إن لم نفهم النص
    return 'الصندوق';
  }

  String _safeCustomerName(String name) {
    final n = name.trim();
    return n.isEmpty ? 'العميل' : n;
  }

  // =======================
  // عمليات جاهزة "إنسانية"
  // =======================

  /// يسجل **دفعة من الزبون** لملف إصلاح (قيد مزدوج).
  ///
  /// description يُولَّد تلقائيًا بصياغة: "دفعة من الزبون — ملف إصلاح".
  /// debitAccount = صندوق/بنك حسب method.
  /// creditAccount = "العملاء (ذمم)" كعنوان عام غير محاسبي.
  Future<void> createReceiptFromRepair({
    required String relatedRepairId,
    required String customerName, // اسم الزبون أو شركة التأمين
    required double amount,
    required String method, // "نقدًا" أو "تحويل/بنك/بطاقة"
    required DateTime date,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final debitAccount = _resolveDebitAccountFromMethod(method);
    final creditAccount = 'العملاء (ذمم)';
    final who = _safeCustomerName(customerName);

    final desc = 'دفعة من الزبون — ملف إصلاح ($who)';

    await addDoubleEntry(
      date: date,
      description: desc,
      amount: amount,
      debitAccount: debitAccount,
      creditAccount: creditAccount,
      relatedRepairId: relatedRepairId,
    );
  }

  /// يسجّل **دفعة إضافية** (فرق عند تعديل المدفوع لاحقًا) لملف إصلاح.
  Future<void> createDeltaReceiptFromRepair({
    required String relatedRepairId,
    required String customerName,
    required double deltaAmount, // الزيادة فقط
    required String method,
    required DateTime date,
  }) async {
    if (deltaAmount <= 0) return; // لا شيء إن لم تكن زيادة
    await createReceiptFromRepair(
      relatedRepairId: relatedRepairId,
      customerName: customerName,
      amount: deltaAmount,
      method: method,
      date: date,
    );
  }

  // =======================
  // واجهات متوافقة قديمة (احتفظنا بها)
  // =======================

  /// نسخة آمنة تعتمد DateTime بدلاً من String للتاريخ.
  Future<void> insertReceiptEntryDateTime({
    required String from,
    required double amount,
    required String method,
    String? description,
    required DateTime date,
    String? relatedRepairId,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');

    final cleanDesc = (description == null || description.trim().isEmpty)
        ? 'دفعة من الزبون ($from)'
        : description.trim();

    final debitAccount = _resolveDebitAccountFromMethod(method);
    final creditAccount = 'العملاء (ذمم)';

    await addDoubleEntry(
      date: date,
      description: cleanDesc,
      amount: amount,
      debitAccount: debitAccount,
      creditAccount: creditAccount,
      relatedRepairId: relatedRepairId ?? '',
    );
  }

  /// (قديمة) تحتفظ بالتوافق إن كان هناك نداءات موجودة تأخذ تاريخ كنص.
  Future<void> insertReceiptEntry({
    required String from,
    required double amount,
    required String method,
    required String description,
    required String date,
    String? relatedRepairId,
  }) async {
    if (amount <= 0) throw ArgumentError('amount must be > 0');
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) {
      throw FormatException('Invalid date format (expected ISO 8601).');
    }

    final cleanDesc =
        description.trim().isEmpty ? 'دفعة من الزبون ($from)' : description;

    final debitAccount = _resolveDebitAccountFromMethod(method);
    final creditAccount = 'العملاء (ذمم)';

    await addDoubleEntry(
      date: parsedDate,
      description: cleanDesc,
      amount: amount,
      debitAccount: debitAccount,
      creditAccount: creditAccount,
      relatedRepairId: relatedRepairId ?? '',
    );
  }

  /// تسوية فاتورة — احتفظت بها كما هي، في حال تستخدمها بمكان آخر.
  Future<void> closeInvoice({
    required String invoiceId,
    required double paidAmount,
    String receiptMethod = 'الصندوق',
    String? relatedRepairId,
    DateTime? postingDate,
    String description = 'تسوية فاتورة',
  }) async {
    if (paidAmount <= 0) throw ArgumentError('paidAmount must be > 0');
    final date = postingDate ??
        (throw ArgumentError('postingDate is required for closeInvoice'));

    await addDoubleEntry(
      date: date,
      description: '$description #$invoiceId',
      amount: paidAmount,
      debitAccount: receiptMethod,
      creditAccount: 'العملاء (ذمم)',
      relatedRepairId: relatedRepairId ?? '',
    );
  }
}
