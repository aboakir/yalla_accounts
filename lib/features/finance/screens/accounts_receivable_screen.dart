// 📁 lib/features/finance/screens/accounts_receivable_screen.dart
//
// Accounts Receivable (Individuals / Insurance) — v19 Unified (Pro UI)
// -------------------------------------------------------------------
// المصدر: v_client_ar + invoices + payments + repairs
// - فلترة البحث + حالة السداد + نطاق تاريخ (يطبَّق على الدفعات فقط)
// - تبويبات: أفراد / شركة تأمين (مع عدّاد لكل تبويب)
// - KPIs أعلى الشاشة (إجمالي الفواتير/المدفوع/المتبقي)
// - ديسكتوب: DataTable احترافي / موبايل: بطاقات أنيقة
// - BottomSheet لعرض ملفات العميل (الإجمالي/المدفوع/المتبقي لكل ملف) + صورة thumbnail لكل ملف
// - تصدير CSV لما هو ظاهر
//
// يتطلب: DBService v19+ ويوجد view باسم v_client_ar

import 'dart:convert';
import 'dart:io';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

// ✅ لإظهار صورة غلاف الملف (تلقائيًا عبر DBService.getRepairThumbnailPath)
import 'package:yalla_accounts/features/repairs/widgets/repair_thumb.dart';

class AccountsReceivableScreen extends StatefulWidget {
  const AccountsReceivableScreen({super.key});
  @override
  State<AccountsReceivableScreen> createState() =>
      _AccountsReceivableScreenState();
}

class _AccountsReceivableScreenState extends State<AccountsReceivableScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  bool _loading = true;
  String? _error;

  // فلاتر
  String _query = '';
  String _status = 'الكل'; // 'الكل' | 'مسدد' | 'مسدد جزئي' | 'غير مسدد'
  DateTimeRange? _range; // يقيّد الدفعات فقط

  // بيانات
  final List<_ClientRow> _allRows = [];

  // واجهة
  final bool _showSidebar = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<Database> _db() => DBService.database;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await _db();

      // تأكيد وجود الـ View
      final viewOk = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='view' AND name='v_client_ar' LIMIT 1",
      );
      if (viewOk.isEmpty) {
        throw StateError(
          'v_client_ar غير موجود. شغّل ترقية DBService v19 أو resetDatabase أثناء التطوير.',
        );
      }

      // 1) قراءة الذمم من v_client_ar
      final arRows = await db.rawQuery('''
        SELECT client_id, client_name, IFNULL(invoices_total,0) AS invoices_total,
               IFNULL(payments_total,0) AS payments_total,
               IFNULL(balance_due,0) AS balance_due
        FROM v_client_ar
        ORDER BY LOWER(client_name) ASC
      ''');

      // 2) نوع العميل من clients → 'شركة تأمين' | 'أفراد'
      final typesRows = await db.rawQuery('SELECT id, type FROM clients');
      final typeById = <int, String>{};
      for (final m in typesRows) {
        final id = (m['id'] as num?)?.toInt();
        if (id == null) continue;
        final t = (m['type'] ?? '').toString().trim().toLowerCase();
        typeById[id] = (t == 'insurance' || t == 'شركة تأمين' || t == 'تأمين')
            ? 'شركة تأمين'
            : 'أفراد';
      }

      // 3) لو في نطاق تاريخ → المدفوع ضمن النطاق فقط
      final paidInRange = <int, double>{};
      if (_range != null) {
        final s = _df.format(DateTime(
            _range!.start.year, _range!.start.month, _range!.start.day));
        final e = _df.format(
            DateTime(_range!.end.year, _range!.end.month, _range!.end.day));
        final rangePay = await db.rawQuery('''
          SELECT
            COALESCE(
              p.client_id,
              (SELECT r.client_id FROM repairs r WHERE r.id = p.repair_id)
            ) AS cid,
            IFNULL(SUM(p.amount),0) AS tot
          FROM payments p
          WHERE p.date >= ? AND p.date <= ?
          GROUP BY 1
        ''', [s, e]);

        for (final m in rangePay) {
          final cidVal = m['cid'];
          if (cidVal == null) continue;
          final cid = (cidVal is num)
              ? cidVal.toInt()
              : int.tryParse(cidVal.toString());
          if (cid != null) {
            paidInRange[cid] = (m['tot'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      _allRows
        ..clear()
        ..addAll(arRows.map((m) {
          final cid = (m['client_id'] as num).toInt();
          final name = (m['client_name'] ?? '').toString();
          final inv = (m['invoices_total'] as num?)?.toDouble() ?? 0.0;
          final paid = _range == null
              ? (m['payments_total'] as num?)?.toDouble() ?? 0.0
              : (paidInRange[cid] ?? 0.0);
          final balance = inv - paid;
          final type = typeById[cid] ?? 'أفراد';
          return _ClientRow(
            clientId: cid,
            name: name,
            type: type,
            invoicesTotal: inv,
            paymentsTotal: paid,
            balance: balance,
          );
        }));

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ===== مشتقات الفلاتر =====
  List<_ClientRow> get _filtered {
    final tabType = _tabs.index == 0 ? 'أفراد' : 'شركة تأمين';
    final q = _query.trim().toLowerCase();

    final list = _allRows.where((r) {
      if (r.type != tabType) return false;

      if (q.isNotEmpty) {
        final hay = '${r.name} ${r.type}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }

      final fullyPaid = r.balance.abs() < 0.0001;
      final noPayment = r.paymentsTotal.abs() < 0.0001;

      switch (_status) {
        case 'مسدد':
          return fullyPaid;
        case 'غير مسدد':
          return noPayment;
        case 'مسدد جزئي':
          return !(fullyPaid || noPayment);
        default:
          return true;
      }
    }).toList();

    list.sort((a, b) => b.balance.compareTo(a.balance));
    return list;
  }

  double get _sumInv => _filtered.fold(0.0, (s, r) => s + r.invoicesTotal);
  double get _sumPaid => _filtered.fold(0.0, (s, r) => s + r.paymentsTotal);
  double get _sumRemain => _sumInv - _sumPaid;

  // ===== أفعال =====
  Future<void> _pickRange() async {
    final now = DateTime.now();
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'نطاق تواريخ الدفعات فقط',
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

  Future<void> _exportCsv(List<_ClientRow> list) async {
    try {
      final sb = StringBuffer()
        ..writeln('client,type,invoices_total,paid,balance');
      for (final r in list) {
        sb.writeln([
          r.name.replaceAll(',', ' '),
          r.type == 'شركة تأمين' ? 'Insurance' : 'Individual',
          r.invoicesTotal.toStringAsFixed(2),
          r.paymentsTotal.toStringAsFixed(2),
          r.balance.toStringAsFixed(2),
        ].join(','));
      }
      final dir = await getDownloadsDirectory();
      final file = File('${dir!.path}/accounts_receivable.csv');
      await file.writeAsString(sb.toString(), encoding: utf8);
      await Share.shareXFiles([XFile(file.path)], text: 'AR Export');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل تصدير CSV: $e')));
    }
  }

  Future<void> _openClientDetails(_ClientRow row) async {
    // تفاصيل ملفات العميل: إجمالي/مدفوع/متبقي لكل repair_id
    final db = await _db();

    // إجمالي الفواتير لكل ملف
    final invRows = await db.rawQuery('''
      SELECT repair_id AS rid, IFNULL(SUM(total),0) AS tot
      FROM invoices
      WHERE client_id = ?
      GROUP BY repair_id
    ''', [row.clientId]);

    // مدفوعات كل ملف ضمن النطاق الزمني (إن وجد)
    final payArgs = <Object?>[row.clientId];
    String payWhere =
        'COALESCE(p.client_id, (SELECT r.client_id FROM repairs r WHERE r.id = p.repair_id)) = ?';
    if (_range != null) {
      final s = _df.format(
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day));
      final e = _df.format(
          DateTime(_range!.end.year, _range!.end.month, _range!.end.day));
      payWhere += ' AND p.date >= ? AND p.date <= ?';
      payArgs.addAll([s, e]);
    }
    final payRows = await db.rawQuery('''
      SELECT repair_id AS rid, IFNULL(SUM(amount),0) AS tot
      FROM payments p
      WHERE $payWhere
      GROUP BY repair_id
    ''', payArgs);

    final invByRid = <String, double>{};
    for (final m in invRows) {
      final rid = (m['rid'] ?? '').toString();
      if (rid.isEmpty) continue;
      invByRid[rid] = (m['tot'] as num?)?.toDouble() ?? 0.0;
    }

    final paidByRid = <String, double>{};
    for (final m in payRows) {
      final rid = (m['rid'] ?? '').toString();
      if (rid.isEmpty) continue;
      paidByRid[rid] = (m['tot'] as num?)?.toDouble() ?? 0.0;
    }

    // بطاقة الملف من repairs
    final metaRows = await db.rawQuery('''
      SELECT id, vehicleType, vehicleModel, vehicleNumber, receivedDate
      FROM repairs
      WHERE client_id = ?
    ''', [row.clientId]);

    final details = <_RepairAgg>[];
    for (final m in metaRows) {
      final rid = (m['id'] ?? '').toString();
      if (rid.isEmpty) continue;
      final vt = (m['vehicleType'] ?? '').toString();
      final vm = (m['vehicleModel'] ?? '').toString();
      final vn = (m['vehicleNumber'] ?? '').toString();
      final labelParts = <String>[];
      if (vt.isNotEmpty) labelParts.add(vt);
      if (vm.isNotEmpty) labelParts.add(vm);
      if (vn.isNotEmpty) labelParts.add(vn);
      final label = labelParts.isEmpty ? rid : labelParts.join(' – ');

      details.add(_RepairAgg(
        id: rid,
        label: label,
        invoiceTotal: invByRid[rid] ?? 0.0,
        paid: paidByRid[rid] ?? 0.0,
        receivedDate: DateTime.tryParse((m['receivedDate'] ?? '').toString()),
      ));
    }

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
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, controller) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: [
                    Row(children: [
                      Text('تفاصيل: ${row.name}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      _statChip('إجمالي', _money.format(row.invoicesTotal),
                          Colors.blueGrey),
                      const SizedBox(width: 6),
                      _statChip('مدفوع', _money.format(row.paymentsTotal),
                          Colors.green),
                      const SizedBox(width: 6),
                      _statChip(
                          'متبقي', _money.format(row.balance), Colors.red),
                      IconButton(
                        tooltip: 'تصدير PDF',
                        icon:
                            const Icon(Icons.picture_as_pdf, color: Colors.red),
                        onPressed: () async {
                          final settings = await WorkshopSettingsService
                              .instance
                              .getOrDefaults();

                          await YallaPdfService.generateClientArDetailsPdf(
                            clientName: row.name,
                            clientType: row.type,
                            total: row.invoicesTotal,
                            paid: row.paymentsTotal,
                            remain: row.balance,
                            rows: details
                                .map((r) => {
                                      'label': r.label,
                                      'received': r.receivedDate == null
                                          ? '-'
                                          : DateFormat('yyyy-MM-dd')
                                              .format(r.receivedDate!),
                                      'total': r.invoiceTotal,
                                      'paid': r.paid,
                                      'remain': r.invoiceTotal - r.paid,
                                    })
                                .toList(),
                            workshopName: settings.workshopName ?? '',
                            logoPath: settings.logoPath,
                          );
                        },
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Expanded(
                      child: details.isEmpty
                          ? const Center(
                              child: Text('لا توجد ملفات إصلاح لهذا العميل'))
                          : Scrollbar(
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: controller,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(bottom: 8),
                                child: DataTable(
                                  headingTextStyle: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  columns: const [
                                    DataColumn(label: Text('الملف / المركبة')),
                                    DataColumn(label: Text('تاريخ الاستلام')),
                                    DataColumn(label: Text('الإجمالي')),
                                    DataColumn(label: Text('المدفوع')),
                                    DataColumn(label: Text('المتبقي')),
                                    DataColumn(label: Text('إجراء')),
                                  ],
                                  rows: details.map((a) {
                                    final remain = (a.invoiceTotal - a.paid);
                                    return DataRow(cells: [
                                      DataCell(
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // ✅ صورة غلاف الملف
                                            RepairThumb(
                                              repairId: a.id,
                                              size: 28,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                a.label,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DataCell(Text(a.receivedDate == null
                                          ? '-'
                                          : DateFormat('yyyy-MM-dd')
                                              .format(a.receivedDate!))),
                                      DataCell(
                                          Text(_money.format(a.invoiceTotal))),
                                      DataCell(Text(_money.format(a.paid),
                                          style: const TextStyle(
                                              color: Colors.green))),
                                      DataCell(Text(_money.format(remain),
                                          style: const TextStyle(
                                              color: Colors.red))),
                                      DataCell(
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            Navigator.of(context)
                                                .pushNamed(AppRoutes.payments);
                                          },
                                          icon: const Icon(Icons.add),
                                          label: const Text('سداد'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ]);
                                  }).toList(),
                                ),
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
  }

  // ===== واجهة =====
  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      drawer: Responsive.isDesktop(context) || _showSidebar
          ? null
          : const Drawer(
              child: YallaSidebar(
                currentRoute: '/finance/accounts-receivable',
              ),
            ),
      body: Row(
        children: [
          if (Responsive.isDesktop(context) && _showSidebar)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/finance/accounts-receivable'),
            ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  // ---------------------------
                  // NEW TOP APP BAR
                  // ---------------------------
                  Container(
                    height: 60,
                    color: AppColors.primary,
                    child: Row(
                      children: [
                        if (!Responsive.isDesktop(context))
                          IconButton(
                            icon: const Icon(Icons.menu, color: Colors.white),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        const SizedBox(width: 12),
                        const Text(
                          'ذمم العملاء وإدارة الدفعات',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),

                        // --------------------------
                        // زر PDF الجديد
                        // --------------------------
                        IconButton(
                          tooltip: "طباعة PDF",
                          icon: const Icon(Icons.picture_as_pdf,
                              color: Colors.white),
                          onPressed: () async {
                            final settings = await WorkshopSettingsService
                                .instance
                                .getOrDefaults();

                            await YallaPdfService.generateAccountsReceivablePdf(
                              _filtered
                                  .map((c) => {
                                        'name': c.name,
                                        'total': c.invoicesTotal,
                                        'paid': c.paymentsTotal,
                                        'remain': c.balance,
                                      })
                                  .toList(),
                              workshopName:
                                  settings.workshopName ?? "ورشة بدون اسم",
                              logoPath: settings.logoPath,
                            );
                          },
                        ),

                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: _load,
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),

                  // ---------------------------
                  // KPIs
                  // ---------------------------
                  _HeaderKpis(
                    sumInv: _money.format(_sumInv),
                    sumPaid: _money.format(_sumPaid),
                    sumRemain: _money.format(_sumRemain),
                  ),

                  // ---------------------------
                  // FILTERS BAR
                  // ---------------------------
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'بحث باسم العميل…',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            _StatusPicker(
                              value: _status,
                              onChanged: (v) => setState(() => _status = v),
                            ),
                            OutlinedButton.icon(
                              onPressed: _pickRange,
                              icon: const Icon(Icons.date_range),
                              label: Text(
                                _range == null
                                    ? 'كل التواريخ (الدفعات)'
                                    : '${_df.format(_range!.start)} → ${_df.format(_range!.end)}',
                              ),
                            ),
                            if (_range != null)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearRange,
                              ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                              ),
                              onPressed: () => _exportCsv(_filtered),
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('تصدير CSV'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 4),

                  // ---------------------------
                  // TABS
                  // ---------------------------
                  Material(
                    color: Colors.transparent,
                    child: TabBar(
                      controller: _tabs,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primary,
                      tabs: [
                        Tab(
                          text:
                              'أفراد (${_allRows.where((e) => e.type == "أفراد").length})',
                        ),
                        Tab(
                          text:
                              'شركة تأمين (${_allRows.where((e) => e.type == "شركة تأمين").length})',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 6),

                  // ---------------------------
                  // LIST AREA
                  // ---------------------------
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(
                                child: Text(
                                  'خطأ أثناء التحميل:\n$_error',
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : Responsive.isDesktop(context)
                                ? _DesktopTable(
                                    rows: _filtered,
                                    money: _money,
                                    onOpen: _openClientDetails,
                                  )
                                : RefreshIndicator(
                                    onRefresh: _load,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 8, 12, 16),
                                      itemCount: _filtered.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 8),
                                      itemBuilder: (_, i) => _ClientCard(
                                        row: _filtered[i],
                                        money: _money,
                                        onOpen: _openClientDetails,
                                      ),
                                    ),
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Helpers UI =====
  Widget _statChip(String label, String value, Color color) {
    return Chip(
      backgroundColor: color.withOpacity(.08),
      label: Row(
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

// ===== نماذج عرض =====
class _ClientRow {
  final int clientId;
  final String name; // اسم العميل
  final String type; // 'أفراد' | 'شركة تأمين'
  final double invoicesTotal;
  final double paymentsTotal;
  final double balance;

  _ClientRow({
    required this.clientId,
    required this.name,
    required this.type,
    required this.invoicesTotal,
    required this.paymentsTotal,
    required this.balance,
  });
}

class _RepairAgg {
  final String id;
  final String label;
  final double invoiceTotal;
  final double paid;
  final DateTime? receivedDate;

  _RepairAgg({
    required this.id,
    required this.label,
    required this.invoiceTotal,
    required this.paid,
    this.receivedDate,
  });
}

// ===== Widgets احترافية =====

class _HeaderKpis extends StatelessWidget {
  final String sumInv;
  final String sumPaid;
  final String sumRemain;
  const _HeaderKpis({
    required this.sumInv,
    required this.sumPaid,
    required this.sumRemain,
  });

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        children: [
          _KpiTile(
            icon: Icons.receipt_long,
            title: 'إجمالي الفواتير',
            value: sumInv,
          ),
          _KpiTile(
            icon: Icons.payments_rounded,
            title: 'المدفوع',
            value: sumPaid,
          ),
          _KpiTile(
            icon: Icons.account_balance_wallet,
            title: 'المتبقي',
            value: sumRemain,
            emphasize: true,
          ),
          if (isDesktop) const SizedBox(width: 1),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final bool emphasize;
  const _KpiTile({
    required this.icon,
    required this.title,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: emphasize ? Colors.white : Colors.white.withOpacity(.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: emphasize ? AppColors.primary.withOpacity(.25) : Colors.white,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.black54, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(value,
                  style: TextStyle(
                    color: emphasize ? AppColors.primary : Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      onChanged: (v) => onChanged(v ?? 'الكل'),
      items: const [
        DropdownMenuItem(value: 'الكل', child: Text('الكل')),
        DropdownMenuItem(value: 'مسدد', child: Text('مسدد')),
        DropdownMenuItem(value: 'مسدد جزئي', child: Text('مسدد جزئي')),
        DropdownMenuItem(value: 'غير مسدد', child: Text('غير مسدد')),
      ],
    );
  }
}

class _ClientCard extends StatelessWidget {
  final _ClientRow row;
  final NumberFormat money;
  final Future<void> Function(_ClientRow) onOpen;
  const _ClientCard({
    required this.row,
    required this.money,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final statusText = row.balance <= 0.0001
        ? 'مسدد'
        : (row.paymentsTotal > 0.0001 ? 'مسدد جزئي' : 'غير مسدد');
    final statusColor = row.balance <= 0.0001
        ? Colors.green.shade100
        : (row.paymentsTotal > 0.0001
            ? Colors.orange.shade100
            : Colors.red.shade100);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(.1),
          child: Icon(
            row.type == 'شركة تأمين' ? Icons.apartment : Icons.person,
            color: AppColors.primary,
          ),
        ),
        title: Text(row.name.isEmpty ? '—' : row.name),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              backgroundColor: Colors.grey.shade200,
              label: Text('إجمالي: ${money.format(row.invoicesTotal)}'),
            ),
            Chip(
              backgroundColor: Colors.green.shade100,
              label: Text('مدفوع: ${money.format(row.paymentsTotal)}'),
            ),
            Chip(
              backgroundColor: Colors.red.shade100,
              label: Text('متبقي: ${money.format(row.balance)}'),
            ),
            Chip(
                backgroundColor: statusColor,
                label: Text('الحالة: $statusText')),
          ],
        ),
        trailing: OutlinedButton.icon(
          onPressed: () => onOpen(row),
          icon: const Icon(Icons.open_in_new),
          label: const Text('تفاصيل'),
        ),
      ),
    );
  }
}

class _DesktopTable extends StatelessWidget {
  final List<_ClientRow> rows;
  final NumberFormat money;
  final Future<void> Function(_ClientRow) onOpen;
  const _DesktopTable({
    required this.rows,
    required this.money,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          columns: const [
            DataColumn(label: Text('العميل')),
            DataColumn(label: Text('النوع')),
            DataColumn(label: Text('الفواتير')),
            DataColumn(label: Text('مدفوع')),
            DataColumn(label: Text('متبقي')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('إجراء')),
          ],
          rows: rows.map((r) {
            final statusText = r.balance <= 0.0001
                ? 'مسدد'
                : (r.paymentsTotal > 0.0001 ? 'مسدد جزئي' : 'غير مسدد');
            final statusColor = r.balance <= 0.0001
                ? Colors.green
                : (r.paymentsTotal > 0.0001 ? Colors.orange : Colors.red);

            return DataRow(cells: [
              DataCell(Text(r.name)),
              DataCell(Text(r.type)),
              DataCell(Text(money.format(r.invoicesTotal))),
              DataCell(Text(money.format(r.paymentsTotal),
                  style: const TextStyle(color: Colors.green))),
              DataCell(Text(money.format(r.balance),
                  style: const TextStyle(color: Colors.red))),
              DataCell(Row(
                children: [
                  Icon(Icons.circle, size: 10, color: statusColor),
                  const SizedBox(width: 6),
                  Text(statusText),
                ],
              )),
              DataCell(
                TextButton.icon(
                  onPressed: () => onOpen(r),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('تفاصيل'),
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 76, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
