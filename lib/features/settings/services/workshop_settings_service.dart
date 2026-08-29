// 📁 lib/features/settings/services/workshop_settings_service.dart
//
// WorkshopSettingsService — النسخة الجديدة مع نظام safeAdd الكامل
// --------------------------------------------------------------
// - إنشاء جدول workshop_settings
// - إضافة أي عمود ناقص تلقائيًا بدون حذف قاعدة البيانات
// - دعم كل الحقول الجديدة: الاسم، العنوان، المدينة، الهواتف، البريد، الشعار…
// --------------------------------------------------------------

import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/settings/models/workshop_settings.dart';

class WorkshopSettingsService {
  WorkshopSettingsService._();

  static final WorkshopSettingsService instance = WorkshopSettingsService._();

  static const table = 'workshop_settings';

  // ============================================================
  // GET SETTINGS
  // ============================================================
  Future<WorkshopSettings?> getSettings() async {
    final db = await DBService.database;
    final rows = await db.query(table, limit: 1);
    if (rows.isEmpty) return null;
    return WorkshopSettings.fromMap(rows.first);
  }

  Future<WorkshopSettings> getOrDefaults() async {
    final current = await getSettings();
    return current ?? WorkshopSettings.defaults();
  }

  // ============================================================
  // SAVE SETTINGS
  // ============================================================
  Future<void> saveSettings(WorkshopSettings settings) async {
    final db = await DBService.database;

    final data = Map<String, Object?>.from(settings.toMap())
      ..['id'] = 1
      ..['updated_at'] = DateTime.now().toIso8601String();

    final count = await db.update(
      table,
      data,
      where: 'id = ?',
      whereArgs: const [1],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    if (count == 0) {
      await db.insert(
        table,
        {
          ...data,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ============================================================
  // CREATE TABLE (with full auto-migration)
  // ============================================================
  static Future<void> createTable(DatabaseExecutor db) async {
    // إنشاء الجدول الأساسي إذا لم يكن موجودًا
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        id INTEGER PRIMARY KEY,
        workshopName TEXT,
        address TEXT,
        city TEXT,
        phone1 TEXT,
        phone2 TEXT,
        email TEXT,
        logoPath TEXT,
        workStart TEXT,
        workEnd TEXT,
        dailyHours REAL,
        breakMinutes INTEGER,
        weekWorkdays TEXT,
        hourlyRate REAL,
        overtimeRate REAL,
        latePenalty REAL,
        earlyLeavePenalty REAL,
        created_at TEXT,
        updated_at TEXT
      )
    ''');

    // ============================================================
    // 🔥 SAFE MIGRATION — No DB delete required
    // ============================================================
    await _safeAdd(db, "workshopName", "TEXT");
    await _safeAdd(db, "address", "TEXT");
    await _safeAdd(db, "city", "TEXT");
    await _safeAdd(db, "phone1", "TEXT");
    await _safeAdd(db, "phone2", "TEXT");
    await _safeAdd(db, "email", "TEXT");
    await _safeAdd(db, "logoPath", "TEXT");

    await _safeAdd(db, "workStart", "TEXT");
    await _safeAdd(db, "workEnd", "TEXT");
    await _safeAdd(db, "dailyHours", "REAL");
    await _safeAdd(db, "breakMinutes", "INTEGER");

    await _safeAdd(db, "weekWorkdays", "TEXT");

    await _safeAdd(db, "hourlyRate", "REAL");
    await _safeAdd(db, "overtimeRate", "REAL");
    await _safeAdd(db, "latePenalty", "REAL");
    await _safeAdd(db, "earlyLeavePenalty", "REAL");

    await _safeAdd(db, "created_at", "TEXT");
    await _safeAdd(db, "updated_at", "TEXT");

    // Index مهم للحضور
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ws_work_time ON $table(workStart, workEnd);',
    );

    // إضافة سجل افتراضي إذا لا يوجد
    final exists = await db.query(table, columns: ['id'], limit: 1);
    if (exists.isEmpty) {
      final now = DateTime.now().toIso8601String();
      await db.insert(table, {
        'id': 1,
        'workStart': '09:00',
        'workEnd': '17:00',
        'dailyHours': 8.0,
        'breakMinutes': 0,
        'weekWorkdays': '1,2,3,4,5,6',
        'phone1': "",
        'phone2': "",
        'address': "",
        'city': "",
        'email': "",
        'logoPath': "",
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  // ============================================================
  // INTERNAL — SAFE COLUMN ADDER
  // ============================================================
  static Future<void> _safeAdd(
    DatabaseExecutor db,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery("PRAGMA table_info($table);");
    final exists = info.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute("ALTER TABLE $table ADD COLUMN $column $type;");
    }
  }
}
