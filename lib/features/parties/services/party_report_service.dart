import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'party_financial_service.dart';

class PartyReportDocument {
  const PartyReportDocument(this.kind, this.header, this.items, this.vehicle);
  final String kind;
  final Map<String, Object?> header;
  final List<Map<String, Object?>> items;
  final Map<String, Object?> vehicle;
}

class DetailedPartyReport {
  const DetailedPartyReport(
      this.statement, this.documents, this.payments, this.dates);
  final PartyLedgerStatement statement;
  final List<PartyReportDocument> documents;
  final List<Map<String, Object?>> payments;
  final Map<int, String> dates;
}

class PartyReportService {
  static Future<DetailedPartyReport> load(
      {required String role,
      required Object legacyId,
      DateTime? from,
      DateTime? to,
      Database? database}) async {
    final db = database ?? await DBService.database;
    return db.transaction((txn) async {
      final statement = await PartyFinancialService.statement(
          role: role,
          legacyId: legacyId,
          combined: true,
          from: from,
          to: to,
          executor: txn);
      final documents = <PartyReportDocument>[];
      final payments = <Map<String, Object?>>[];
      final dates = <int, String>{};
      final seen = <String>{};
      final tables = (await txn
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'])
          .toSet();
      final roles = await txn.query('party_roles',
          where: 'party_id=?', whereArgs: [statement.partyId]);
      String? legacy(String kind) {
        for (final r in roles) {
          if (r['role'] == kind) return r['legacy_id']?.toString();
        }
        return null;
      }

      Future<List<Map<String, Object?>>> find(
          String table, String field, Object value) async {
        if (!tables.contains(table)) return [];
        return txn.query(table, where: '$field=?', whereArgs: [value]);
      }

      for (final id in statement.lines.map((l) => l.entryId).toSet()) {
        final entries = await find('gl_entries', 'id', id);
        if (entries.isNotEmpty)
          dates[id] = entries.first['date']?.toString() ?? '';
        final vouchers = await find('vouchers', 'gl_entry_id', id);
        if (vouchers.isNotEmpty) {
          payments.addAll(vouchers);
        } else {
          payments.addAll(await find('payments', 'gl_entry_id', id));
        }
      }
      for (final line in statement.lines) {
        final invoiceId = line.invoiceId;
        if (invoiceId == null || invoiceId.isEmpty) continue;
        for (final kind in ['بيع', 'شراء']) {
          final key = '$kind:$invoiceId';
          if (seen.contains(key)) continue;
          final headers = await find(
              kind == 'بيع' ? 'invoices' : 'purchase_invoices',
              'id',
              invoiceId);
          if (headers.isEmpty) continue;
          final h = headers.first;
          final owner = kind == 'بيع' ? legacy('CUSTOMER') : legacy('SUPPLIER');
          if (owner == null ||
              h[kind == 'بيع' ? 'client_id' : 'supplier_id']?.toString() !=
                  owner) continue;
          seen.add(key);
          var items = <Map<String, Object?>>[];
          var vehicle = <String, Object?>{};
          if (kind == 'شراء') {
            items =
                await find('purchase_invoice_lines', 'invoice_id', invoiceId);
          } else {
            final repairId = h['repair_id']?.toString();
            if (repairId != null && repairId.isNotEmpty) {
              items = await find('repair_lines', 'repair_id', repairId);
              final repairs = await find('repairs', 'id', repairId);
              if (repairs.isNotEmpty) vehicle = repairs.first;
            }
          }
          documents.add(PartyReportDocument(kind, h, items, vehicle));
        }
      }
      return DetailedPartyReport(statement, documents, payments, dates);
    });
  }
}
