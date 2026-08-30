// GLService — قراءة قيود GL مع الفلاتر (تاريخ/نص/مصدر) + مجاميع
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class GLRow {
  final int entryId;
  final String date; // ISO
  final String? ref;
  final String source; // REPAIR / PAYMENT / ...
  final String sourceId;
  final String? note;

  final int lineId;
  final int accountId;
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? partyType; // CUSTOMER / SUPPLIER / EMPLOYEE
  final String? partyId;

  GLRow({
    required this.entryId,
    required this.date,
    required this.ref,
    required this.source,
    required this.sourceId,
    required this.note,
    required this.lineId,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.partyType,
    required this.partyId,
  });
}

class GLTotals {
  final double debit;
  final double credit;
  GLTotals(this.debit, this.credit);
}

class GLService {
  static Future<List<String>> sources() async {
    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT DISTINCT source FROM gl_entries ORDER BY source
    ''');
    return rows
        .map((e) => (e['source'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static Future<List<GLRow>> fetch({
    DateTime? from,
    DateTime? to,
    String? source, // مثال: 'PAYMENT'
    String? search, // يبحث في ref/note/account/name/code/party_id
    int limit = 500,
    int offset = 0,
  }) async {
    final db = await DBService.database;

    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }
    if (source != null && source.trim().isNotEmpty) {
      where.add('e.source = ?');
      args.add(source.trim());
    }
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where.add('('
          'IFNULL(e.ref,"") LIKE ? OR IFNULL(e.note,"") LIKE ? OR '
          'IFNULL(a.code,"") LIKE ? OR IFNULL(a.name,"") LIKE ? OR '
          'IFNULL(l.party_id,"") LIKE ? OR IFNULL(e.source_id,"") LIKE ?'
          ')');
      args.addAll([like, like, like, like, like, like]);
    }

    final rows = await db.rawQuery('''
      SELECT
        e.id          AS entry_id,
        e.date        AS date,
        e.ref         AS ref,
        e.source      AS source,
        e.source_id   AS source_id,
        e.note        AS note,
        l.id          AS line_id,
        l.account_id  AS account_id,
        a.code        AS account_code,
        a.name        AS account_name,
        l.debit       AS debit,
        l.credit      AS credit,
        l.party_type  AS party_type,
        l.party_id    AS party_id
      FROM gl_entries e
      JOIN gl_lines l   ON l.entry_id = e.id
      JOIN accounts a   ON a.id = l.account_id
      ${where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : ''}
      ORDER BY e.date DESC, e.id DESC, l.id ASC
      LIMIT $limit OFFSET $offset
    ''', args);

    return rows.map((m) {
      double toD(o) {
        if (o is num) return o.toDouble();
        return double.tryParse(o?.toString() ?? '0') ?? 0.0;
      }

      return GLRow(
        entryId: (m['entry_id'] as int),
        date: (m['date'] ?? '').toString(),
        ref: (m['ref']?.toString()),
        source: (m['source'] ?? '').toString(),
        sourceId: (m['source_id'] ?? '').toString(),
        note: (m['note']?.toString()),
        lineId: (m['line_id'] as int),
        accountId: (m['account_id'] as int),
        accountCode: (m['account_code'] ?? '').toString(),
        accountName: (m['account_name'] ?? '').toString(),
        debit: toD(m['debit']),
        credit: toD(m['credit']),
        partyType: m['party_type']?.toString(),
        partyId: m['party_id']?.toString(),
      );
    }).toList();
  }

  static Future<GLTotals> totals({
    DateTime? from,
    DateTime? to,
    String? source,
    String? search,
  }) async {
    final db = await DBService.database;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('e.date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('e.date <= ?');
      args.add(to.toIso8601String());
    }
    if (source != null && source.trim().isNotEmpty) {
      where.add('e.source = ?');
      args.add(source.trim());
    }
    if (search != null && search.trim().isNotEmpty) {
      final like = '%${search.trim()}%';
      where.add('('
          'IFNULL(e.ref,"") LIKE ? OR IFNULL(e.note,"") LIKE ? OR '
          'IFNULL(a.code,"") LIKE ? OR IFNULL(a.name,"") LIKE ? OR '
          'IFNULL(l.party_id,"") LIKE ? OR IFNULL(e.source_id,"") LIKE ?'
          ')');
      args.addAll([like, like, like, like, like, like]);
    }

    final res = await db.rawQuery('''
      SELECT SUM(l.debit) AS sdebit, SUM(l.credit) AS scredit
      FROM gl_entries e
      JOIN gl_lines l ON l.entry_id = e.id
      JOIN accounts a ON a.id = l.account_id
      ${where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : ''}
    ''', args);

    double d(v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0;
    }

    final m = res.isEmpty ? <String, Object?>{} : res.first;
    return GLTotals(d(m['sdebit']), d(m['scredit']));
  }

  static String formatIso(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('yyyy-MM-dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
