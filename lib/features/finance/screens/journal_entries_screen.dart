import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
// 📁 lib/features/finance/screens/journal_entries_screen.dart
//
// قيود اليومية — قراءة مباشرة من GL (gl_entries + gl_lines + accounts)
// ✅ بدون أي بيانات وهمية
// ✅ مصادر حقيقية: GL + SQLite (invoices, payments, repairs لعرض الوصف)
// ✅ عرض ملف الإصلاح: "اسم المستفيد — نوع المركبة — سنة الإنتاج" (إخفاء UUID)
// ✅ مجاميع دقيقة بعد الفلاتر فقط
// ✅ اختيار أعمدة مستقل لكل وضع
// ✅ وضع مضغوط/مريح + إظهار/إخفاء السايدبار
// ✅ تجاوب كامل + Scroll أفقي/عمودي بلا Overflow
// ✅ ألوان: المدفوع أخضر، المتبقي أحمر

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

enum SortBy { dateAsc, dateDesc, amountAsc, amountDesc }

enum ViewMode { transactions, byRepair }

class JournalEntriesScreen extends StatefulWidget {
  final String? initialRepairId;

  const JournalEntriesScreen({
    super.key,
    this.initialRepairId,
  });

  @override
  State<JournalEntriesScreen> createState() => _JournalEntriesScreenState();
}

class _JournalEntriesScreenState extends State<JournalEntriesScreen> {
  // ===== Formatting =====
  final _df = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat('#,##0.00', 'ar');

  // ===== UI State =====
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  DateTimeRange? _range;
  SortBy _sort = SortBy.dateDesc;
  bool _loading = true;
  String? _error;

  // Sidebar toggle
  bool _showSidebar = true;

  // وضع مضغوط
  bool _compact = true;

  // وضع العرض
  ViewMode _mode = ViewMode.transactions;

  // اختيار الأعمدة — Transactions
  bool _tDate = true,
      _tDesc = true,
      _tAccount = true,
      _tDebit = true,
      _tCredit = true,
      _tRepair = true,
      _tPaid = true,
      _tRemain = true,
      _tActions = true;

  // اختيار الأعمدة — ByRepair
  bool _rRepair = true,
      _rInv = true,
      _rPaid = true,
      _rRemain = true,
      _rFirstDate = true,
      _rLastDate = true,
      _rActions = true;

  // ===== Data =====
  List<_JRow> _rows = [];
  final Map<String, double> _paidMap = {}; // relatedRepairId -> paid
  final Map<String, double> _invoiceMap = {}; // repair_id -> invoices total
  final Map<String, DateTime> _firstDateByRepair = {};
  final Map<String, DateTime> _lastDateByRepair = {};

  // عرض إنساني لملف الإصلاح
  final Map<String, String> _repairDisplayMap = {}; // rid -> label

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ===== DB helpers =====
  Future<Database> _db() async => DBService.database;

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final info = await db.rawQuery("PRAGMA table_info($table)");
    for (final r in info) {
      if ((r['name'] ?? '').toString() == column) return true;
    }
    return false;
  }

  Future<String?> _firstExistingColumn(
    Database db,
    String table,
    List<String> candidates,
  ) async {
    for (final c in candidates) {
      if (await _columnExists(db, table, c)) return c;
    }
    return null;
  }

  // ===== Load Repair display fields (beneficiary — vehicleType — year) =====
  Future<void> _loadRepairDisplayMap(Database db) async {
    _repairDisplayMap.clear();
    if (!await _tableExists(db, 'repairs')) return;

    final idCol = await _firstExistingColumn(
            db, 'repairs', ['id', 'repair_id', 'uuid', 'ulid']) ??
        'id';
    final nameCol = await _firstExistingColumn(db, 'repairs',
        ['beneficiaryName', 'client_name', 'beneficiary', 'ownerName']);
    final typeCol = await _firstExistingColumn(
        db, 'repairs', ['vehicleType', 'carType', 'vehicle', 'type']);
    // استخراج السنة من vehicleModel إذا لزم
    final yearCol = await _firstExistingColumn(db, 'repairs', [
      'modelYear',
      'year',
      'vehicleModelYear',
      'carModelYear',
      'vehicleModel',
      'model'
    ]);

    final cols =
        [idCol, nameCol, typeCol, yearCol].whereType<String>().toList();
    final res = await db.rawQuery('SELECT ${cols.join(',')} FROM repairs');

    for (final m in res) {
      final rid = (m[idCol] ?? '').toString();
      if (rid.isEmpty) continue;

      final beneficiary =
          (nameCol != null ? (m[nameCol] ?? '') : '').toString().trim();
      final vtype =
          (typeCol != null ? (m[typeCol] ?? '') : '').toString().trim();
      final yearRaw =
          (yearCol != null ? (m[yearCol] ?? '') : '').toString().trim();

      String year = '';
      final yrMatch = RegExp(r'\d{4}').firstMatch(yearRaw);
      if (yrMatch != null) year = yrMatch.group(0)!;

      final parts =
          [beneficiary, vtype, year].where((s) => s.isNotEmpty).toList();
      final label = parts.isEmpty ? '' : parts.join(' — ');
      if (label.isNotEmpty) _repairDisplayMap[rid] = label;
    }
  }

  String _repairLabel(String? rid) {
    if (rid == null || rid.isEmpty) return '—';
    final label = _repairDisplayMap[rid];
    if (label != null && label.trim().isNotEmpty) return label;
    final s = rid;
    if (s.length <= 10) return s;
    return '${s.substring(0, 6)}…${s.substring(s.length - 5)}';
  }

  // ===== Load all from GL =====
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await _db();

      // (1) تحميل وصف ملف الإصلاح للعرض
      await _loadRepairDisplayMap(db);

      // (2) قراءة كل أسطر GL مع أسماء الحسابات
      final where = <String>[];
      final args = <dynamic>[];

      // STAGE1_P0_REPAIR_JOURNAL_SCOPE
      final scopedRepairId = widget.initialRepairId?.trim();
      if (scopedRepairId != null && scopedRepairId.isNotEmpty) {
        where.add('gl.repair_id = ?');
        args.add(scopedRepairId);
      }

      if (_range != null) {
        where.add('ge.date BETWEEN ? AND ?');
        args.add(_range!.start.toIso8601String());
        args.add(DateTime(_range!.end.year, _range!.end.month, _range!.end.day,
                23, 59, 59)
            .toIso8601String());
      }

      // بحث بالنص على note واسم الحساب
      final q = _searchCtrl.text.trim();
      if (q.isNotEmpty) {
        where.add(
            '(ge.note LIKE ? OR a.name LIKE ? OR ge.source LIKE ? OR ge.source_id LIKE ?)');
        final like = '%$q%';
        args.addAll([like, like, like, like]);
      }

      final sql = StringBuffer('''
        SELECT
          ge.id            AS gl_id,
          ge.date          AS gl_date,
          ge.note          AS gl_note,
          ge.source        AS gl_source,
          ge.source_id     AS gl_source_id,
          gl.debit         AS debit,
          gl.credit        AS credit,
          gl.repair_id     AS repair_id,
          (SELECT pi.amount_total FROM purchase_invoices pi
            WHERE pi.id = gl.invoice_id) AS purchase_total,
          (SELECT ${PurchaseBalanceSql.paid('pi.id')} FROM purchase_invoices pi
            WHERE pi.id = gl.invoice_id) AS purchase_paid,
          a.name           AS account_name
        FROM gl_entries ge
        JOIN gl_lines gl  ON gl.entry_id = ge.id
        JOIN accounts a   ON a.id = gl.account_id
      ''');
      if (where.isNotEmpty) {
        sql.write(' WHERE ${where.join(' AND ')}');
      }
      sql.write(' ORDER BY ge.date DESC, ge.id DESC, gl.id ASC');

      final maps = await db.rawQuery(sql.toString(), args);
      _rows = maps.map<_JRow>((m) {
        final date = DateTime.tryParse((m['gl_date'] ?? '').toString()) ??
            DateTime(1970, 1, 1);
        final desc = (m['gl_note'] ?? '').toString().trim();
        final account = (m['account_name'] ?? '').toString();
        final debit = (m['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (m['credit'] as num?)?.toDouble() ?? 0.0;
        final rid = (m['repair_id'] ?? '').toString();
        return _JRow(
          date: date,
          description: desc.isEmpty ? (m['gl_source']?.toString() ?? '') : desc,
          accountName: account,
          debit: debit,
          credit: credit,
          relatedRepairId: rid.isEmpty ? null : rid,
          purchaseTotal: (m['purchase_total'] as num?)?.toDouble(),
          purchasePaid: (m['purchase_paid'] as num?)?.toDouble(),
        );
      }).toList();

      // (3) فواتير حسب repair_id
      _invoiceMap.clear();
      if (await _tableExists(db, 'invoices')) {
        final rows = await db.rawQuery('''
          SELECT COALESCE(repair_id,'') AS rid, IFNULL(SUM(total),0) AS tot
          FROM invoices
          GROUP BY COALESCE(repair_id,'')
        ''');
        for (final m in rows) {
          final rid = (m['rid'] ?? '').toString();
          final tot = (m['tot'] as num?)?.toDouble() ?? 0.0;
          if (rid.isNotEmpty) _invoiceMap[rid] = tot;
        }
      }

      // (4) المدفوع من جدول payments + أول/آخر تاريخ للدفعات
      _paidMap.clear();
      _firstDateByRepair.clear();
      _lastDateByRepair.clear();
      if (await _tableExists(db, 'payments')) {
        final rows = await db.rawQuery('''
          SELECT
            COALESCE(repair_id,'') AS rid,
            IFNULL(SUM(amount),0)  AS paid,
            MIN(date)              AS firstDate,
            MAX(date)              AS lastDate
          FROM payments
          GROUP BY COALESCE(repair_id,'')
        ''');
        for (final m in rows) {
          final rid = (m['rid'] ?? '').toString();
          if (rid.isEmpty) continue;
          final paid = (m['paid'] as num?)?.toDouble() ?? 0.0;
          _paidMap[rid] = paid;
          final fd = DateTime.tryParse((m['firstDate'] ?? '').toString());
          final ld = DateTime.tryParse((m['lastDate'] ?? '').toString());
          if (fd != null) _firstDateByRepair[rid] = fd;
          if (ld != null) _lastDateByRepair[rid] = ld;
        }
      }

      _applySort();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySort() {
    _rows.sort((a, b) {
      switch (_sort) {
        case SortBy.dateAsc:
          return a.date.compareTo(b.date);
        case SortBy.dateDesc:
          return b.date.compareTo(a.date);
        case SortBy.amountAsc:
          return (a.debit + a.credit).compareTo(b.debit + b.credit);
        case SortBy.amountDesc:
          return (b.debit + b.credit).compareTo(a.debit + a.credit);
      }
    });
  }

  // ===== Filters =====
  List<_JRow> get _filteredTx {
    Iterable<_JRow> list = _rows;

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) =>
          e.description.toLowerCase().contains(q) ||
          e.accountName.toLowerCase().contains(q) ||
          (e.relatedRepairId ?? '').toLowerCase().contains(q) ||
          _repairLabel(e.relatedRepairId).toLowerCase().contains(q));
    }

    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59);
      list = list.where((e) => !e.date.isBefore(start) && !e.date.isAfter(end));
    }

    return list.toList();
  }

  // ===== Aggregation by Repair =====
  List<_RepairAgg> get _filteredAgg {
    final tx = _filteredTx;
    final map = <String, _RepairAgg>{};

    for (final e in tx) {
      final rid = e.relatedRepairId ?? '';
      if (rid.isEmpty) continue;
      map.putIfAbsent(rid, () => _RepairAgg(rid: rid));

      final agg = map[rid]!;
      agg.invoiceTotal = _invoiceMap[rid] ?? 0.0;
      agg.paid = _paidMap[rid] ?? 0.0;

      final d1 = _firstDateByRepair[rid];
      final d2 = _lastDateByRepair[rid];
      if (d1 != null) agg.firstDate = d1;
      if (d2 != null) agg.lastDate = d2;

      // تسمية عرضية (الاسم — النوع — السنة)
      agg.display = _repairLabel(rid);
    }

    // فلترة بالبحث على الـ display أيضاً
    final q = _searchCtrl.text.trim().toLowerCase();
    final list = map.values.where((a) {
      if (q.isEmpty) return true;
      return a.rid.toLowerCase().contains(q) ||
          a.display.toLowerCase().contains(q);
    }).toList();

    // ترتيب
    list.sort((a, b) {
      switch (_sort) {
        case SortBy.dateAsc:
          return (a.firstDate ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.firstDate ?? DateTime.fromMillisecondsSinceEpoch(0));
        case SortBy.dateDesc:
          return (b.firstDate ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.firstDate ?? DateTime.fromMillisecondsSinceEpoch(0));
        case SortBy.amountAsc:
          return a.invoiceTotal.compareTo(b.invoiceTotal);
        case SortBy.amountDesc:
          return b.invoiceTotal.compareTo(a.invoiceTotal);
      }
    });

    return list;
  }

  // ===== Totals (after filters only) =====
  double get _txTotalDebits => _filteredTx.fold(0.0, (s, e) => s + e.debit);
  double get _txTotalCredits => _filteredTx.fold(0.0, (s, e) => s + e.credit);

  double get _aggInv => _filteredAgg.fold(0.0, (s, a) => s + a.invoiceTotal);
  double get _aggPaid => _filteredAgg.fold(0.0, (s, a) => s + a.paid);
  double get _aggRemain => _aggInv - _aggPaid;

  // ===== Payments details bottom sheet (from GL) =====
  Future<void> _showPaymentsDetails(String repairId) async {
    try {
      final db = await _db();
      if (!await _tableExists(db, 'gl_entries')) return;

      const customerAccounts = [
        'العملاء',
        'عملاء',
        'Customers',
        'Accounts Receivable',
        'AR'
      ];
      final placeholders = List.filled(customerAccounts.length, '?').join(',');

      final rows = await db.rawQuery('''
        SELECT ge.date AS date, ge.note AS note, gl.credit AS credit, a.name AS accountName
        FROM gl_entries ge
        JOIN gl_lines gl ON gl.entry_id = ge.id
        JOIN accounts a  ON a.id = gl.account_id
        WHERE gl.repair_id = ?
          AND a.name IN ($placeholders)
          AND gl.credit > 0
        ORDER BY ge.date ASC, ge.id ASC
      ''', [repairId, ...customerAccounts]);

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.55,
            minChildSize: 0.35,
            maxChildSize: 0.9,
            builder: (ctx, controller) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تفاصيل الدفعات — ${_repairLabel(repairId)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      Expanded(
                        child: rows.isEmpty
                            ? const Center(
                                child: Text('لا يوجد دفعات مسجلة لهذا الملف'))
                            : ListView.separated(
                                controller: controller,
                                itemCount: rows.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 8),
                                itemBuilder: (_, i) {
                                  final m = rows[i];
                                  final dt = DateTime.tryParse(
                                          (m['date'] ?? '').toString()) ??
                                      DateTime(1970);
                                  final desc = (m['note'] ?? 'دفعة').toString();
                                  final val =
                                      (m['credit'] as num?)?.toDouble() ?? 0.0;
                                  return ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.payments),
                                    title: Text(desc),
                                    subtitle: Text(_df.format(dt)),
                                    trailing: Text(
                                      _currency.format(val),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'الإجمالي: ${_currency.format(_paidMap[repairId] ?? 0.0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'نطاق التاريخ',
    );
    if (dr != null) setState(() => _range = dr);
  }

  void _clearRange() => setState(() => _range = null);

  void _openColumnChooser() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setM) {
            Widget cb(String label, bool v, ValueChanged<bool?> on) {
              return CheckboxListTile(
                value: v,
                onChanged: (b) => setM(() => on(b)),
                title: Text(label),
                dense: true,
              );
            }

            final isTx = _mode == ViewMode.transactions;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isTx
                            ? 'اختيار الأعمدة — سطور محاسبية'
                            : 'اختيار الأعمدة — مجمّع حسب ملف الإصلاح',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      if (isTx) ...[
                        cb('التاريخ', _tDate, (b) => _tDate = b ?? true),
                        cb('الوصف', _tDesc, (b) => _tDesc = b ?? true),
                        cb('الحساب', _tAccount, (b) => _tAccount = b ?? true),
                        cb('مدين', _tDebit, (b) => _tDebit = b ?? true),
                        cb('دائن', _tCredit, (b) => _tCredit = b ?? true),
                        cb('ملف الإصلاح', _tRepair,
                            (b) => _tRepair = b ?? true),
                        cb('المدفوع', _tPaid, (b) => _tPaid = b ?? true),
                        cb('المتبقي', _tRemain, (b) => _tRemain = b ?? true),
                        cb('تفاصيل', _tActions, (b) => _tActions = b ?? true),
                      ] else ...[
                        cb('ملف الإصلاح', _rRepair,
                            (b) => _rRepair = b ?? true),
                        cb('إجمالي الفاتورة', _rInv, (b) => _rInv = b ?? true),
                        cb('المدفوع', _rPaid, (b) => _rPaid = b ?? true),
                        cb('المتبقي', _rRemain, (b) => _rRemain = b ?? true),
                        cb('أول تاريخ', _rFirstDate,
                            (b) => _rFirstDate = b ?? true),
                        cb('آخر تاريخ', _rLastDate,
                            (b) => _rLastDate = b ?? true),
                        cb('تفاصيل', _rActions, (b) => _rActions = b ?? true),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () {
                            setState(() {}); // يعكس الخيارات
                            Navigator.pop(context);
                          },
                          child: const Text('تم'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final width = MediaQuery.of(context).size.width;
    final useCards = !isDesktop && width < 900;

    const currentRoute = '/finance/journal';

    final tableColumnSpacing = _compact ? 12.0 : 24.0;
    final dataTextStyle = TextStyle(fontSize: _compact ? 12 : 14);
    final headerTextStyle =
        TextStyle(fontWeight: FontWeight.bold, fontSize: _compact ? 12 : 14);

    Widget totalsBar() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: _mode == ViewMode.transactions
              ? Text(
                  'الإجماليات — مدين: ${_currency.format(_txTotalDebits)} • '
                  'دائن: ${_currency.format(_txTotalCredits)} • '
                  'الصافي: ${_currency.format(_txTotalDebits - _txTotalCredits)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              : Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _chipStat('إجمالي الفواتير', _currency.format(_aggInv),
                        color: Colors.blueGrey),
                    _chipStat('المدفوع', _currency.format(_aggPaid),
                        color: Colors.green),
                    _chipStat('المتبقي', _currency.format(_aggRemain),
                        color: Colors.red),
                  ],
                ),
        ),
      );
    }

    return Scaffold(
      drawer: isDesktop || _showSidebar
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      appBar: AppBar(
        title: Text(
          widget.initialRepairId == null ? 'قيود اليومية' : 'قيود ملف الإصلاح',
        ),
        backgroundColor: AppColors.primary,
        leading: isDesktop
            ? IconButton(
                tooltip: _showSidebar ? 'إخفاء القائمة' : 'إظهار القائمة',
                icon: Icon(_showSidebar ? Icons.chevron_right : Icons.menu),
                onPressed: () => setState(() => _showSidebar = !_showSidebar),
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: [
          if (isDesktop) ...[
            // toggle mode
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: SegmentedButton<ViewMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10)),
                ),
                segments: const [
                  ButtonSegment(
                      value: ViewMode.transactions, label: Text('سطور')),
                  ButtonSegment(
                      value: ViewMode.byRepair, label: Text('حسب الإصلاح')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ),
            IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh),
                onPressed: _load),
            IconButton(
              tooltip: _compact ? 'وضع مريح' : 'وضع مضغوط',
              icon: Icon(_compact ? Icons.density_small : Icons.density_medium),
              onPressed: () => setState(() => _compact = !_compact),
            ),
            IconButton(
                tooltip: 'اختيار الأعمدة',
                icon: const Icon(Icons.view_column),
                onPressed: _openColumnChooser),
          ] else
            PopupMenuButton<String>(
                tooltip: 'خيارات العرض',
                onSelected: (value) {
                  if (value == 'refresh') {
                    _load();
                  }
                  if (value == 'columns') {
                    _openColumnChooser();
                  }
                  if (value == 'mode') {
                    setState(() => _mode = _mode == ViewMode.transactions
                        ? ViewMode.byRepair
                        : ViewMode.transactions);
                  }
                  if (value == 'density') {
                    setState(() => _compact = !_compact);
                  }
                },
                itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'mode',
                          child: Text(_mode == ViewMode.transactions
                              ? 'عرض حسب الإصلاح'
                              : 'عرض السطور')),
                      const PopupMenuItem(
                          value: 'refresh', child: Text('تحديث')),
                      const PopupMenuItem(
                          value: 'columns', child: Text('اختيار الأعمدة')),
                      const PopupMenuItem(
                          value: 'density', child: Text('تغيير كثافة العرض')),
                    ]),
        ],
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop && _showSidebar)
            const SizedBox(
                width: 260, child: YallaSidebar(currentRoute: currentRoute)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('حدث خطأ أثناء تحميل البيانات:\n$_error',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      )
                    : Column(
                        children: [
                          // ===== Toolbar =====
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 560),
                                  child: TextField(
                                    inputFormatters: const [
                                      YallaDigitNormalizer()
                                    ],
                                    controller: _searchCtrl,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText:
                                          'بحث بالوصف/الحساب/اسم المستفيد/نوع المركبة/سنة…',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: _pickRange,
                                      icon: const Icon(Icons.date_range),
                                      label: Text(
                                        _range == null
                                            ? 'كل التواريخ'
                                            : '${_df.format(_range!.start)} → ${_df.format(_range!.end)}',
                                      ),
                                    ),
                                    if (_range != null)
                                      IconButton(
                                        tooltip: 'مسح النطاق',
                                        onPressed: _clearRange,
                                        icon: const Icon(Icons.clear),
                                      ),
                                    const SizedBox(width: 8),
                                    DropdownButton<SortBy>(
                                      value: _sort,
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() {
                                          _sort = v;
                                          _applySort();
                                        });
                                      },
                                      items: const [
                                        DropdownMenuItem(
                                            value: SortBy.dateDesc,
                                            child: Text('الأحدث أولاً')),
                                        DropdownMenuItem(
                                            value: SortBy.dateAsc,
                                            child: Text('الأقدم أولاً')),
                                        DropdownMenuItem(
                                            value: SortBy.amountDesc,
                                            child: Text('المبلغ (تنازلي)')),
                                        DropdownMenuItem(
                                            value: SortBy.amountAsc,
                                            child: Text('المبلغ (تصاعدي)')),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ===== Totals =====
                          totalsBar(),
                          const SizedBox(height: 4),

                          // ===== Content =====
                          Expanded(
                            child: Builder(
                              builder: (_) {
                                if (_mode == ViewMode.transactions) {
                                  final list = _filteredTx;
                                  if (list.isEmpty) {
                                    return const Center(
                                        child: Text('لا توجد قيود مسجلة'));
                                  }
                                  return useCards
                                      ? _buildTxCards(
                                          list,
                                        )
                                      : _buildTxTable(
                                          list,
                                          headerTextStyle,
                                          dataTextStyle,
                                          tableColumnSpacing,
                                        );
                                } else {
                                  final list = _filteredAgg;
                                  if (list.isEmpty) {
                                    return const Center(
                                        child: Text(
                                            'لا توجد ملفات إصلاح ضمن الفلاتر الحالية'));
                                  }
                                  return useCards
                                      ? _buildAggCards(list)
                                      : _buildAggTable(
                                          list,
                                          headerTextStyle,
                                          dataTextStyle,
                                          tableColumnSpacing,
                                        );
                                }
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ===== Transactions: Table =====
  Widget _buildTxTable(
    List<_JRow> list,
    TextStyle headerTextStyle,
    TextStyle dataTextStyle,
    double columnSpacing,
  ) {
    final vertical = ScrollController();
    final horizontal = ScrollController();

    return Listener(
      onPointerSignal: (ps) {
        if (ps is PointerScrollEvent) {
          // سكرول عمودي عند تدوير عجلة الماوس
          vertical.jumpTo(
            vertical.offset + ps.scrollDelta.dy,
          );
        }
      },
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1200),
            child: Scrollbar(
              controller: vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: vertical,
                scrollDirection: Axis.vertical,
                child: AdaptiveDataTable(
                  headingTextStyle: headerTextStyle,
                  dataTextStyle: dataTextStyle,
                  columnSpacing: columnSpacing,
                  columns: [
                    if (_tDate) const DataColumn(label: Text('التاريخ')),
                    if (_tDesc) const DataColumn(label: Text('الوصف')),
                    if (_tAccount) const DataColumn(label: Text('الحساب')),
                    if (_tDebit)
                      const DataColumn(numeric: true, label: Text('مدين')),
                    if (_tCredit)
                      const DataColumn(numeric: true, label: Text('دائن')),
                    if (_tRepair) const DataColumn(label: Text('ملف الإصلاح')),
                    if (_tPaid)
                      const DataColumn(numeric: true, label: Text('المدفوع')),
                    if (_tRemain)
                      const DataColumn(numeric: true, label: Text('المتبقي')),
                    if (_tActions) const DataColumn(label: Text('تفاصيل')),
                  ],
                  rows: list.map((e) {
                    final rid = e.relatedRepairId ?? '';
                    final paid = e.purchasePaid ??
                        (rid.isEmpty ? 0 : (_paidMap[rid] ?? 0));
                    final invTotal = e.purchaseTotal ??
                        (rid.isEmpty ? 0 : (_invoiceMap[rid] ?? 0));
                    final remain = invTotal - paid;

                    return DataRow(cells: [
                      if (_tDate) DataCell(Text(_df.format(e.date))),
                      if (_tDesc) DataCell(Text(e.description)),
                      if (_tAccount) DataCell(Text(e.accountName)),
                      if (_tDebit) DataCell(Text(_currency.format(e.debit))),
                      if (_tCredit) DataCell(Text(_currency.format(e.credit))),
                      if (_tRepair) DataCell(Text(_repairLabel(rid))),
                      if (_tPaid)
                        DataCell(
                          rid.isEmpty && e.purchaseTotal == null
                              ? const Text('—')
                              : Text(
                                  _currency.format(paid),
                                  style: const TextStyle(color: Colors.green),
                                ),
                        ),
                      if (_tRemain)
                        DataCell(
                          rid.isEmpty && e.purchaseTotal == null
                              ? const Text('—')
                              : Text(
                                  _currency.format(remain),
                                  style: const TextStyle(color: Colors.red),
                                ),
                        ),
                      if (_tActions)
                        DataCell(
                          rid.isEmpty || paid <= 0
                              ? const Text('—')
                              : TextButton.icon(
                                  onPressed: () => _showPaymentsDetails(rid),
                                  icon: const Icon(Icons.list),
                                  label: const Text('عرض'),
                                ),
                        ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Transactions: Cards (narrow) =====
  Widget _buildTxCards(List<_JRow> list) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = list[i];
        final rid = e.relatedRepairId ?? '';
        final paid =
            e.purchasePaid ?? (rid.isEmpty ? 0.0 : (_paidMap[rid] ?? 0.0));
        final invTotal =
            e.purchaseTotal ?? (rid.isEmpty ? 0.0 : (_invoiceMap[rid] ?? 0.0));
        final remain = (invTotal - paid).clamp(-1e12, 1e12);

        return Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveRow(
                  children: [
                    Expanded(
                        child: Text(e.description,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold))),
                    Text(_df.format(e.date)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _kv('الحساب', e.accountName),
                    _kv('مدين', _currency.format(e.debit)),
                    _kv('دائن', _currency.format(e.credit)),
                    _kv('ملف الإصلاح', _repairLabel(rid)),
                    _kv(
                        'المدفوع',
                        rid.isEmpty && e.purchaseTotal == null
                            ? '—'
                            : _currency.format(paid),
                        valueColor: Colors.green,
                        isBold: true),
                    _kv(
                        'المتبقي',
                        rid.isEmpty && e.purchaseTotal == null
                            ? '—'
                            : _currency.format(remain),
                        valueColor: Colors.red,
                        isBold: true),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: rid.isEmpty || paid <= 0
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () => _showPaymentsDetails(rid),
                          icon: const Icon(Icons.list),
                          label: const Text('تفاصيل الدفعات'),
                        ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== Aggregated by Repair: Table =====
  Widget _buildAggTable(
    List<_RepairAgg> list,
    TextStyle headerTextStyle,
    TextStyle dataTextStyle,
    double columnSpacing,
  ) {
    final vertical = ScrollController();
    final horizontal = ScrollController();

    return Listener(
      onPointerSignal: (ps) {
        if (ps is PointerScrollEvent) {
          vertical.jumpTo(vertical.offset + ps.scrollDelta.dy);
        }
      },
      child: Scrollbar(
        controller: horizontal,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: horizontal,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 1000),
            child: Scrollbar(
              controller: vertical,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: vertical,
                child: AdaptiveDataTable(
                  headingTextStyle: headerTextStyle,
                  dataTextStyle: dataTextStyle,
                  columnSpacing: columnSpacing,
                  columns: [
                    if (_rRepair) const DataColumn(label: Text('ملف الإصلاح')),
                    if (_rInv)
                      const DataColumn(
                          numeric: true, label: Text('إجمالي الفاتورة')),
                    if (_rPaid)
                      const DataColumn(numeric: true, label: Text('المدفوع')),
                    if (_rRemain)
                      const DataColumn(numeric: true, label: Text('المتبقي')),
                    if (_rFirstDate) const DataColumn(label: Text('أول تاريخ')),
                    if (_rLastDate) const DataColumn(label: Text('آخر تاريخ')),
                    if (_rActions) const DataColumn(label: Text('تفاصيل')),
                  ],
                  rows: list.map((a) {
                    final remain = a.invoiceTotal - a.paid;

                    return DataRow(cells: [
                      if (_rRepair)
                        DataCell(Text(a.display.isEmpty
                            ? _repairLabel(a.rid)
                            : a.display)),
                      if (_rInv)
                        DataCell(Text(_currency.format(a.invoiceTotal))),
                      if (_rPaid)
                        DataCell(Text(
                          _currency.format(a.paid),
                          style: const TextStyle(color: Colors.green),
                        )),
                      if (_rRemain)
                        DataCell(Text(
                          _currency.format(remain),
                          style: const TextStyle(color: Colors.red),
                        )),
                      if (_rFirstDate)
                        DataCell(Text(a.firstDate == null
                            ? '—'
                            : _df.format(a.firstDate!))),
                      if (_rLastDate)
                        DataCell(Text(a.lastDate == null
                            ? '—'
                            : _df.format(a.lastDate!))),
                      if (_rActions)
                        DataCell(
                          a.paid <= 0
                              ? const Text('—')
                              : TextButton.icon(
                                  onPressed: () => _showPaymentsDetails(a.rid),
                                  icon: const Icon(Icons.list),
                                  label: const Text('دفعات'),
                                ),
                        ),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Aggregated by Repair: Cards =====
  Widget _buildAggCards(List<_RepairAgg> list) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = list[i];
        final remain = (a.invoiceTotal - a.paid).clamp(-1e12, 1e12);

        return Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveRow(
                  children: [
                    const Icon(Icons.folder_copy_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a.display.isEmpty ? _repairLabel(a.rid) : a.display,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _kv('إجمالي الفاتورة', _currency.format(a.invoiceTotal)),
                    _kv('المدفوع', _currency.format(a.paid),
                        valueColor: Colors.green, isBold: true),
                    _kv('المتبقي', _currency.format(remain),
                        valueColor: Colors.red, isBold: true),
                    _kv('أول تاريخ',
                        a.firstDate == null ? '—' : _df.format(a.firstDate!)),
                    _kv('آخر تاريخ',
                        a.lastDate == null ? '—' : _df.format(a.lastDate!)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: a.paid <= 0
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () => _showPaymentsDetails(a.rid),
                          icon: const Icon(Icons.list),
                          label: const Text('تفاصيل الدفعات'),
                        ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== Helpers UI =====
  Widget _kv(String k, String v, {Color? valueColor, bool isBold = false}) {
    return AdaptiveRow(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          v,
          style: TextStyle(
              color: valueColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400),
        ),
      ],
    );
  }

  Widget _chipStat(String label, String value, {required Color color}) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ===== Row model (محلي) =====
class _JRow {
  final DateTime date;
  final String description;
  final String accountName;
  final double debit;
  final double credit;
  final String? relatedRepairId;
  final double? purchaseTotal;
  final double? purchasePaid;

  _JRow({
    required this.date,
    required this.description,
    required this.accountName,
    required this.debit,
    required this.credit,
    required this.relatedRepairId,
    this.purchaseTotal,
    this.purchasePaid,
  });
}

// ===== Aggregation Model =====
class _RepairAgg {
  final String rid;
  String display = '';
  double invoiceTotal = 0.0;
  double paid = 0.0;
  DateTime? firstDate;
  DateTime? lastDate;

  _RepairAgg({required this.rid});
}
