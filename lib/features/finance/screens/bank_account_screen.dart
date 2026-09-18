import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
import 'package:yalla_accounts/features/finance/services/liquidity_ledger_service.dart';
// 📁 lib/features/finance/screens/bank_account_screen.dart
//
// شاشة البنك — Bank Account (GL v29)
// - القراءة من gl_entries + gl_lines لحساب 1010 (مع join على accounts).
// - فلاتر: تاريخ (من/إلى) + بحث نصي يشمل (ref/note/source/source_id/account_name/account_code/invoice_id/repair_id).
// - مجاميع (مدين/دائن) + رصيد تراكمي يبدأ من Opening قبل from + رصيد ختامي.
// - جدول للديسكتوب وبطاقات للموبايل.
// - Tooltip لكل سطر يعرض ref / source / source_id / invoice_id / repair_id.
// - أزرار Refresh + Reset.
// - بدون إنشاء جداول.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class BankAccountScreen extends StatefulWidget {
  const BankAccountScreen({super.key});

  @override
  State<BankAccountScreen> createState() => _BankAccountScreenState();
}

class _BankAccountScreenState extends State<BankAccountScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  DateTime? _from;
  DateTime? _to;
  String _query = '';
  bool _loading = true;
  String? _error;

  int? _bankAccountId; // account_id للبنك (1010)

  List<_Entry> _rows = [];
  double _sumDebit = 0;
  double _sumCredit = 0;
  double _openingBalance = 0; // ✅ جديد: رصيد افتتاحي قبل from

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _bankAccountId = await DBService.getAccountIdByCode('1010');
      if (_bankAccountId == null) {
        throw StateError(
            'حساب البنك (code=1010) غير موجود. نفّذ seeding للحسابات الافتراضية.');
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  int _loadVersion = 0;
  Future<void> _load() async {
    if (!mounted) return;
    if (!mounted) return;
    final version = ++_loadVersion;
    if (_bankAccountId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_from != null && _to != null && _from!.isAfter(_to!)) {
        throw ArgumentError('بداية الفترة بعد نهايتها');
      }
      final db = await DBService.database;

      final statement = await LiquidityLedgerService.load(db, _bankAccountId!,
          from: _from, to: _to, query: _query);
      final opening = statement.opening;
      final maps = statement.rows;
      double running = opening;
      final rows = <_Entry>[];

      for (final m in maps) {
        final d = (m['debit'] is num) ? (m['debit'] as num).toDouble() : 0.0;
        final c = (m['credit'] is num) ? (m['credit'] as num).toDouble() : 0.0;
        running = (m['running_balance'] as num).toDouble();

        rows.add(
          _Entry(
            id: (m['entry_id'] as num).toInt(),
            date: DateTime.tryParse(m['date']?.toString() ?? '') ??
                DateTime(1970, 1, 1),
            description: (m['note']?.toString() ?? '').isNotEmpty
                ? m['note'].toString()
                : (m['ref']?.toString() ?? ''),
            debit: d,
            credit: c,
            accountCode: (m['account_code'] ?? '').toString(),
            accountName: (m['account_name'] ?? '').toString(),
            relatedRepairId: (m['repair_id'] ?? '').toString().isEmpty
                ? m['source_id']?.toString()
                : m['repair_id']?.toString(),
            ref: m['ref']?.toString(),
            source: m['source']?.toString(),
            sourceId: m['source_id']?.toString(),
            invoiceId: m['invoice_id']?.toString(),
            repairId: m['repair_id']?.toString(),
            runningBalance: running,
          ),
        );
      }

      if (!mounted || version != _loadVersion) return;
      setState(() {
        _rows = rows;
        _sumDebit = statement.debit;
        _sumCredit = statement.credit;
        _openingBalance = opening; // ✅ تخزين الافتتاحي للواجهة
      });
    } catch (e) {
      if (!mounted || version != _loadVersion) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted && version == _loadVersion) setState(() => _loading = false);
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      locale: const Locale('ar'),
    );
    if (d != null && mounted) {
      setState(() => _from = d);
      _load();
    }
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
    if (d != null && mounted) {
      setState(() => _to = d);
      _load();
    }
  }

  void _resetFilters() {
    setState(() {
      _from = null;
      _to = null;
      _query = '';
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = !Responsive.isDesktop(context);

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FinancialPeriodFilter(
              from: _from,
              to: _to,
              onChanged: (range) {
                setState(() {
                  _from = range.start;
                  _to = range.end;
                });
                _load();
              }),
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          const Text(
            'الحساب البنكي',
            style: TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          _ChipButton(
              label: _from == null ? 'من' : _df.format(_from!),
              icon: Icons.date_range,
              onTap: _pickFrom),
          const SizedBox(width: 8),
          _ChipButton(
              label: _to == null ? 'إلى' : _df.format(_to!),
              icon: Icons.event,
              onTap: _pickTo),
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              textAlign: TextAlign.right,
              onChanged: (v) {
                setState(() => _query = v);
                _load();
              },
              decoration: InputDecoration(
                hintText: 'بحث: المرجع/الوصف/المصدر/رقم/اسم/كود/فاتورة/إصلاح…',
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh, color: Colors.white)),
          IconButton(
              tooltip: 'مسح الفلاتر',
              onPressed: _resetFilters,
              icon: const Icon(Icons.clear_all, color: Colors.white)),
        ],
      ),
    );

    final closing = _openingBalance + (_sumDebit - _sumCredit); // ✅ ختامي صحيح

    final totalsBar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          _Stat(
              label: 'رصيد افتتاحي',
              value: _money.format(_openingBalance),
              color: Colors.blueGrey),
          _Stat(
              label: 'إجمالي مدين',
              value: _money.format(_sumDebit),
              color: AppColors.primary),
          _Stat(
              label: 'إجمالي دائن',
              value: _money.format(_sumCredit),
              color: Colors.red),
          _Stat(
            label: 'الرصيد الختامي',
            value: _money.format(closing),
            color: closing >= 0 ? AppColors.primary : Colors.red,
            bold: true,
          ),
        ],
      ),
    );

    final content = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Text(
                  'تعذر تحميل البيانات:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            : _rows.isEmpty
                ? const _EmptyState(
                    icon: Icons.account_balance,
                    title: 'لا توجد حركات بنكية ضمن الفلاتر الحالية',
                    subtitle:
                        'عدّل التاريخ/البحث أو أضف قيودًا عبر عمليات النظام.',
                  )
                : isMobile
                    ? _MobileList(rows: _rows, money: _money)
                    : _DesktopTable(rows: _rows, money: _money);

    return Scaffold(
      drawer: isMobile ? const Drawer(child: YallaSidebar()) : null,
      body: AdaptiveRow(
        children: [
          if (!isMobile) const YallaSidebar(currentRoute: '/finance/bank'),
          Expanded(
            child: SafeArea(
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(child: header),
                  SliverToBoxAdapter(child: totalsBar),
                ],
                body: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Widgets/Models داخلي ─────────────────────────

class _Entry {
  final int id; // entry_id
  final DateTime date;
  final String description; // note أو ref
  final double debit;
  final double credit;
  final String accountCode; // من join
  final String accountName; // من join
  final String? relatedRepairId; // fallback قديم من source_id
  final String? ref;
  final String? source;
  final String? sourceId;
  final String? invoiceId;
  final String? repairId; // من gl_lines
  final double runningBalance;

  _Entry({
    required this.id,
    required this.date,
    required this.description,
    required this.debit,
    required this.credit,
    required this.accountCode,
    required this.accountName,
    required this.relatedRepairId,
    required this.runningBalance,
    this.ref,
    this.source,
    this.sourceId,
    this.invoiceId,
    this.repairId,
  });
}

class _DesktopTable extends StatelessWidget {
  final List<_Entry> rows;
  final NumberFormat money;
  const _DesktopTable({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AdaptiveDataTable(
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('الحساب')),
            DataColumn(label: Text('الوصف')),
            DataColumn(label: Text('مدين')),
            DataColumn(label: Text('دائن')),
            DataColumn(label: Text('الرصيد')),
          ],
          rows: rows.map((e) {
            final tip = [
              if ((e.ref ?? '').isNotEmpty) 'ref: ${e.ref}',
              if ((e.source ?? '').isNotEmpty) 'source: ${e.source}',
              if ((e.sourceId ?? '').isNotEmpty) 'source_id: ${e.sourceId}',
              if ((e.invoiceId ?? '').isNotEmpty) 'invoice_id: ${e.invoiceId}',
              if ((e.repairId ?? '').isNotEmpty) 'repair_id: ${e.repairId}',
            ].join('  •  ');
            return DataRow(cells: [
              DataCell(Text(DateFormat('yyyy-MM-dd').format(e.date))),
              DataCell(Text('${e.accountCode} — ${e.accountName}')),
              DataCell(
                Tooltip(
                  message: tip.isEmpty ? 'لا توجد بيانات مرجعية' : tip,
                  child: Text(e.description, textAlign: TextAlign.right),
                ),
              ),
              DataCell(Text(money.format(e.debit),
                  style: const TextStyle(color: AppColors.primary))),
              DataCell(Text(money.format(e.credit),
                  style: const TextStyle(color: Colors.red))),
              DataCell(Text(
                money.format(e.runningBalance),
                style: TextStyle(
                  color: e.runningBalance >= 0 ? AppColors.primary : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _MobileList extends StatelessWidget {
  final List<_Entry> rows;
  final NumberFormat money;
  const _MobileList({required this.rows, required this.money});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final e = rows[i];
        final tip = [
          if ((e.ref ?? '').isNotEmpty) 'ref: ${e.ref}',
          if ((e.source ?? '').isNotEmpty) 'source: ${e.source}',
          if ((e.sourceId ?? '').isNotEmpty) 'source_id: ${e.sourceId}',
          if ((e.invoiceId ?? '').isNotEmpty) 'invoice_id: ${e.invoiceId}',
          if ((e.repairId ?? '').isNotEmpty) 'repair_id: ${e.repairId}',
        ].join('  •  ');
        return Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            title: Text('${e.accountCode} — ${e.accountName}',
                textAlign: TextAlign.right),
            subtitle: Text(
              '${DateFormat('yyyy-MM-dd').format(e.date)}\n${e.description}',
              textAlign: TextAlign.right,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            leading: Tooltip(
              message: tip.isEmpty ? 'لا توجد بيانات مرجعية' : tip,
              child: const Icon(Icons.info_outline),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money.format(e.runningBalance),
                  style: TextStyle(
                    color:
                        e.runningBalance >= 0 ? AppColors.primary : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                AdaptiveRow(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(money.format(e.debit),
                        style: const TextStyle(color: AppColors.primary)),
                    const SizedBox(width: 8),
                    Text(money.format(e.credit),
                        style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool bold;
  const _Stat(
      {required this.label,
      required this.value,
      required this.color,
      this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: color.withOpacity(0.08),
      label: AdaptiveRow(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 2),
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _ChipButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Chip(
        labelPadding: const EdgeInsetsDirectional.only(start: 6, end: 10),
        avatar: Icon(icon, size: 18, color: Colors.white),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
