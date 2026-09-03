import 'package:yalla_accounts/core/services/db_service.dart';

enum RepairPayerKind {
  customer,
  insurance,
  mixed,
  legacyUnknown,
}

/// Reads payer semantics from the existing repairs row without changing schema.
///
/// Backward-compatibility rule:
/// legacy `cash` by itself is NOT enough to classify an old file as customer-paid.
/// Only the explicit P07 marker can turn a cash row into customer-paid semantics.
class RepairPayerBridge {
  const RepairPayerBridge._();

  static Future<RepairPayerKind> load(Object repairId) async {
    final id = repairId.toString().trim();
    if (id.isEmpty) return RepairPayerKind.legacyUnknown;

    final db = await DBService.database;
    final info = await db.rawQuery('PRAGMA table_info(repairs)');
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

    final idColumn = firstColumn(const ['id']);
    if (idColumn == null) return RepairPayerKind.legacyUnknown;

    final notesColumn = firstColumn(const ['notes', 'note', 'remarks']);
    final paymentColumn =
        firstColumn(const ['paymentType', 'payment_type', 'payer_type']);

    final selected = <String>[idColumn];
    if (notesColumn != null) selected.add(notesColumn);
    if (paymentColumn != null) selected.add(paymentColumn);

    final rows = await db.query(
      'repairs',
      columns: selected,
      where: '"$idColumn" = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return RepairPayerKind.legacyUnknown;

    final row = rows.first;
    final notes =
        notesColumn == null ? '' : (row[notesColumn] ?? '').toString();

    if (notes.contains('[YALLA_PAYER] العميل')) {
      return RepairPayerKind.customer;
    }
    if (notes.contains('[YALLA_PAYER] شركة تأمين')) {
      return RepairPayerKind.insurance;
    }
    if (notes.contains('[YALLA_PAYER] مختلط')) {
      return RepairPayerKind.mixed;
    }

    final payment = paymentColumn == null
        ? ''
        : (row[paymentColumn] ?? '').toString().trim().toLowerCase();

    if (payment == 'insurance') return RepairPayerKind.insurance;
    if (payment == 'mixed') return RepairPayerKind.mixed;

    // Important: old records often used `cash` as a default even when an
    // insurance relationship existed. Preserve their legacy UI.
    return RepairPayerKind.legacyUnknown;
  }
}
