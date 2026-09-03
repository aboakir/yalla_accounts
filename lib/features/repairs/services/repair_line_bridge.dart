import 'package:yalla_accounts/core/services/db_service.dart';

/// Canonical bridge between the repair intake/edit flows and Repair Details.
///
/// Reads the existing `repair_lines` table without changing its schema and
/// normalizes desktop-compatible line maps to: name / qty / price / total.
class RepairLineBridge {
  const RepairLineBridge._();

  static Future<RepairLineSnapshot> load(Object repairId) async {
    final db = await DBService.database;
    final info = await db.rawQuery('PRAGMA table_info(repair_lines)');
    final columns = info
        .map((row) => (row['name'] ?? '').toString())
        .where((name) => name.isNotEmpty)
        .toSet();

    String? firstColumn(List<String> candidates) {
      for (final candidate in candidates) {
        if (columns.contains(candidate)) return candidate;
      }
      return null;
    }

    final repairColumn = firstColumn(const ['repair_id', 'repairId']);
    final typeColumn = firstColumn(const ['type', 'line_type', 'category']);
    final nameColumn = firstColumn(const ['name', 'description', 'item_name']);
    final qtyColumn = firstColumn(const ['qty', 'quantity']);
    final priceColumn = firstColumn(const ['price', 'unit_price', 'unitPrice']);
    final totalColumn = firstColumn(const ['total', 'line_total', 'amount']);

    if (repairColumn == null ||
        typeColumn == null ||
        nameColumn == null ||
        qtyColumn == null ||
        priceColumn == null ||
        totalColumn == null) {
      return const RepairLineSnapshot();
    }

    final rows = await db.query(
      'repair_lines',
      where: '"$repairColumn" = ?',
      whereArgs: <Object?>[repairId],
    );

    final works = <Map<String, dynamic>>[];
    final parts = <Map<String, dynamic>>[];

    double asDouble(Object? value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? 0.0;
    }

    bool isPartType(String raw) {
      final lower = raw.trim().toLowerCase();
      return lower == 'part' ||
          lower.contains('part') ||
          raw.contains('قطعة') ||
          raw.contains('قطع');
    }

    bool isWorkType(String raw) {
      final lower = raw.trim().toLowerCase();
      return lower == 'work' ||
          lower.contains('work') ||
          lower.contains('repair') ||
          lower.contains('service') ||
          lower.contains('labor') ||
          lower.contains('labour') ||
          raw.contains('عمل') ||
          raw.contains('أعمال') ||
          raw.contains('إصلاح') ||
          raw.contains('اصلاح');
    }

    for (final row in rows) {
      final name = (row[nameColumn] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final qty = asDouble(row[qtyColumn]);
      final price = asDouble(row[priceColumn]);
      final storedTotal = asDouble(row[totalColumn]);
      final normalized = <String, dynamic>{
        'name': name,
        'qty': qty,
        'price': price,
        'total': storedTotal != 0 ? storedTotal : qty * price,
      };

      final type = (row[typeColumn] ?? '').toString();
      if (isPartType(type)) {
        parts.add(normalized);
      } else if (isWorkType(type)) {
        works.add(normalized);
      }
    }

    return RepairLineSnapshot(works: works, parts: parts);
  }
}

class RepairLineSnapshot {
  const RepairLineSnapshot({
    this.works = const <Map<String, dynamic>>[],
    this.parts = const <Map<String, dynamic>>[],
  });

  final List<Map<String, dynamic>> works;
  final List<Map<String, dynamic>> parts;

  int get count => works.length + parts.length;
}
