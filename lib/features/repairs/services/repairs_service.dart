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
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as im;

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/events/app_event_bus.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

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
    final sumRow = await db.rawQuery(
      'SELECT IFNULL(SUM(amount),0) AS total FROM payments WHERE repair_id = ?',
      [repairId],
    );

    final totalPaid = (sumRow.first['total'] as num?)?.toDouble() ?? 0.0;

    // قيمة الملف الأصلية
    final r = await db.rawQuery(
      'SELECT fileValue FROM repairs WHERE id = ? LIMIT 1',
      [repairId],
    );

    final fileValue =
        r.isNotEmpty ? (r.first['fileValue'] as num?)?.toDouble() ?? 0.0 : 0.0;

    // تحديد حالة السداد
    String paymentStatus;
    if (totalPaid >= fileValue && fileValue > 0) {
      paymentStatus = 'مسدد';
    } else if (totalPaid > 0) {
      paymentStatus = 'مسدد جزئي';
    } else {
      paymentStatus = 'غير مسدد';
    }

    // تحديث جدول repairs
    await db.update(
      'repairs',
      {
        'total_paid_amount': totalPaid,
        'paymentStatus': paymentStatus,
      },
      where: 'id = ?',
      whereArgs: [repairId],
    );
  }

  // ============================== CREATE =====================================
  Future<String> createRepair(Repair repair) async {
    final id = repair.id.isEmpty ? const Uuid().v4() : repair.id;

    await db.transaction((txn) async {
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

    return await db.transaction<int>((txn) async {
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
    return db.transaction<int>((txn) async {
      final invoices = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM invoices WHERE repair_id = ?',
              [id],
            ),
          ) ??
          0;

      final payments = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM payments '
              'WHERE repair_id = ? OR relatedRepairId = ?',
              [id, id],
            ),
          ) ??
          0;

      final glLines = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM gl_lines WHERE repair_id = ?',
              [id],
            ),
          ) ??
          0;

      if (invoices > 0 || payments > 0 || glLines > 0) {
        throw StateError(
          'Cannot delete an invoiced/accounted repair. '
          'Use a formal void/reversal workflow.',
        );
      }

      await _ensureImagesTable();

      final imgRows = await txn.query(
        'repairs_images',
        columns: ['path'],
        where: 'repair_id = ?',
        whereArgs: [id],
      );

      final paths = imgRows
          .map((e) => e['path'].toString())
          .where((e) => e.isNotEmpty)
          .toList();

      for (final pth in paths) {
        _deletePhysicalFile(pth);
      }

      await txn.delete(
        'repairs_images',
        where: 'repair_id = ?',
        whereArgs: [id],
      );

      try {
        final thumb = await DBService.getRepairThumbnailPath(id);
        if (thumb != null && thumb.isNotEmpty) _deletePhysicalFile(thumb);
        await DBService.setRepairThumbnailPath(repairId: id, path: null);
      } catch (_) {}

      return txn.delete(
        'repairs',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
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
    final where = <String>[];
    final args = <Object?>[];

    if (from != null && from.isNotEmpty) {
      where.add('date(receivedDate) >= date(?)');
      args.add(from);
    }

    if (to != null && to.isNotEmpty) {
      where.add('date(receivedDate) <= date(?)');
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

    for (final m in rows) {
      final map = Map<String, dynamic>.from(m);
      final imgs = await listImagePaths(map['id'].toString());
      map['imagePaths'] = imgs;
      try {
        out.add(Repair.fromMap(map));
      } catch (_) {}
    }

    return out;
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

    _deletePhysicalFile(path);

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

    for (final pth in paths) {
      final s = _scoreImage(pth);
      if (s == null) continue;
      maxSharp = math.max(maxSharp, s.sharpness);
      ranked.add(s);
    }

    if (ranked.isEmpty) {
      await DBService.setRepairThumbnailPath(repairId: repairId, path: null);
      return null;
    }

    for (var i = 0; i < ranked.length; i++) {
      final s = ranked[i];
      final normSharp = maxSharp <= 0 ? 0.0 : s.sharpness / maxSharp;
      final total =
          0.6 * normSharp + 0.3 * s.brightnessScore + 0.1 * s.orientationScore;
      ranked[i] = s.copyWith(total: total);
    }

    ranked.sort((a, b) => b.total.compareTo(a.total));
    final bestPath = ranked.first.path;

    final thumbPath = await _makeThumbnail(bestPath, repairId: repairId);

    await DBService.setRepairThumbnailPath(repairId: repairId, path: thumbPath);

    return thumbPath;
  }

  Future<String> _makeThumbnail(String srcPath,
      {required String repairId}) async {
    final bytes = File(srcPath).readAsBytesSync();
    final decoded = im.decodeImage(bytes);

    if (decoded == null) throw StateError('decode failed');

    final square = im.copyResizeCropSquare(decoded, size: 160);

    final dir =
        Directory(p.join(File(srcPath).parent.parent.path, 'repairs_thumbs'));

    if (!dir.existsSync()) dir.createSync(recursive: true);

    final out = p.join(dir.path, 'thumb_rep_$repairId.jpg');

    File(out).writeAsBytesSync(im.encodeJpg(square, quality: 85));

    return out;
  }

  // ============================== Helpers ====================================
  void _deletePhysicalFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

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
  _ImgScore? _scoreImage(String path) {
    try {
      final f = File(path);
      if (!f.existsSync()) return null;

      final bytes = f.readAsBytesSync();
      final img = im.decodeImage(bytes);

      if (img == null) return null;

      final w = img.width;
      final h = img.height;

      final scaled =
          (math.max(w, h) > 512) ? im.copyResize(img, width: 512) : img;

      final g = im.grayscale(scaled);

      // sharpness
      double sum = 0;
      int count = 0;

      for (int y = 1; y < g.height - 1; y++) {
        for (int x = 1; x < g.width - 1; x++) {
          final l = g.getPixel(x - 1, y).r;
          final r = g.getPixel(x + 1, y).r;
          final u = g.getPixel(x, y - 1).r;
          final d = g.getPixel(x, y + 1).r;

          final dx = (r - l).abs();
          final dy = (d - u).abs();

          sum += dx + dy;
          count++;
        }
      }

      final sharpness = (count == 0) ? 0.0 : sum / (count * 255.0);

      // brightness
      double mean = 0.0;
      int samples = 0;

      for (int y = 0; y < g.height; y += 4) {
        for (int x = 0; x < g.width; x += 4) {
          mean += g.getPixel(x, y).r / 255.0;
          samples++;
        }
      }

      if (samples > 0) mean /= samples;

      final brightnessScore = math.max(0.0, 1.0 - (mean - 0.6).abs() * 2.0);

      final orientationScore = (w >= h) ? 1.0 : 0.0;

      return _ImgScore(
        path: path,
        sharpness: sharpness,
        brightnessScore: brightnessScore,
        orientationScore: orientationScore,
        total: 0.0,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------
  // 🔄 تحديث مسار الـ Thumbnail داخل repairs
  // -------------------------------------------------------------------
  Future<void> updateThumbnail({
    required String repairId,
    required String? thumbPath,
  }) async {
    await db.update(
      'repairs',
      {'thumbnail_path': thumbPath},
      where: 'id = ?',
      whereArgs: [repairId],
    );
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
  final double brightnessScore;
  final double orientationScore;
  final double total;

  _ImgScore({
    required this.path,
    required this.sharpness,
    required this.brightnessScore,
    required this.orientationScore,
    required this.total,
  });

  _ImgScore copyWith({double? total}) => _ImgScore(
        path: path,
        sharpness: sharpness,
        brightnessScore: brightnessScore,
        orientationScore: orientationScore,
        total: total ?? this.total,
      );
}
