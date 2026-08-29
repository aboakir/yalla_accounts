import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});

  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  bool _loading = true;
  String? _error;

  double _sumDebit = 0;
  double _sumCredit = 0;

  double _cashBalance = 0;
  double _bankBalance = 0;

  List<_AccountAgg> _topAccounts = [];
  List<_EntryLine> _latestLines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // FILTER WHERE
  // ---------------------------------------------------------------------------
  String _dateFilterWhere(List<Object?> args) {
    final where = <String>[];

    if (_from != null) {
      where.add('e.date >= ?');
      args.add(_from!.toIso8601String());
    }
    if (_to != null) {
      final d = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
      where.add('e.date <= ?');
      args.add(d.toIso8601String());
    }
    if (_query.trim().isNotEmpty) {
      final q = '%${_query.trim().toLowerCase()}%';
      where.add(
          '(LOWER(e.note) LIKE ? OR LOWER(e.source) LIKE ? OR LOWER(a.name) LIKE ? OR LOWER(a.code) LIKE ?)');
      args
        ..add(q)
        ..add(q)
        ..add(q)
        ..add(q);
    }

    return where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
  }

  // ---------------------------------------------------------------------------
  // LOAD DATA
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final db = await DBService.database;

      // Total Debit / Credit
      {
        final args = <Object?>[];
        final where = _dateFilterWhere(args);

        final rows = await db.rawQuery('''
          SELECT IFNULL(SUM(l.debit),0) AS d,
                 IFNULL(SUM(l.credit),0) AS c
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id = e.id
          JOIN accounts a ON a.id = l.account_id
          $where
        ''', args);

        _sumDebit = ((rows.first['d'] as num?) ?? 0).toDouble();
        _sumCredit = ((rows.first['c'] as num?) ?? 0).toDouble();
      }

      // Cash + Bank
      final cashId = await DBService.getAccountIdByCode('1000');
      final bankId = await DBService.getAccountIdByCode('1010');

      Future<double> bal(int? acc) async {
        if (acc == null) return 0.0;

        final args = <Object?>[acc];
        final whereParts = <String>['l.account_id = ?'];

        if (_from != null) {
          whereParts.add('e.date >= ?');
          args.add(_from!.toIso8601String());
        }
        if (_to != null) {
          final d = DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
          whereParts.add('e.date <= ?');
          args.add(d.toIso8601String());
        }

        final rows = await db.rawQuery('''
          SELECT IFNULL(SUM(l.debit - l.credit),0) AS bal
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id = e.id
          WHERE ${whereParts.join(' AND ')}
        ''', args);

        return ((rows.first['bal'] as num?) ?? 0).toDouble();
      }

      _cashBalance = await bal(cashId);
      _bankBalance = await bal(bankId);

      // Top Accounts
      {
        final args = <Object?>[];
        final where = _dateFilterWhere(args);

        final rows = await db.rawQuery('''
          SELECT a.code, a.name,
                 IFNULL(SUM(l.debit),0) AS debit,
                 IFNULL(SUM(l.credit),0) AS credit
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id = e.id
          JOIN accounts a ON a.id = l.account_id
          $where
          GROUP BY a.id
          ORDER BY ABS(SUM(l.debit - l.credit)) DESC
          LIMIT 10
        ''', args);

        _topAccounts = rows
            .map((r) => _AccountAgg(
                  name:
                      '${r['code'] ?? ''} — ${(r['name'] as String?)?.trim() ?? ''}',
                  debit: ((r['debit'] as num?) ?? 0).toDouble(),
                  credit: ((r['credit'] as num?) ?? 0).toDouble(),
                ))
            .toList();
      }

      // Latest Lines
      {
        final args = <Object?>[];
        final where = _dateFilterWhere(args);

        final rows = await db.rawQuery('''
          SELECT e.id AS entry_id, e.date, e.source, e.source_id, e.note,
                 a.code, a.name AS account_name,
                 l.debit, l.credit
          FROM gl_entries e
          JOIN gl_lines l ON l.entry_id = e.id
          JOIN accounts a ON a.id = l.account_id
          $where
          ORDER BY e.date DESC, e.id DESC, l.id DESC
          LIMIT 20
        ''', args);

        _latestLines = rows
            .map((r) => _EntryLine(
                  entryId: (r['entry_id'] as num).toInt(),
                  date:
                      DateTime.tryParse('${r['date']}') ?? DateTime(1970, 1, 1),
                  description: (() {
                    final note = (r['note'] as String?)?.trim();
                    if (note != null && note.isNotEmpty) return note;

                    final s = (r['source'] as String?)?.trim() ?? '';
                    final id = (r['source_id'] as String?)?.trim() ?? '';
                    return 'القيد: $s ${id.isNotEmpty ? "($id)" : ""}';
                  })(),
                  accountName:
                      '${r['code'] ?? ''} — ${(r['account_name'] as String?)?.trim() ?? ''}',
                  debit: ((r['debit'] as num?) ?? 0).toDouble(),
                  credit: ((r['credit'] as num?) ?? 0).toDouble(),
                ))
            .toList();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // DATE PICKERS
  // ---------------------------------------------------------------------------
  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() => _from = d);
    _load();
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('ar'),
    );
    if (d != null) setState(() => _to = d);
    _load();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: Row(
        children: [
          if (!isMobile) const YallaSidebar(currentRoute: '/finance/dashboard'),
          Expanded(
            child: Column(
              children: [
                _buildHeader(isMobile),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(
                                'تعذر تحميل البيانات:\n$_error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : _buildBody(),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------
  Widget _buildHeader(bool mobile) {
    return Material(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mobile)
                    IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  const Text(
                    'لوحة المالية',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              _dateChip(_from == null ? 'من' : _df.format(_from!), _pickFrom),
              _dateChip(_to == null ? 'إلى' : _df.format(_to!), _pickTo),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
                child: TextField(
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'بحث...',
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    setState(() => _query = v);
                    _load();
                  },
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateChip(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        label: Text(label, style: const TextStyle(color: Colors.white)),
        avatar: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BODY — NEW PRO DESIGN
  // ---------------------------------------------------------------------------
  Widget _buildBody() {
    final net = _sumDebit - _sumCredit;

    final kpiCards = [
      _KpiSmall(
          title: 'إجمالي مدين',
          value: _money.format(_sumDebit),
          color: Colors.green,
          icon: Icons.south_west),
      _KpiSmall(
          title: 'إجمالي دائن',
          value: _money.format(_sumCredit),
          color: Colors.red,
          icon: Icons.north_east),
      _KpiSmall(
          title: 'الصافي',
          value: _money.format(net),
          color: net >= 0 ? Colors.green : Colors.red,
          icon: Icons.balance),
      _KpiSmall(
          title: 'رصيد الصندوق',
          value: _money.format(_cashBalance),
          color: _cashBalance >= 0 ? Colors.green : Colors.red,
          icon: Icons.account_balance_wallet),
      _KpiSmall(
          title: 'رصيد البنك',
          value: _money.format(_bankBalance),
          color: _bankBalance >= 0 ? Colors.green : Colors.red,
          icon: Icons.account_balance),
    ];

    return Container(
      color: const Color(0xfff7f9f4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KPIs — Row scrollable
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) => kpiCards[i],
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: kpiCards.length,
              ),
            ),

            const SizedBox(height: 28),

            const _SectionTitle('أكثر الحسابات حركة'),
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _TopAccountsTable(rows: _topAccounts, money: _money),
              ),
            ),

            const SizedBox(height: 28),

            const _SectionTitle('آخر القيود'),
            const SizedBox(height: 12),

            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _LatestLines(rows: _latestLines, money: _money),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------
class _EntryLine {
  final int entryId;
  final DateTime date;
  final String description;
  final String accountName;
  final double debit;
  final double credit;

  _EntryLine({
    required this.entryId,
    required this.date,
    required this.description,
    required this.accountName,
    required this.debit,
    required this.credit,
  });
}

class _AccountAgg {
  final String name;
  final double debit;
  final double credit;

  const _AccountAgg({
    required this.name,
    required this.debit,
    required this.credit,
  });

  double get net => debit - credit;
}

// ---------------------------------------------------------------------------
// WIDGETS
// ---------------------------------------------------------------------------
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: Colors.black87,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// KPI Small
// ---------------------------------------------------------------------------
class _KpiSmall extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiSmall({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withOpacity(0.12),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: color,
                    )),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TABLES
// ---------------------------------------------------------------------------
class _TopAccountsTable extends StatelessWidget {
  final List<_AccountAgg> rows;
  final NumberFormat money;

  const _TopAccountsTable({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('لا توجد بيانات ضمن الفلاتر الحالية')),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 32,
        headingRowColor: MaterialStateProperty.all(Colors.grey.shade200),
        dataRowHeight: 48,
        columns: const [
          DataColumn(label: Text('الحساب')),
          DataColumn(label: Text('مدين')),
          DataColumn(label: Text('دائن')),
          DataColumn(label: Text('الصافي')),
        ],
        rows: rows
            .map((a) => DataRow(cells: [
                  DataCell(Text(a.name)),
                  DataCell(Text(
                    money.format(a.debit),
                    style: const TextStyle(color: Colors.green),
                  )),
                  DataCell(Text(
                    money.format(a.credit),
                    style: const TextStyle(color: Colors.red),
                  )),
                  DataCell(Text(
                    money.format(a.net),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: a.net >= 0 ? Colors.green : Colors.red,
                    ),
                  )),
                ]))
            .toList(),
      ),
    );
  }
}

class _LatestLines extends StatelessWidget {
  final List<_EntryLine> rows;
  final NumberFormat money;

  const _LatestLines({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: Text('لا توجد قيود ضمن الفلاتر الحالية')),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = rows[i];
        final net = e.debit - e.credit;

        return Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: Colors.white,
          child: ListTile(
            title: Text(e.description, textAlign: TextAlign.right),
            subtitle: Text(
              '${DateFormat('yyyy-MM-dd – HH:mm').format(e.date)}  •  ${e.accountName}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  money.format(net),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: net >= 0 ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      money.format(e.debit),
                      style: const TextStyle(color: Colors.green),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      money.format(e.credit),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
