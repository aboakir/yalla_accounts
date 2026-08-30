// 📁 lib/features/finance/screens/account_receivable_screen.dart
//
// Accounts Receivable — شاشة الذمم المدينة (العملاء)
// ✅ عربي بالكامل بدون فرض RTL (يتبع اتجاه التطبيق).
// ✅ بدون أي بيانات وهمية — قراءة فعلية من SQLite.
// ✅ مصادر: clients + invoices (total,date,client_id) + journal_entries (credit على "العملاء") + repairs (للربط).
// ✅ يحسب "المدفوع" عبر JOIN: journal_entries.relatedRepairId → repairs.id → repairs.client_id.
// ✅ لو وُجد عمود clientId داخل اليومية، يُستخدم كمسار إضافي (اختياري) وتُدمَج النتائج.
// ✅ بحث + فلترة النوع + نطاق تاريخ يؤثر على الاستعلامات.
// ✅ جدول للديسكتوب وبطاقات للموبايل + BottomSheet لدفعات العميل.
// ✅ زر إضافة دفعة يفتح /finance/payments.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class AccountReceivableScreen extends StatefulWidget {
  const AccountReceivableScreen({super.key});

  @override
  State<AccountReceivableScreen> createState() =>
      _AccountReceivableScreenState();
}

class _AccountReceivableScreenState extends State<AccountReceivableScreen> {
  // ===== Formatting =====
  final _df = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat('#,##0.00', 'ar');

  // ===== UI =====
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _filterType = 'الكل'; // 'الكل' | 'أفراد' | 'شركة تأمين'
  DateTimeRange? _range;
  bool _loading = true;
  String? _error;
  bool _showSidebar = true;
  bool _compact = true;

  // ===== Data =====
  final Map<String, _ClientInfo> _clients = {}; // clientId -> info
  final Map<String, double> _invByClient = {}; // clientId -> invoices total
  final Map<String, double> _paidByClient = {}; // clientId -> paid total
  final Map<String, DateTime> _firstPayByClient = {};
  final Map<String, DateTime> _lastPayByClient = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  Future<Database> _db() async => DBService.database;

  Future<bool> _tableExists(Database db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final info = await db.rawQuery("PRAGMA table_info($table)");
    for (final m in info) {
      if ((m['name'] ?? '').toString().toLowerCase() == column.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await _db();

      final hasClients = await _tableExists(db, 'clients');
      final hasInv = await _tableExists(db, 'invoices');
      final hasJE = await _tableExists(db, 'journal_entries');
      final hasRepairs = await _tableExists(db, 'repairs');

      if (!hasClients) {
        throw 'جدول clients غير موجود.';
      }
      if (!hasInv && !hasJE) {
        throw 'لا يوجد invoices ولا journal_entries.';
      }

      // (1) العملاء
      _clients.clear();
      final clientsRows =
          await db.rawQuery('SELECT id, name, type FROM clients');
      for (final m in clientsRows) {
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty) continue;
        _clients[id] = _ClientInfo(
          id: id,
          name: (m['name'] ?? '').toString(),
          type: _toUiType((m['type'] ?? '').toString()),
        );
      }

      // نطاق التاريخ
      String whereInv = '';
      List<Object?> argsInv = [];
      String extraPayDates = ''; // للشروط على journal_entries.date
      List<Object?> argsPay = [];
      if (_range != null) {
        final start = _df.format(DateTime(
            _range!.start.year, _range!.start.month, _range!.start.day));
        final end = _df.format(
            DateTime(_range!.end.year, _range!.end.month, _range!.end.day));
        whereInv = "WHERE date >= ? AND date <= ?";
        argsInv = [start, end];
        extraPayDates = " AND je.date >= ? AND je.date <= ? ";
        argsPay.addAll([start, end]);
      }

      // (2) فواتير لكل عميل
      _invByClient.clear();
      if (hasInv) {
        final invRows = await db.rawQuery('''
          SELECT COALESCE(client_id,'') AS cid, IFNULL(SUM(total),0) AS tot
          FROM invoices
          $whereInv
          GROUP BY COALESCE(client_id,'')
        ''', argsInv);
        for (final m in invRows) {
          final cid = (m['cid'] ?? '').toString();
          final tot = (m['tot'] as num?)?.toDouble() ?? 0.0;
          if (cid.isNotEmpty) _invByClient[cid] = tot;
        }
      }

      // (3) المدفوع من اليومية — المسار الرئيسي عبر repairs
      _paidByClient.clear();
      _firstPayByClient.clear();
      _lastPayByClient.clear();

      if (hasJE && hasRepairs) {
        const customerAccounts = [
          'العملاء',
          'عملاء',
          'Customers',
          'Accounts Receivable',
          'AR'
        ];
        final placeholders =
            List.filled(customerAccounts.length, '?').join(',');

        final mainRows = await db.rawQuery('''
          SELECT COALESCE(r.client_id,'') AS cid,
                 IFNULL(SUM(je.credit),0) AS paid,
                 MIN(je.date) AS firstDate,
                 MAX(je.date) AS lastDate
          FROM journal_entries je
          JOIN repairs r ON r.id = je.relatedRepairId
          WHERE je.accountName IN ($placeholders)
            AND je.credit > 0
            $extraPayDates
          GROUP BY COALESCE(r.client_id,'')
        ''', [...customerAccounts, ...argsPay]);

        for (final m in mainRows) {
          final cid = (m['cid'] ?? '').toString();
          if (cid.isEmpty) continue;
          final paid = (m['paid'] as num?)?.toDouble() ?? 0.0;
          _paidByClient[cid] = (_paidByClient[cid] ?? 0.0) + paid;

          final fd = DateTime.tryParse((m['firstDate'] ?? '').toString());
          final ld = DateTime.tryParse((m['lastDate'] ?? '').toString());
          if (fd != null) {
            final cur = _firstPayByClient[cid];
            _firstPayByClient[cid] =
                (cur == null || fd.isBefore(cur)) ? fd : cur;
          }
          if (ld != null) {
            final cur = _lastPayByClient[cid];
            _lastPayByClient[cid] = (cur == null || ld.isAfter(cur)) ? ld : cur;
          }
        }
      }

      // (3b) مسار إضافي اختياري: لو في عمود clientId داخل اليومية
      if (hasJE && await _columnExists(db, 'journal_entries', 'clientId')) {
        const customerAccounts = [
          'العملاء',
          'عملاء',
          'Customers',
          'Accounts Receivable',
          'AR'
        ];
        final placeholders =
            List.filled(customerAccounts.length, '?').join(',');

        final extraRows = await db.rawQuery('''
          SELECT COALESCE(je.clientId,'') AS cid,
                 IFNULL(SUM(je.credit),0) AS paid,
                 MIN(je.date) AS firstDate,
                 MAX(je.date) AS lastDate
          FROM journal_entries je
          WHERE je.accountName IN ($placeholders)
            AND je.credit > 0
            $extraPayDates
          GROUP BY COALESCE(je.clientId,'')
        ''', [...customerAccounts, ...argsPay]);

        for (final m in extraRows) {
          final cid = (m['cid'] ?? '').toString();
          if (cid.isEmpty) continue;
          final paid = (m['paid'] as num?)?.toDouble() ?? 0.0;
          _paidByClient[cid] = (_paidByClient[cid] ?? 0.0) + paid;

          final fd = DateTime.tryParse((m['firstDate'] ?? '').toString());
          final ld = DateTime.tryParse((m['lastDate'] ?? '').toString());
          if (fd != null) {
            final cur = _firstPayByClient[cid];
            _firstPayByClient[cid] =
                (cur == null || fd.isBefore(cur)) ? fd : cur;
          }
          if (ld != null) {
            final cur = _lastPayByClient[cid];
            _lastPayByClient[cid] = (cur == null || ld.isAfter(cur)) ? ld : cur;
          }
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== Helpers (UI & Filters) =====
  String _norm(String s) => s.trim().toLowerCase();

  String _toUiType(String v) {
    final s = _norm(v);
    if (s == 'insurance' || s == 'شركة تأمين' || s == 'تأمين') {
      return 'شركة تأمين';
    }
    return 'أفراد';
  }

  bool _matchesType(String t) {
    if (_filterType == 'الكل') return true;
    if (_filterType == 'شركة تأمين') return t == 'شركة تأمين';
    if (_filterType == 'أفراد') return t == 'أفراد';
    return true;
  }

  List<_ClientRow> get _rows {
    final List<_ClientRow> out = [];
    final q = _searchCtrl.text.trim().toLowerCase();

    for (final entry in _clients.entries) {
      final cid = entry.key;
      final info = entry.value;

      if (!_matchesType(info.type)) continue;

      final inv = _invByClient[cid] ?? 0.0;
      final paid = _paidByClient[cid] ?? 0.0;
      if (inv == 0 && paid == 0) continue;

      final remain = (inv - paid).clamp(-1e12, 1e12);

      if (q.isNotEmpty) {
        final hay = '${info.name} ${info.type}'.toLowerCase();
        if (!hay.contains(q)) continue;
      }

      out.add(_ClientRow(
        clientId: cid,
        name: info.name,
        type: info.type,
        invoiceTotal: inv,
        paid: paid,
        remain: remain,
        firstPayment: _firstPayByClient[cid],
        lastPayment: _lastPayByClient[cid],
      ));
    }
    out.sort((a, b) => b.remain.compareTo(a.remain));
    return out;
  }

  double get _sumInv => _rows.fold(0.0, (s, r) => s + r.invoiceTotal);
  double get _sumPaid => _rows.fold(0.0, (s, r) => s + r.paid);
  double get _sumRemain => _sumInv - _sumPaid;

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'نطاق التاريخ',
      locale: const Locale('ar'),
    );
    if (dr != null) {
      setState(() => _range = dr);
      await _load();
    }
  }

  void _clearRange() async {
    setState(() => _range = null);
    await _load();
  }

  Future<void> _showClientPayments(String clientId, String clientName) async {
    try {
      final db = await _db();
      if (!await _tableExists(db, 'journal_entries')) return;

      const accounts = [
        'العملاء',
        'عملاء',
        'Customers',
        'Accounts Receivable',
        'AR'
      ];
      final placeholders = List.filled(accounts.length, '?').join(',');

      // نحاول أولاً المسار الموحّد عبر repairs
      final rows = await db.rawQuery('''
        SELECT je.date AS date, je.description AS description, je.credit AS credit
        FROM journal_entries je
        JOIN repairs r ON r.id = je.relatedRepairId
        WHERE r.client_id = ?
          AND je.accountName IN ($placeholders)
          AND je.credit > 0
        ORDER BY je.date ASC, je.id ASC
      ''', [clientId, ...accounts]);

      // ولو ما فيه نتائج، نجرب عمود clientId (إن وُجد)
      List<Map<String, Object?>> rows2 = [];
      if (rows.isEmpty &&
          await _columnExists(db, 'journal_entries', 'clientId')) {
        rows2 = await db.rawQuery('''
          SELECT je.date AS date, je.description AS description, je.credit AS credit
          FROM journal_entries je
          WHERE je.clientId = ?
            AND je.accountName IN ($placeholders)
            AND je.credit > 0
          ORDER BY je.date ASC, je.id ASC
        ''', [clientId, ...accounts]);
      }

      final toShow = rows.isNotEmpty ? rows : rows2;

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          final inheritedDirection = Directionality.of(context);
          return Directionality(
            textDirection: inheritedDirection,
            child: DraggableScrollableSheet(
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
                        Text('دفعات العميل — $clientName',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 10),
                        Expanded(
                          child: toShow.isEmpty
                              ? const Center(
                                  child:
                                      Text('لا يوجد دفعات مسجلة لهذا العميل'),
                                )
                              : ListView.separated(
                                  controller: controller,
                                  itemCount: toShow.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 8),
                                  itemBuilder: (_, i) {
                                    final m = toShow[i];
                                    final dt = DateTime.tryParse(
                                            (m['date'] ?? '').toString()) ??
                                        DateTime(1970);
                                    final desc =
                                        (m['description'] ?? 'دفعة').toString();
                                    final val =
                                        (m['credit'] as num?)?.toDouble() ??
                                            0.0;
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
                            'الإجمالي: ${_currency.format(_paidByClient[clientId] ?? 0.0)}',
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
            ),
          );
        },
      );
    } catch (_) {
      // ignore
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final width = MediaQuery.of(context).size.width;
    final useCards = !isDesktop && width < 900;

    const currentRoute = '/clients/accounts-receivable';

    final tableColumnSpacing = _compact ? 12.0 : 22.0;
    final dataTextStyle = TextStyle(fontSize: _compact ? 12 : 14);
    final headerTextStyle =
        TextStyle(fontWeight: FontWeight.bold, fontSize: _compact ? 12 : 14);

    Widget totalsBar() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _chipStat('إجمالي الفواتير', _currency.format(_sumInv),
                  color: Colors.blueGrey),
              _chipStat('المدفوع', _currency.format(_sumPaid),
                  color: Colors.green),
              _chipStat('المتبقي', _currency.format(_sumRemain),
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
        title: const Text('الذمم المدينة (العملاء)'),
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
          IconButton(
            tooltip: _compact ? 'وضع مريح' : 'وضع مضغوط',
            icon: Icon(_compact ? Icons.density_small : Icons.density_medium),
            onPressed: () => setState(() => _compact = !_compact),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          IconButton(
            tooltip: 'إضافة دفعة',
            icon: const Icon(Icons.add),
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.payments),
          ),
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
                                    controller: _searchCtrl,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search),
                                      hintText: 'بحث بالاسم / النوع…',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                AdaptiveRow(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 190,
                                      child: DropdownButtonFormField<String>(
                                        value: _filterType,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'النوع',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'الكل',
                                              child: Text('الكل')),
                                          DropdownMenuItem(
                                              value: 'أفراد',
                                              child: Text('أفراد')),
                                          DropdownMenuItem(
                                              value: 'شركة تأمين',
                                              child: Text('شركة تأمين')),
                                        ],
                                        onChanged: (v) {
                                          if (v == null) return;
                                          setState(() => _filterType = v);
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
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
                            child: Builder(builder: (_) {
                              final list = _rows;
                              if (list.isEmpty) {
                                return const Center(
                                    child: Text(
                                        'لا توجد ذمم ضمن الفلاتر الحالية'));
                              }
                              return useCards
                                  ? _buildCards(list)
                                  : _buildTable(
                                      list,
                                      headerTextStyle,
                                      dataTextStyle,
                                      tableColumnSpacing,
                                    );
                            }),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ===== Table (desktop) =====
  Widget _buildTable(
    List<_ClientRow> list,
    TextStyle headerTextStyle,
    TextStyle dataTextStyle,
    double columnSpacing,
  ) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 0),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: AdaptiveDataTable(
                headingTextStyle: headerTextStyle,
                dataTextStyle: dataTextStyle,
                columnSpacing: columnSpacing,
                columns: const [
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('النوع')),
                  DataColumn(numeric: true, label: Text('إجمالي الفواتير')),
                  DataColumn(numeric: true, label: Text('المدفوع')),
                  DataColumn(numeric: true, label: Text('المتبقي')),
                  DataColumn(label: Text('أول دفعة')),
                  DataColumn(label: Text('آخر دفعة')),
                  DataColumn(label: Text('دفعات')),
                ],
                rows: list.map((r) {
                  return DataRow(
                    cells: [
                      DataCell(Text(r.name)),
                      DataCell(Text(r.type)),
                      DataCell(Text(_currency.format(r.invoiceTotal))),
                      DataCell(Text(_currency.format(r.paid),
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold))),
                      DataCell(Text(_currency.format(r.remain),
                          style: const TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold))),
                      DataCell(Text(r.firstPayment == null
                          ? '—'
                          : _df.format(r.firstPayment!))),
                      DataCell(Text(r.lastPayment == null
                          ? '—'
                          : _df.format(r.lastPayment!))),
                      DataCell(
                        r.paid <= 0
                            ? const Text('—')
                            : TextButton.icon(
                                onPressed: () =>
                                    _showClientPayments(r.clientId, r.name),
                                icon: const Icon(Icons.list),
                                label: const Text('عرض'),
                              ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Cards (narrow) =====
  Widget _buildCards(List<_ClientRow> list) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = list[i];
        return Card(
          elevation: 1.5,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdaptiveRow(
                  children: [
                    const Icon(Icons.badge),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(r.type, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _kv('إجمالي الفواتير', _currency.format(r.invoiceTotal)),
                    _kv('المدفوع', _currency.format(r.paid),
                        valueColor: Colors.green, isBold: true),
                    _kv('المتبقي', _currency.format(r.remain),
                        valueColor: Colors.red, isBold: true),
                    _kv(
                        'أول دفعة',
                        r.firstPayment == null
                            ? '—'
                            : _df.format(r.firstPayment!)),
                    _kv(
                        'آخر دفعة',
                        r.lastPayment == null
                            ? '—'
                            : _df.format(r.lastPayment!)),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: r.paid <= 0
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () =>
                              _showClientPayments(r.clientId, r.name),
                          icon: const Icon(Icons.list),
                          label: const Text('تفاصيل الدفعات'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===== Small UI helpers =====
  Widget _kv(String k, String v, {Color? valueColor, bool isBold = false}) {
    return AdaptiveRow(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(
          v,
          style: TextStyle(
            color: valueColor,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
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

// ===== Models (local) =====
class _ClientInfo {
  final String id;
  final String name;
  final String type;
  _ClientInfo({required this.id, required this.name, required this.type});
}

class _ClientRow {
  final String clientId;
  final String name;
  final String type;
  final double invoiceTotal;
  final double paid;
  final double remain;
  final DateTime? firstPayment;
  final DateTime? lastPayment;
  _ClientRow({
    required this.clientId,
    required this.name,
    required this.type,
    required this.invoiceTotal,
    required this.paid,
    required this.remain,
    required this.firstPayment,
    required this.lastPayment,
  });
}
