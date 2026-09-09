import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
//[📁 lib/core/services/db/tables/repair_tables.dart]

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class RepairTables {
  // 🚗 إنشاء جداول الإصلاحات + شركات التأمين
  static Future<void> createAllTables(DatabaseExecutor db) async {
    await _createInsuranceCompaniesTable(db);
    await _seedInsuranceCompanies(db);

    await _createRepairsTable(db);
    await _createInvoicesTable(db);
    await _createRepairLinesTable(db);
    await _createRepairImagesTable(db);
    await ensureP09WorkflowSchema(db);

    await ensureRepairsSchema(db);
  }

  // =======================================================================
  // 🏢 جدول شركات التأمين
  // =======================================================================
  static Future<void> _createInsuranceCompaniesTable(
      DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS insurance_companies(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
  }

  // تعبئة الشركات الافتراضية مرة واحدة فقط
  static Future<void> _seedInsuranceCompanies(DatabaseExecutor db) async {
    final companies = [
      'الأهلية',
      'العالمية',
      'الوطنية',
      'التكافل',
      'فلسطين',
      'تمكين',
      'ترست',
      'المشرق',
      'الأراضي المقدسة',
      'البركة'
    ];

    for (final name in companies) {
      await db.insert(
        'insurance_companies',
        {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // =======================================================================
  // 🛠 جدول الإصلاحات (نسختك الأصلية + الأعمدة الناقصة مضافة)
  // =======================================================================
  static Future<void> _createRepairsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repairs(
        id TEXT PRIMARY KEY,
        invoiceNumber TEXT,
        vehicleModel TEXT,
        vehicleType TEXT,
        vehicleNumber TEXT,
        receivedDate TEXT,
        beneficiaryType TEXT,
        beneficiaryName TEXT,
        insuranceStatus TEXT,
        insurance_follow_up_status TEXT,
        repairType TEXT,
        vehicleStatus TEXT,
        parts TEXT,
        works TEXT,
        fileValue REAL,
        paymentType TEXT,
        paidAmount REAL,
        paymentStatus TEXT,
        notes TEXT,
        imagePaths TEXT,
        isArchived INTEGER DEFAULT 0,
        finalApprovedAmount REAL,
        workCost REAL,
        incomeAmount REAL,
        isLedgerEnabled INTEGER,
        isLedgerSynced INTEGER,
        invoiceId TEXT,
        invoice_id TEXT,
        client_id INTEGER,
        thumbnail_path TEXT,
        thumbnail_updated_at TEXT,

        -- P07 intake documentation (non-financial, additive migration)
        odometer INTEGER,
        fuel_level INTEGER,
        previous_damage TEXT,
        customer_signature_path TEXT,
        intake_completed_at TEXT,

        -- 🔥 الأعمدة الناقصة (مضافة بدون حذف أي شيء)

        created_at TEXT,
        updated_at TEXT,

        status TEXT,
        quote_number TEXT,
        quote_valid_until TEXT,
        approved_at TEXT,
        approved_by TEXT,

        actualCost REAL,
        transferFromAccount TEXT,
        transferToAccount TEXT,
        transferCompany TEXT,
        transferDate TEXT,
        transferAmount REAL,
        transferImagePath TEXT
      )
    ''');

    await _ensureRepairsIndexes(db);
  }

  static Future<void> _ensureRepairsIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repairs_client ON repairs(client_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repairs_invoice ON repairs(invoice_id);');
  }

  // =======================================================================
  // 🧾 جدول الفواتير
  // =======================================================================
  static Future<void> _createInvoicesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices(
        id TEXT PRIMARY KEY,
        repair_id TEXT,
        client_id INTEGER,
        date TEXT NOT NULL,
        subtotal REAL DEFAULT 0,
        vat_amount REAL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        paid REAL NOT NULL DEFAULT 0,
        status TEXT,
        notes TEXT,
        method TEXT,
        note TEXT,
        post_to_gl INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    await _ensureInvoicesIndexes(db);
  }

  static Future<void> _ensureInvoicesIndexes(DatabaseExecutor db) async {
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_client_id ON invoices(client_id);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invoices_date ON invoices(date);');

    // P0.006 — one repair can have at most one sales invoice.
    final duplicates = await db.rawQuery('''
      SELECT COUNT(*) AS c
      FROM (
        SELECT repair_id
        FROM invoices
        WHERE repair_id IS NOT NULL AND TRIM(repair_id) <> ''
        GROUP BY repair_id
        HAVING COUNT(*) > 1
      )
    ''');

    final duplicateCount = (duplicates.first['c'] as num?)?.toInt() ?? 0;

    if (duplicateCount == 0) {
      await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS uq_invoices_repair_id
        ON invoices(repair_id)
        WHERE repair_id IS NOT NULL AND TRIM(repair_id) <> '';
      ''');
    }
  }

  // =======================================================================
  // 🧩 جدول تفاصيل الإصلاح
  // =======================================================================
  static Future<void> _createRepairLinesTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repair_lines(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        line_type TEXT NOT NULL CHECK(line_type IN ('work','part')),
        name TEXT NOT NULL CHECK(LENGTH(TRIM(name)) > 0),
        qty REAL NOT NULL DEFAULT 1 CHECK(qty > 0),
        price REAL NOT NULL DEFAULT 0 CHECK(price >= 0),
        total REAL NOT NULL DEFAULT 0
          CHECK(total >= 0 AND ABS(total - (qty * price)) <= 0.01),
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
      )
    ''');

    await _ensureRepairLinesIndexes(db);
  }

  static Future<void> _ensureRepairLinesIndexes(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_lines_repair '
      'ON repair_lines(repair_id);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_lines_type '
      'ON repair_lines(line_type);',
    );
  }

  static double _repairLineNumber(
    Object? value, {
    required double fallback,
  }) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  static double _roundRepairLine(double value) =>
      double.parse(value.toStringAsFixed(2));

  static List<Map<String, dynamic>> _decodeRepairLineList(Object? raw) {
    if (raw == null) return <Map<String, dynamic>>[];

    dynamic decoded = raw;
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return <Map<String, dynamic>>[];
      decoded = jsonDecode(text);
    }

    if (decoded is! List) return <Map<String, dynamic>>[];

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Map<String, dynamic>? _normalizeRepairLine(
    Map<String, dynamic> item,
  ) {
    final name = (item['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    var qty = _repairLineNumber(item['qty'], fallback: 1.0);
    if (qty <= 0) qty = 1.0;

    final price = _repairLineNumber(
      item['price'] ?? item['amount'] ?? item['cost'],
      fallback: 0.0,
    );

    if (price < 0) {
      throw StateError('Repair line price cannot be negative: $name');
    }

    final total = _roundRepairLine(qty * price);

    return <String, dynamic>{
      ...item,
      'name': name,
      'qty': qty,
      'price': price,
      'total': total,
    };
  }

  // P0.009 — repairs.parts / repairs.works are the canonical operational
  // detail. repair_lines is a normalized derived table used for query/report
  // compatibility. This migration never rewrites Invoice or GL amounts.
  static Future<void> _rebuildRepairLinesV57(Database db) async {
    final repairs = await db.query(
      'repairs',
      columns: ['id', 'parts', 'works', 'fileValue', 'created_at'],
    );

    await db.execute('DROP TABLE IF EXISTS repair_lines_v57;');
    await db.execute('''
      CREATE TABLE repair_lines_v57(
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        line_type TEXT NOT NULL CHECK(line_type IN ('work','part')),
        name TEXT NOT NULL CHECK(LENGTH(TRIM(name)) > 0),
        qty REAL NOT NULL DEFAULT 1 CHECK(qty > 0),
        price REAL NOT NULL DEFAULT 0 CHECK(price >= 0),
        total REAL NOT NULL DEFAULT 0
          CHECK(total >= 0 AND ABS(total - (qty * price)) <= 0.01),
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
      );
    ''');

    for (final repair in repairs) {
      final repairId = repair['id']?.toString() ?? '';
      if (repairId.isEmpty) continue;

      final normalizedParts = <Map<String, dynamic>>[];
      final normalizedWorks = <Map<String, dynamic>>[];
      var normalizedTotal = 0.0;

      Future<void> migrateType(
        String type,
        Object? raw,
        List<Map<String, dynamic>> normalizedTarget,
      ) async {
        final decoded = _decodeRepairLineList(raw);

        for (var index = 0; index < decoded.length; index++) {
          final normalized = _normalizeRepairLine(decoded[index]);
          if (normalized == null) continue;

          normalizedTarget.add(normalized);
          final total = _repairLineNumber(
            normalized['total'],
            fallback: 0.0,
          );
          normalizedTotal += total;

          await db.insert(
            'repair_lines_v57',
            {
              'id': '$repairId:$type:$index',
              'repair_id': repairId,
              'line_type': type,
              'name': normalized['name'],
              'qty': normalized['qty'],
              'price': normalized['price'],
              'total': normalized['total'],
              'notes': normalized['notes'],
              'created_at': repair['created_at'],
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await migrateType('part', repair['parts'], normalizedParts);
      await migrateType('work', repair['works'], normalizedWorks);

      final storedFileValue = _repairLineNumber(
        repair['fileValue'],
        fallback: 0.0,
      );

      await db.update(
        'repairs',
        {
          'parts': jsonEncode(normalizedParts),
          'works': jsonEncode(normalizedWorks),
          if ((normalizedTotal - storedFileValue).abs() > 0.01)
            'isLedgerSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [repairId],
      );
    }

    await db.execute('DROP TABLE IF EXISTS repair_lines;');
    await db.execute('ALTER TABLE repair_lines_v57 RENAME TO repair_lines;');
    await _ensureRepairLinesIndexes(db);
  }

  // =======================================================================
  // 🔄 تحديثات لاحقة — تركنا كودك كما هو دون حذف أي سطر
  // =======================================================================
  static Future<void> ensureRepairsSchema(DatabaseExecutor db) async {
    await _ensureColumn(db, 'repairs', 'status', 'TEXT');
    await _ensureColumn(db, 'repairs', 'quote_number', 'TEXT');
    await _ensureColumn(db, 'repairs', 'quote_valid_until', 'TEXT');
    await _ensureColumn(db, 'repairs', 'approved_at', 'TEXT');
    await _ensureColumn(db, 'repairs', 'approved_by', 'TEXT');
    await _ensureColumn(db, 'repairs', 'client_id', 'INTEGER'); // ← أضف هذا فقط
    await ensureP07IntakeSchema(db);
    await ensureP09WorkflowSchema(db);
    await _ensureRepairsExtraCols(db);
    await _ensureRepairsInvoiceIdCol(db);
    await _migrateRepairsInvoiceId(db);
    await _synchronizeRepairInvoiceLinks(db);
    await _ensureInvoicesIndexes(db);
    await _ensureColumn(db, 'repairs', 'total_paid_amount', 'REAL');
    await db.execute("""
  UPDATE repairs 
  SET total_paid_amount = paidAmount
  WHERE total_paid_amount IS NULL;
""");
  }

  /// P09 additive operational workflow schema.
  ///
  /// This table deliberately keeps estimate/approval/work-order state outside
  /// repairs.status because legacy accounting code still couples that column
  /// to invoice/GL events. No existing repair/accounting rows are rewritten.
  static Future<void> ensureP09WorkflowSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repair_workflow (
        repair_id TEXT PRIMARY KEY,
        stage TEXT NOT NULL DEFAULT 'DRAFT',
        damage_assessment TEXT NOT NULL DEFAULT '',
        quote_number TEXT,
        quote_valid_until TEXT,
        quote_sent_at TEXT,
        approved_at TEXT,
        approved_by TEXT,
        approval_method TEXT,
        approval_note TEXT,
        rejected_at TEXT,
        rejection_reason TEXT,
        work_order_started_at TEXT,
        work_order_number TEXT,
        responsible_employee_id TEXT,
        initial_qc_at TEXT,
        initial_qc_by TEXT,
        initial_qc_notes TEXT,
        qc_work_complete INTEGER NOT NULL DEFAULT 0,
        qc_finish_checked INTEGER NOT NULL DEFAULT 0,
        qc_cleanliness_checked INTEGER NOT NULL DEFAULT 0,
        qc_documentation_checked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_workflow_stage '
      'ON repair_workflow(stage);',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_workflow_responsible '
      'ON repair_workflow(responsible_employee_id);',
    );

    // P13 additive delivery/closure fields. Existing workflow/accounting rows
    // are never rebuilt or rewritten.
    await _ensureColumn(db, 'repair_workflow', 'final_qc_at', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'final_qc_by', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'final_qc_notes', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'final_qc_work_verified',
        'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'repair_workflow', 'final_qc_finish_verified',
        'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'repair_workflow', 'final_qc_cleanliness_verified',
        'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'repair_workflow',
        'final_qc_documentation_verified', 'INTEGER NOT NULL DEFAULT 0');
    await _ensureColumn(db, 'repair_workflow', 'ready_for_delivery_at', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'ready_for_delivery_by', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'delivered_at', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'delivered_by', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'handover_recipient', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'handover_method', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'handover_note', 'TEXT');
    await _ensureColumn(
        db, 'repair_workflow', 'handover_signature_path', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'closed_at', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'closed_by', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'closure_note', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'reopened_at', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'reopened_by', 'TEXT');
    await _ensureColumn(db, 'repair_workflow', 'reopen_reason', 'TEXT');
    await _ensureColumn(
        db, 'repair_workflow', 'reopen_count', 'INTEGER NOT NULL DEFAULT 0');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS repair_workflow_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        repair_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        from_stage TEXT,
        to_stage TEXT,
        actor_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(repair_id) REFERENCES repairs(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_repair_workflow_events_repair '
      'ON repair_workflow_events(repair_id, created_at);',
    );
  }

  /// P07 additive intake migration. Never drops/rebuilds customer tables.
  static Future<void> ensureP07IntakeSchema(DatabaseExecutor db) async {
    await _ensureColumn(db, 'repairs', 'odometer', 'INTEGER');
    await _ensureColumn(db, 'repairs', 'fuel_level', 'INTEGER');
    await _ensureColumn(db, 'repairs', 'previous_damage', 'TEXT');
    await _ensureColumn(db, 'repairs', 'customer_signature_path', 'TEXT');
    await _ensureColumn(db, 'repairs', 'intake_completed_at', 'TEXT');
  }

  static Future<void> _ensureColumn(
      DatabaseExecutor db, String table, String column, String type) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type;');
    }
  }

  static Future<void> _ensureRepairsExtraCols(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(repairs)');
    final cols = info.map((e) => e['name'] as String).toSet();

    Future<void> addCol(String name, String type) async {
      if (!cols.contains(name)) {
        await db.execute('ALTER TABLE repairs ADD COLUMN $name $type;');
      }
    }

    await addCol('status', 'TEXT');
    await addCol('quote_number', 'TEXT');
    await addCol('quote_valid_until', 'TEXT');
    await addCol('approved_at', 'TEXT');
    await addCol('approved_by', 'TEXT');

    await addCol('actualCost', 'REAL');
    await addCol('transferFromAccount', 'TEXT');
    await addCol('transferToAccount', 'TEXT');
    await addCol('transferCompany', 'TEXT');
    await addCol('transferDate', 'TEXT');
    await addCol('transferAmount', 'REAL');
    await addCol('transferImagePath', 'TEXT');
  }

  static Future<void> _ensureRepairsInvoiceIdCol(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(repairs)');
    final cols = info.map((e) => e['name'] as String).toSet();

    if (!cols.contains('invoice_id')) {
      await db.execute('ALTER TABLE repairs ADD COLUMN invoice_id TEXT;');
    }

    if (!cols.contains('invoiceId')) {
      await db.execute('ALTER TABLE repairs ADD COLUMN invoiceId TEXT;');
    }

    await db.execute('''
      UPDATE repairs
      SET invoice_id = invoiceId
      WHERE (invoice_id IS NULL OR TRIM(invoice_id) = '')
        AND (invoiceId IS NOT NULL AND TRIM(invoiceId) <> '');
    ''');
  }

  static Future<void> _migrateRepairsInvoiceId(DatabaseExecutor db) async {
    try {
      final rows =
          await db.rawQuery('SELECT id, invoiceId, invoice_id FROM repairs');

      for (final r in rows) {
        final id = r['id']?.toString();
        final oldVal = r['invoiceId']?.toString();
        final newVal = r['invoice_id']?.toString();
        if (id == null) continue;

        if ((newVal == null || newVal.trim().isEmpty) &&
            (oldVal != null && oldVal.trim().isNotEmpty)) {
          await db.update(
            'repairs',
            {'invoice_id': oldVal},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e) {
      print('⚠️ migrateRepairsInvoiceId error: $e');
    }
  }

  // P0.006 — invoices.repair_id is authoritative.
  // repairs.invoice_id is a compatibility cache for screens/models.
  static Future<void> _synchronizeRepairInvoiceLinks(
      DatabaseExecutor db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='invoices'",
    );
    if (table.isEmpty) return;

    await db.execute('''
      UPDATE repairs
      SET invoice_id = (
        SELECT i.id
        FROM invoices i
        WHERE i.repair_id = repairs.id
        ORDER BY i.rowid ASC
        LIMIT 1
      )
      WHERE EXISTS (
        SELECT 1 FROM invoices i WHERE i.repair_id = repairs.id
      );
    ''');

    // Keep the old camelCase column synchronized only when it already exists.
    final info = await db.rawQuery('PRAGMA table_info(repairs)');
    final hasLegacy = info.any((c) => c['name'] == 'invoiceId');
    if (hasLegacy) {
      await db.execute('''
        UPDATE repairs
        SET invoiceId = invoice_id
        WHERE COALESCE(invoice_id, '') <> ''
          AND COALESCE(invoiceId, '') <> COALESCE(invoice_id, '');
      ''');
    }
  }

  // =======================================================================
  // ⬆️ onUpgrade
  // =======================================================================
  static Future<void> onUpgrade(Database db, int oldV, int newV) async {
    await _createRepairImagesTable(db);

    if (oldV < 57) {
      await _rebuildRepairLinesV57(db);
    } else {
      await _createRepairLinesTable(db);
    }

    await ensureRepairsSchema(db);
  }

  // =======================================================================
  // 📌 READ APIs
  // =======================================================================
  static Future<Map<String, dynamic>> getRepairById(
      DatabaseExecutor db, String id) async {
    final result = await db.query(
      'repairs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty ? Map<String, dynamic>.from(result.first) : {};
  }

  static Future<void> updateRepairPaidAmount(
      DatabaseExecutor db, String repairId, double amount) async {
    await db.update(
      'repairs',
      {'paidAmount': amount},
      where: 'id = ?',
      whereArgs: [repairId],
    );
  }

  static Future<void> setRepairThumbnailPath({
    required DatabaseExecutor db,
    required String repairId,
    String? path,
  }) async {
    await SyncFoundationService.writeOn(
        db,
        (txn) => txn.update(
              'repairs',
              {
                'thumbnail_path': path,
                'thumbnail_updated_at': DateTime.now().toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [repairId],
            ));
  }

  static Future<String?> getRepairThumbnailPath(
      DatabaseExecutor db, String repairId) async {
    final result = await db.query(
      'repairs',
      columns: ['thumbnail_path'],
      where: 'id = ?',
      whereArgs: [repairId],
    );
    return result.isNotEmpty
        ? result.first['thumbnail_path']?.toString()
        : null;
  }

  static Future<String?> getThumbnailPath(
    DatabaseExecutor db,
    String repairId,
  ) async {
    return getRepairThumbnailPath(db, repairId);
  }

  // =======================================================================
  // 🧾 إنشاء فاتورة
  // =======================================================================
  static Future<String> createInvoiceForRepair({
    required DatabaseExecutor db,
    required String repairId,
    required int? clientId,
    required double total,
  }) async {
    if (total <= 0) {
      throw StateError('Cannot create invoice with total <= 0');
    }
    if (clientId == null || clientId <= 0) {
      throw StateError('Cannot create invoice without client_id');
    }

    final existing = await db.query(
      'invoices',
      columns: ['id'],
      where: 'repair_id = ?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final existingId = existing.first['id'].toString();
      await db.update(
        'repairs',
        {'invoice_id': existingId},
        where: 'id = ?',
        whereArgs: [repairId],
      );
      return existingId;
    }

    final invoiceId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'invoices',
      {
        'id': invoiceId,
        'repair_id': repairId,
        'client_id': clientId,
        'date': now,
        'subtotal': total,
        'vat_amount': 0.0,
        'vat': 0.0,
        'total': total,
        'paid': 0.0,
        'status': 'unpaid',
        'notes': null,
        'method': null,
        'note': null,
        'post_to_gl': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    await db.update(
      'repairs',
      {'invoice_id': invoiceId},
      where: 'id = ?',
      whereArgs: [repairId],
    );

    return invoiceId;
  }

  // =======================================================================
// 📸 جدول صور الإصلاح
// =======================================================================
  static Future<void> _createRepairImagesTable(DatabaseExecutor db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS repairs_images(
      id TEXT PRIMARY KEY,
      repair_id TEXT NOT NULL,
      path TEXT NOT NULL,
      created_at TEXT
    )
  ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repairs_images_repair ON repairs_images(repair_id);');
  }
}
