import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_financial_truth_service.dart';
// 📁 lib/features/repairs/services/repairs_service.dart
//
// النسخة النهائية بالكامل — متوافقة مع DB v36 ومصححة مشكلة total_paid_amount
// وتعمل مع RepairDetailsScreen + ReceiptVoucherScreen
//
// • updateTotalsFromPayments: يحسب SUM(amount) من جدول payments ويحدّث:
//      total_paid_amount + paymentStatus
// • معالجة الصور + الغلاف (thumbnail)
// • CRUD كامل
// • متوافق مع model Repair الحالي بدون أي تضارب
//
// جاهز للاستبدال الكامل

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as im;

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/core/services/events/app_event_bus.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repair_auto_accounting_service.dart';

class RepairsService {
  final Database db;
  RepairsService(this.db);

  static Future<RepairsService> instance() async {
    final db = await DBService.database;
    return RepairsService(db);
  }

  // ======================== تحديث إجمالي المدفوعات ===========================
  Future<void> updateTotalsFromPayments(String repairId) async {
    // مجموع المدفوعات من جدول payments
    final totalPaid =
        await RepairFinancialTruthService.paidForRepair(repairId, executor: db);

    // قيمة الملف الأصلية
    final r = await db.rawQuery(
      'SELECT fileValue FROM repairs WHERE id = ? LIMIT 1',
      [repairId],
    );

    final fileValue =
        r.isNotEmpty ? (r.first['fileValue'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // تحديد حالة السداد
    String paymentStatus;
    if (fileValue <= 0 || totalPaid >= fileValue) {
      paymentStatus = 'مسدد';
    } else if (totalPaid > 0) {
      paymentStatus = 'مسدد جزئي';
    } else {
      paymentStatus = 'غير مسدد';
    }

    // تحديث جدول repairs
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              'repairs',
              {
                'total_paid_amount': totalPaid,
                'paymentStatus': paymentStatus,
              },
              where: 'id = ?',
              whereArgs: [repairId],
            ));
  }

  // ============================== CREATE =====================================
  Future<String> createRepair(Repair repair) async {
    final id = repair.id.isEmpty ? const Uuid().v4() : repair.id;

    await SyncFoundationService.transaction(db, (txn) async {
      final data = repair.copyWith(id: id).toMap();
      await txn.insert('repairs', data,
          conflictAlgorithm: ConflictAlgorithm.replace);

      await _enableLedgerFlags(txn, id);

      final clientId = await _extractClientId(txn, id);
      if (clientId != null && clientId > 0) {
        try {
          await DBService.ensureClientAccount(clientId);
        } catch (_) {}
      }
    });

    AppEventBus.emit(RepairCreated(repairId: id));
    return id;
  }

  // ============================== UPDATE =====================================
  Future<int> updateRepair(Repair repair) async {
    if (repair.id.isEmpty) throw ArgumentError('repair.id is required');

    return await SyncFoundationService.transaction<int>(db, (txn) async {
      final data = repair.toMap()..remove('invoice_id');

      final rows = await txn.update(
        'repairs',
        data,
        where: 'id = ?',
        whereArgs: [repair.id],
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await _enableLedgerFlags(txn, repair.id);

      final clientId = await _extractClientId(txn, repair.id);
      if (clientId != null && clientId > 0) {
        try {
          await DBService.ensureClientAccount(clientId);
        } catch (_) {}
      }

      return rows;
    });
  }

  // ============================== DELETE =====================================
  Future<int> deleteRepair(String id) async {
    await RepairAutoAccountingService.deleteRepair(id);
    return 1;
  }

  // ============================= GET =========================================
  Future<Repair?> getById(String id) async {
    final rows =
        await db.query('repairs', where: 'id = ?', whereArgs: [id], limit: 1);

    if (rows.isEmpty) return null;

    final map = Map<String, dynamic>.from(rows.first);

    final imgs = await listImagePaths(id);
    map['imagePaths'] = imgs;

    return Repair.fromMap(map);
  }

  // ============================= LIST ========================================
  Future<List<Repair>> list({
    String? from,
    String? to,
    String? repairStatus,
    String? paymentStatus,
    bool insuranceOnly = false,
    String? search,
    bool newestFirst = true,
    int? limit,
    int? offset,
  }) async {
    // Intake timestamps are UTC; legacy timestamps without an offset are local.
    const receivedDay =
        "date(CASE WHEN receivedDate LIKE '%Z' OR (length(receivedDate)>19 AND substr(receivedDate,-6,1) IN ('+','-')) THEN datetime(receivedDate,'localtime') ELSE receivedDate END)";
    final where = <String>["(status IS NULL OR status <> ?)"];
    final args = <Object?>[RepairAutoAccountingService.cancelledStatus];

    if (from != null && from.isNotEmpty) {
      where.add('$receivedDay >= date(?)');
      args.add(from);
    }

    if (to != null && to.isNotEmpty) {
      where.add('$receivedDay <= date(?)');
      args.add(to);
    }

    if (repairStatus != null && repairStatus.isNotEmpty) {
      where.add('vehicleStatus = ?');
      args.add(repairStatus);
    }

    if (paymentStatus != null && paymentStatus.isNotEmpty) {
      where.add('paymentStatus = ?');
      args.add(paymentStatus);
    }

    if (insuranceOnly) {
      where.add(
          "(beneficiaryType = 'شركة تأمين' OR beneficiaryType = 'INSURANCE')");
    }

    if (search != null && search.trim().isNotEmpty) {
      final q = '%${search.trim()}%';
      where.add('('
          'vehicleModel LIKE ? OR '
          'vehicleType LIKE ? OR '
          'vehicleNumber LIKE ? OR '
          'beneficiaryName LIKE ? OR '
          'invoiceNumber LIKE ? OR '
          'notes LIKE ?'
          ')');
      args.addAll([q, q, q, q, q, q]);
    }

    final order = newestFirst ? 'DESC' : 'ASC';
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(" AND ")}';
    final lim = limit != null ? ' LIMIT $limit ' : '';
    final off = (offset != null && offset > 0) ? ' OFFSET $offset ' : '';

    final rows = await db.rawQuery('''
      SELECT * FROM repairs
      $whereSql
      ORDER BY datetime(receivedDate) $order, rowid $order
      $lim $off
    ''', args);

    final out = <Repair>[];
    final ids = rows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final imagesByRepair = await _listImagePathsForRepairIds(ids);

    for (final m in rows) {
      final map = Map<String, dynamic>.from(m);
      final id = map['id']?.toString() ?? '';
      map['imagePaths'] = imagesByRepair[id] ?? const <String>[];
      try {
        out.add(Repair.fromMap(map));
      } catch (_) {}
    }

    return out;
  }

  Future<Map<String, List<String>>> _listImagePathsForRepairIds(
    List<String> repairIds,
  ) async {
    if (repairIds.isEmpty) return const <String, List<String>>{};
    await _ensureImagesTable();

    final result = <String, List<String>>{};
    const chunkSize = 400;
    for (int start = 0; start < repairIds.length; start += chunkSize) {
      final end = math.min(start + chunkSize, repairIds.length);
      final chunk = repairIds.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT repair_id, path FROM repairs_images '
        'WHERE repair_id IN ($placeholders) '
        'ORDER BY repair_id ASC, datetime(created_at) ASC, rowid ASC',
        chunk,
      );

      for (final row in rows) {
        final id = row['repair_id']?.toString() ?? '';
        final path = row['path']?.toString() ?? '';
        if (id.isEmpty || path.isEmpty) continue;
        result.putIfAbsent(id, () => <String>[]).add(path);
      }
    }
    return result;
  }

  // ========================= Images table ====================================
  Future<void> _ensureImagesTable() async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS repairs_images (
        id TEXT PRIMARY KEY,
        repair_id TEXT NOT NULL,
        path TEXT NOT NULL,
        created_at TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_repimgs_rid ON repairs_images(repair_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_repimgs_unique ON repairs_images(repair_id, path)');
  }

  Future<void> addImagePath({
    required String repairId,
    required String path,
  }) async {
    await _ensureImagesTable();

    await db.insert(
      'repairs_images',
      {
        'id': const Uuid().v4(),
        'repair_id': repairId,
        'path': path,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // تحديث الغلاف تلقائياً
    try {
      await autoSelectCoverAndSave(repairId: repairId);
    } catch (_) {}
  }

  Future<void> removeImagePath({required String path}) async {
    await _ensureImagesTable();

    String? repairId;

    try {
      final r = await db.query(
        'repairs_images',
        columns: ['repair_id'],
        where: 'path = ?',
        whereArgs: [path],
        limit: 1,
      );
      repairId = r.isNotEmpty ? r.first['repair_id']?.toString() : null;
    } catch (_) {}

    await YallaStorageService.deleteStoredFile(path);

    await db.delete('repairs_images', where: 'path = ?', whereArgs: [path]);

    try {
      final guessed = repairId ?? _guessRepairIdFromPath(path);
      if (guessed != null) {
        await autoSelectCoverAndSave(repairId: guessed);
      }
    } catch (_) {}
  }

  Future<List<String>> listImagePaths(String repairId) async {
    await _ensureImagesTable();

    final rows = await db.query(
      'repairs_images',
      columns: ['path'],
      where: 'repair_id = ?',
      whereArgs: [repairId],
      orderBy: 'created_at ASC',
    );

    return rows
        .map((e) => e['path'].toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ========================= Cover Thumbnail =================================
  Future<String?> autoSelectCoverAndSave({required String repairId}) async {
    final paths = await listImagePaths(repairId);

    if (paths.isEmpty) {
      await DBService.setRepairThumbnailPath(repairId: repairId, path: null);
      return null;
    }

    final ranked = <_ImgScore>[];
    double maxSharp = 0;
    double maxCenterSharp = 0;
    double maxContrast = 0;

    for (final pth in paths) {
      final resolved = await YallaStorageService.resolveExistingPath(pth);
      if (resolved == null) continue;
      final s = await _scoreImage(resolved);
      if (s == null) continue;
      final portable = s.copyWith(path: pth);
      maxSharp = math.max(maxSharp, portable.sharpness);
      maxCenterSharp = math.max(maxCenterSharp, portable.centerSharpness);
      maxContrast = math.max(maxContrast, portable.contrastScore);
      ranked.add(portable);
    }

    if (ranked.isEmpty) {
      await DBService.setRepairThumbnailPath(repairId: repairId, path: null);
      return null;
    }

    for (var i = 0; i < ranked.length; i++) {
      final s = ranked[i];
      final normSharp = maxSharp <= 0 ? 0.0 : s.sharpness / maxSharp;
      final normCenter =
          maxCenterSharp <= 0 ? 0.0 : s.centerSharpness / maxCenterSharp;
      final normContrast =
          maxContrast <= 0 ? 0.0 : s.contrastScore / maxContrast;
      final total = 0.45 * normSharp +
          0.25 * normCenter +
          0.15 * s.brightnessScore +
          0.10 * normContrast +
          0.05 * s.orientationScore;
      ranked[i] = s.copyWith(total: total);
    }

    ranked.sort((a, b) => b.total.compareTo(a.total));
    final bestPath = ranked.first.path;

    await DBService.setRepairThumbnailPath(repairId: repairId, path: bestPath);

    return bestPath;
  }

  // ============================== Helpers ====================================
  Future<void> _enableLedgerFlags(DatabaseExecutor txn, String repairId) async {
    try {
      final info = await txn.rawQuery("PRAGMA table_info(repairs)");
      final cols = info.map((m) => m['name'].toString()).toSet();

      if (cols.contains('isLedgerEnabled') && cols.contains('isLedgerSynced')) {
        await txn.update(
          'repairs',
          {
            'isLedgerEnabled': 1,
            'isLedgerSynced': 0,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [repairId],
        );
      }
    } catch (_) {}
  }

  Future<int?> _extractClientId(DatabaseExecutor txn, String repairId) async {
    final r = await txn.query(
      'repairs',
      columns: ['client_id'],
      where: 'id=?',
      whereArgs: [repairId],
      limit: 1,
    );

    if (r.isEmpty) return null;

    final v = r.first['client_id'];
    if (v == null) return null;
    if (v is int) return v;

    return int.tryParse(v.toString());
  }

  String? _guessRepairIdFromPath(String path) {
    final name = p.basename(path);
    final m = RegExp(r'rep_([a-f0-9\-]{16,})_').firstMatch(name);
    return m?.group(1);
  }

  // ============================= Image Scoring ================================
  Future<_ImgScore?> _scoreImage(String path) async {
    final data = await compute<String, Map<String, double>?>(
      _scoreImagePayload,
      path,
    );
    if (data == null) return null;
    return _ImgScore(
      path: path,
      sharpness: data['sharpness'] ?? 0,
      centerSharpness: data['centerSharpness'] ?? 0,
      brightnessScore: data['brightnessScore'] ?? 0,
      contrastScore: data['contrastScore'] ?? 0,
      orientationScore: data['orientationScore'] ?? 0,
      total: 0,
    );
  }

  // -------------------------------------------------------------------
  // 🔄 تحديث مسار الـ Thumbnail داخل repairs
  // -------------------------------------------------------------------
  Future<void> updateThumbnail({
    required String repairId,
    required String? thumbPath,
  }) async {
    await SyncFoundationService.writeOn(
        db,
        (syncTxn) => syncTxn.update(
              'repairs',
              {'thumbnail_path': thumbPath},
              where: 'id = ?',
              whereArgs: [repairId],
            ));
  }
}

Map<String, double>? _scoreImagePayload(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final image = im.decodeImage(file.readAsBytesSync());
    if (image == null) return null;

    final originalWidth = image.width;
    final originalHeight = image.height;
    final scaled = math.max(originalWidth, originalHeight) > 512
        ? (originalWidth >= originalHeight
            ? im.copyResize(image, width: 512)
            : im.copyResize(image, height: 512))
        : image;
    final gray = im.grayscale(scaled);

    double sharpSum = 0;
    int sharpCount = 0;
    double centerSharpSum = 0;
    int centerSharpCount = 0;
    final centerLeft = (gray.width * 0.15).round();
    final centerRight = (gray.width * 0.85).round();
    final centerTop = (gray.height * 0.12).round();
    final centerBottom = (gray.height * 0.88).round();

    for (int y = 1; y < gray.height - 1; y++) {
      for (int x = 1; x < gray.width - 1; x++) {
        final left = gray.getPixel(x - 1, y).r;
        final right = gray.getPixel(x + 1, y).r;
        final up = gray.getPixel(x, y - 1).r;
        final down = gray.getPixel(x, y + 1).r;
        final detail = (right - left).abs() + (down - up).abs();
        sharpSum += detail;
        sharpCount++;
        if (x >= centerLeft &&
            x <= centerRight &&
            y >= centerTop &&
            y <= centerBottom) {
          centerSharpSum += detail;
          centerSharpCount++;
        }
      }
    }

    final sharpness = sharpCount == 0 ? 0.0 : sharpSum / (sharpCount * 255.0);
    final centerSharpness = centerSharpCount == 0
        ? 0.0
        : centerSharpSum / (centerSharpCount * 255.0);

    double mean = 0;
    double meanSq = 0;
    int samples = 0;
    for (int y = 0; y < gray.height; y += 4) {
      for (int x = 0; x < gray.width; x += 4) {
        final value = gray.getPixel(x, y).r / 255.0;
        mean += value;
        meanSq += value * value;
        samples++;
      }
    }
    if (samples > 0) {
      mean /= samples;
      meanSq /= samples;
    }

    final brightnessScore = math.max(0.0, 1.0 - (mean - 0.58).abs() * 2.2);
    final variance = math.max(0.0, meanSq - (mean * mean));
    return <String, double>{
      'sharpness': sharpness,
      'centerSharpness': centerSharpness,
      'brightnessScore': brightnessScore,
      'contrastScore': math.sqrt(variance),
      'orientationScore': originalWidth >= originalHeight ? 1.0 : 0.45,
    };
  } catch (_) {
    return null;
  }
}

// ============================= Event =========================================
class RepairCreated extends AppEvent {
  final String repairId;
  RepairCreated({required this.repairId});
}

// ============================== Score Model ==================================
class _ImgScore {
  final String path;
  final double sharpness;
  final double centerSharpness;
  final double brightnessScore;
  final double contrastScore;
  final double orientationScore;
  final double total;

  _ImgScore({
    required this.path,
    required this.sharpness,
    required this.centerSharpness,
    required this.brightnessScore,
    required this.contrastScore,
    required this.orientationScore,
    required this.total,
  });

  _ImgScore copyWith({String? path, double? total}) => _ImgScore(
        path: path ?? this.path,
        sharpness: sharpness,
        centerSharpness: centerSharpness,
        brightnessScore: brightnessScore,
        contrastScore: contrastScore,
        orientationScore: orientationScore,
        total: total ?? this.total,
      );
}
