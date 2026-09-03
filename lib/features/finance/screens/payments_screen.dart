// 📁 lib/features/finance/screens/payments_screen.dart
//
// Payments Screen — قراءة مباشرة من GL مع تكامل payments عند الحاجة
// -----------------------------------------------------------------
// • المصدر الرئيسي: gl_entries + gl_lines + accounts على حسابي 1000/1010.
// • تشمل: صرف الرواتب (PAYROLL_PAYMENT)، قيود المشتريات، التحويلات… إلخ.
// • إن وُجدت دفعة أصلها من جدول payments (p.gl_entry_id=gl.id) نظهر أزرار
//   التعديل/الحذف عبر PaymentService. وإلا فالصف للقراءة فقط.
// • فلاتر التاريخ والبحث والعميل. إجمالي داخل/خارج.
// • فتح قيد GL دائمًا. فتح الإصلاح/الفاتورة عند توفر المعرف.
//
// ملاحظات:
// - الطريقة Method تُستنتج من كود الحساب: 1000→cash، 1010→bank.
// - الاتجاه: داخلة=Debit على 1000/1010، خارجة=Credit على 1000/1010.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

// PaymentService للنماذج القائمة على جدول payments فقط
import 'package:yalla_accounts/features/finance/payments/models/payment.dart'
    as fpay;
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';

// شاشة عرض قيد GL
import 'package:yalla_accounts/features/finance/payments/screens/payment_gl_entry_screen_ltr.dart';

// إصلاح
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/screens/repair_details_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _money = NumberFormat('#,##0.00', 'ar');

  bool _loading = true;
  String? _error;
  DateTimeRange? _range;
  final _searchCtrl = TextEditingController();
  bool _compact = false;
  bool _showSidebar = true;

  int? _filterClientId;
  List<Map<String, dynamic>> _clients = [];

  List<_GlCashMovement> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadClients();
    _load();
  }

  Future<Database> _db() async => DBService.database;

  Future<void> _loadClients() async {
    try {
      final db = await _db();
      final rows = await db
          .rawQuery('SELECT id, name FROM clients ORDER BY LOWER(name)');
      if (!mounted) return;
      setState(() => _clients = rows);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await _db();

      // بناء WHERE ديناميكي
      final where = <String>[];
      final args = <dynamic>[];

      // التاريخ: على gl_entries.date
      if (_range != null) {
        where.add('ge.date BETWEEN ? AND ?');
        args.add(_range!.start.toIso8601String());
        args.add(_range!.end.toIso8601String());
      }

      // فلتر العميل: إن كان الصف مرتبطًا بجدول payments
      if (_filterClientId != null) {
        where.add('p.client_id = ?');
        args.add(_filterClientId);
      }

      // البحث بالنص: على note/source/source_id واسم العميل ووسم الإصلاح
      if (_searchCtrl.text.trim().isNotEmpty) {
        final s = '%${_searchCtrl.text.trim()}%';
        where.add('('
            'ge.note LIKE ? OR ge.source LIKE ? OR ge.source_id LIKE ? '
            'OR IFNULL(c.name,"") LIKE ? '
            'OR IFNULL(r.vehicleType,"") LIKE ? '
            'OR IFNULL(r.vehicleModel,"") LIKE ? '
            'OR IFNULL(r.vehicleNumber,"") LIKE ? '
            'OR IFNULL(a.name,"") LIKE ?'
            ')');
        args.addAll([s, s, s, s, s, s, s, s]);
      }

      // نجلب فقط أسطر GL على 1000/1010
      final baseSql = StringBuffer('''
        SELECT
          ge.id              AS gl_id,
          ge.date            AS gl_date,
          ge.source          AS gl_source,
          ge.source_id       AS gl_source_id,
          ge.note            AS gl_note,

          gl.debit           AS line_debit,
          gl.credit          AS line_credit,
          gl.invoice_id      AS invoice_id,
          gl.repair_id       AS repair_id,
          gl.party_type      AS party_type,
          gl.party_id        AS party_id,

          a.id               AS account_id,
          a.code             AS account_code,
          a.name             AS account_name,

          -- ربط اختياري بجدول payments إن وُجد
          p.id               AS payment_id,
          p.client_id        AS client_id,
          c.name             AS client_name,

          -- لعرض وسم الإصلاح
          (r.vehicleType || ' - ' || r.vehicleModel || ' - ' || r.vehicleNumber) AS repair_label
        FROM gl_entries ge
        JOIN gl_lines gl    ON gl.entry_id = ge.id
        JOIN accounts a     ON a.id = gl.account_id
        LEFT JOIN payments p ON p.gl_entry_id = ge.id
        LEFT JOIN clients  c ON c.id = p.client_id
        LEFT JOIN repairs  r ON r.id = gl.repair_id
        WHERE a.code IN ('1000','1010')
      ''');

      if (where.isNotEmpty) {
        baseSql.write(' AND ${where.join(' AND ')}');
      }
      baseSql.write(' ORDER BY ge.date DESC, ge.id DESC');

      final maps = await db.rawQuery(baseSql.toString(), args);
      _rows = maps.map(_GlCashMovement.fromMap).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final dr = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
    );
    if (dr != null) {
      setState(() {
        _range = DateTimeRange(
          start: dr.start,
          end: dr.end.add(const Duration(hours: 23, minutes: 59, seconds: 59)),
        );
      });
      _load();
    }
  }

  // ===== فتحات =====

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _openGLEntry(int glId) => PaymentGLEntryScreenLtr.push(context, glId);

  Future<void> _openRepairById(String repairId) async {
    try {
      final db = await _db();
      final rows = await db.query('repairs',
          where: 'id=?', whereArgs: [repairId], limit: 1);
      if (rows.isEmpty) return _toast('ملف الإصلاح غير موجود');
      final r = Repair.fromMap(rows.first);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RepairDetailsScreen(repair: r),
        settings: const RouteSettings(name: AppRoutes.repairDetail),
      ));
    } catch (e) {
      _toast('تعذر فتح الإصلاح: $e');
    }
  }

  void _openInvoiceById(String invoiceId) {
    Navigator.of(context)
        .pushNamed(AppRoutes.invoiceView, arguments: invoiceId);
  }

  // ===== إنشاء/تعديل دفعات قائمة على جدول payments فقط =====

  Future<void> _openAddEdit([_GlCashMovement? row]) async {
    // يسمح فقط عندما المصدر payments موجود ومعه payment_id
    if (row != null && row.paymentId == null) {
      _toast('هذه الحركة من GL مباشرة ولا يمكن تعديلها هنا.');
      return;
    }

    final res = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddEditPaymentDialog(
        payment: row?.toPaymentModel(),
        onCreated: () => _load(),
        onUpdated: () => _load(),
        presetClientId: _filterClientId,
        clientsCache: _clients,
      ),
    );
    if (res == true) _load();
  }

  Future<void> _deletePaymentFromPaymentsTable(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تأكيد'),
        content: const Text(
            'سيتم حذف الدفعة من جدول payments وعكس القيد المرتبط وتحديث الفاتورة.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;

    final db = await _db();
    await db.transaction((txn) async {
      final row =
          await txn.query('payments', where: 'id=?', whereArgs: [id], limit: 1);
      if (row.isEmpty) return;

      final m = row.first;
      final glId = (m['gl_entry_id'] is int)
          ? (m['gl_entry_id'] as int)
          : int.tryParse(m['gl_entry_id']?.toString() ?? '');
      final invoiceId = m['invoice_id']?.toString();
      final repairId = m['repair_id']?.toString();

      if (glId != null) {
        try {
          await DBService.reverseEntryGL(glId,
              note: 'Reverse on payment delete');
        } catch (_) {}
      }

      await txn.delete('payments', where: 'id=?', whereArgs: [id]);

      String? invId = invoiceId;
      if ((invId == null || invId.isEmpty) && (repairId?.isNotEmpty == true)) {
        final q = await txn.query('invoices',
            columns: ['id', 'total'],
            where: 'repair_id=?',
            whereArgs: [repairId],
            limit: 1);
        if (q.isNotEmpty) invId = q.first['id']?.toString();
      }

      if (invId != null && invId.isNotEmpty) {
        final paidRow = await txn.rawQuery(
          'SELECT IFNULL(SUM(amount),0) AS s FROM payments WHERE invoice_id = ?',
          [invId],
        );
        final paid = (paidRow.first['s'] is num)
            ? (paidRow.first['s'] as num).toDouble()
            : double.tryParse(paidRow.first['s'].toString()) ?? 0.0;

        final totRow = await txn.query('invoices',
            columns: ['total'], where: 'id=?', whereArgs: [invId], limit: 1);
        final totalRaw = totRow.isNotEmpty ? totRow.first['total'] : 0;
        final total = (totalRaw is num)
            ? totalRaw.toDouble()
            : double.tryParse(totalRaw.toString()) ?? 0.0;

        String status;
        if (paid <= 0.0000001) {
          status = 'unpaid';
        } else if ((total - paid).abs() <= 0.0000001 || paid > total) {
          status = 'paid';
        } else {
          status = 'partial';
        }

        await txn.update(
          'invoices',
          {
            'paid': paid,
            'status': status,
            'updated_at': DateTime.now().toIso8601String()
          },
          where: 'id=?',
          whereArgs: [invId],
        );
      }
    });

    _load();
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    const route = AppRoutes.payments;

    return Scaffold(
      drawer: isDesktop || _showSidebar
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: route)),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('سجل الحركات النقدية/البنكية (GL)'),
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
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
              onPressed: () => setState(() => _compact = !_compact),
              icon:
                  Icon(_compact ? Icons.density_small : Icons.density_medium)),
          IconButton(
              onPressed: () => _openAddEdit(), icon: const Icon(Icons.add)),
        ],
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop && _showSidebar)
            const SizedBox(
                width: 260, child: YallaSidebar(currentRoute: route)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('خطأ: $_error'))
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _filters(),
        _stats(),
        Expanded(
          child: _rows.isEmpty
              ? const Center(
                  child: Text('لا توجد حركات على الصندوق/البنك ضمن الفلاتر'))
              : Responsive.isDesktop(context)
                  ? _table()
                  : _cards(),
        ),
      ],
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'بحث…',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range),
            label: Text(_range == null
                ? 'كل التواريخ'
                : '${_df.format(_range!.start)} → ${_df.format(_range!.end)}'),
          ),
          if (_range != null)
            IconButton(
              tooltip: 'مسح النطاق',
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() => _range = null);
                _load();
              },
            ),
          DropdownButton<int?>(
            value: _filterClientId,
            hint: const Text('كل العملاء'),
            items: [
              const DropdownMenuItem<int?>(
                  value: null, child: Text('كل العملاء')),
              ..._clients.map(
                (c) => DropdownMenuItem<int?>(
                  value: (c['id'] as num).toInt(),
                  child: Text(c['name'].toString()),
                ),
              ),
            ],
            onChanged: (v) {
              setState(() => _filterClientId = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    double totalIn = 0, totalOut = 0;
    for (final r in _rows) {
      if (r.direction == _Direction.inflow) {
        totalIn += r.amount;
      } else {
        totalOut += r.amount;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('داخل: ${_money.format(totalIn)}')),
            Chip(label: Text('خارج: ${_money.format(totalOut)}')),
            Chip(
              label: Text('صافي: ${_money.format(totalIn - totalOut)}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columnSpacing: _compact ? 10 : 24,
        columns: const [
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('المبلغ')),
          DataColumn(label: Text('اتجاه')),
          DataColumn(label: Text('الطريقة')),
          DataColumn(label: Text('الحساب')),
          DataColumn(label: Text('المصدر')),
          DataColumn(label: Text('الطرف/العميل')),
          DataColumn(label: Text('الملف')),
          DataColumn(label: Text('ملاحظة')),
          DataColumn(label: Text('')),
        ],
        rows: _rows.map((r) {
          return DataRow(cells: [
            DataCell(Text(_df.format(r.date))),
            DataCell(Text(_money.format(r.amount))),
            DataCell(Text(r.direction == _Direction.inflow ? 'داخل' : 'خارج')),
            DataCell(Text(r.methodLabel)),
            DataCell(Text(r.accountName)),
            DataCell(Text(r.sourceLabel)),
            DataCell(Text(r.partyLabel ?? '-')),
            DataCell(Text(r.repairLabel ?? '-')),
            DataCell(Text(r.note ?? '-', maxLines: 1)),
            DataCell(AdaptiveRow(
              children: [
                IconButton(
                  tooltip: 'فتح قيد GL',
                  icon: const Icon(Icons.account_balance),
                  onPressed: () => _openGLEntry(r.glId),
                ),
                if (r.repairId != null && r.repairId!.isNotEmpty)
                  IconButton(
                    tooltip: 'فتح الإصلاح',
                    icon: const Icon(Icons.build_circle),
                    onPressed: () => _openRepairById(r.repairId!),
                  ),
                if (r.invoiceId != null && r.invoiceId!.isNotEmpty)
                  IconButton(
                    tooltip: 'فتح الفاتورة',
                    icon: const Icon(Icons.receipt_long),
                    onPressed: () => _openInvoiceById(r.invoiceId!),
                  ),
                // تعديل/حذف فقط إذا أتت من جدول payments
                if (r.paymentId != null) ...[
                  IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openAddEdit(r)),
                  IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete),
                      onPressed: () =>
                          _deletePaymentFromPaymentsTable(r.paymentId!)),
                ],
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _cards() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      itemBuilder: (_, i) {
        final r = _rows[i];
        final dirTxt = r.direction == _Direction.inflow ? 'داخل' : 'خارج';
        return Card(
          child: ListTile(
            title:
                Text('${_money.format(r.amount)} • $dirTxt • ${r.methodLabel}'),
            subtitle: Text(
              '${_df.format(r.date)}\n${r.sourceLabel}\n${r.partyLabel ?? ''}\n${r.repairLabel ?? ''}\n${r.note ?? ''}',
            ),
            isThreeLine: true,
            trailing: AdaptiveRow(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    tooltip: 'قيد GL',
                    icon: const Icon(Icons.account_balance),
                    onPressed: () => _openGLEntry(r.glId)),
                if (r.repairId != null && r.repairId!.isNotEmpty)
                  IconButton(
                      tooltip: 'الإصلاح',
                      icon: const Icon(Icons.build_circle),
                      onPressed: () => _openRepairById(r.repairId!)),
                if (r.invoiceId != null && r.invoiceId!.isNotEmpty)
                  IconButton(
                      tooltip: 'الفاتورة',
                      icon: const Icon(Icons.receipt_long),
                      onPressed: () => _openInvoiceById(r.invoiceId!)),
                if (r.paymentId != null) ...[
                  IconButton(
                      tooltip: 'تعديل',
                      icon: const Icon(Icons.edit),
                      onPressed: () => _openAddEdit(r)),
                  IconButton(
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete),
                      onPressed: () =>
                          _deletePaymentFromPaymentsTable(r.paymentId!)),
                ],
              ],
            ),
            onTap: () => _openGLEntry(r.glId),
            onLongPress: () => r.paymentId != null ? _openAddEdit(r) : null,
          ),
        );
      },
    );
  }
}

// ======================= Models / Mapping =======================

enum _Direction { inflow, outflow }

class _GlCashMovement {
  final int glId;
  final DateTime date;
  final String source;
  final String sourceId;
  final String? note;

  final double debit;
  final double credit;

  final String accountCode;
  final String accountName;

  final String? invoiceId;
  final String? repairId;
  final String? repairLabel;

  final String? partyType; // EMPLOYEE | CLIENT | SUPPLIER | ...
  final String? partyId;

  final String? paymentId; // إذا كانت من جدول payments
  final int? clientId;
  final String? clientName;

  _GlCashMovement({
    required this.glId,
    required this.date,
    required this.source,
    required this.sourceId,
    required this.note,
    required this.debit,
    required this.credit,
    required this.accountCode,
    required this.accountName,
    required this.invoiceId,
    required this.repairId,
    required this.repairLabel,
    required this.partyType,
    required this.partyId,
    required this.paymentId,
    required this.clientId,
    required this.clientName,
  });

  double get amount => debit > 0 ? debit : credit;
  _Direction get direction =>
      debit > 0 ? _Direction.inflow : _Direction.outflow;

  String get methodLabel => accountCode == '1010' ? 'بنك' : 'نقدي';

  String get sourceLabel {
    switch (source) {
      case 'PAYROLL_PAYMENT':
        return 'صرف رواتب';
      case 'PURCHASE_PAY':
        return 'سداد مورد';
      case 'INVOICE': // في حال كان هناك قيد يؤثر على النقدية عبر الفاتورة
        return 'فاتورة';
      default:
        return source; // يظهر رمز المصدر كما هو
    }
  }

  String? get partyLabel {
    if (clientName != null && clientName!.trim().isNotEmpty) return clientName;
    if (partyType == 'EMPLOYEE') return 'موظف: ${partyId ?? ''}';
    if (partyType == 'SUPPLIER') return 'مورد: ${partyId ?? ''}';
    if (partyType == 'CLIENT') return 'عميل: ${partyId ?? ''}';
    return null;
  }

  // تحويل جزئي ليستفيد منه Dialog الإضافة/التعديل عند وجود payment
  fpay.Payment? toPaymentModel() {
    if (paymentId == null) return null;

    return fpay.Payment(
      id: paymentId!,
      isIncome: false, // ← مهم جداً (مصروف)
      clientId: clientId,
      repairId: repairId ?? '',
      relatedRepairId: repairId ?? '',
      invoiceId: invoiceId ?? '',
      amount: amount,
      date: date,
      method: methodLabel,
      accountName: accountName,
      status: 'posted',
      notes: note ?? '',
      attachments: '',
      glEntryId: null,
    );
  }

  factory _GlCashMovement.fromMap(Map<String, dynamic> m) {
    double d(Object? v) => v == null
        ? 0
        : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);

    return _GlCashMovement(
      glId: (m['gl_id'] as num).toInt(),
      date: DateTime.tryParse(m['gl_date']?.toString() ?? '') ??
          DateTime(1970, 1, 1),
      source: m['gl_source']?.toString() ?? '',
      sourceId: m['gl_source_id']?.toString() ?? '',
      note: m['gl_note']?.toString(),
      debit: d(m['line_debit']),
      credit: d(m['line_credit']),
      accountCode: m['account_code']?.toString() ?? '',
      accountName: m['account_name']?.toString() ?? '',
      invoiceId: m['invoice_id']?.toString(),
      repairId: m['repair_id']?.toString(),
      repairLabel: m['repair_label']?.toString(),
      partyType: m['party_type']?.toString(),
      partyId: m['party_id']?.toString(),
      paymentId: m['payment_id']?.toString(),
      clientId: (m['client_id'] as num?)?.toInt(),
      clientName: m['client_name']?.toString(),
    );
  }
}

// ======================= Dialog للإضافة/التعديل (كما كان) =======================

class AddEditPaymentDialog extends StatefulWidget {
  final fpay.Payment? payment;
  final VoidCallback? onCreated;
  final VoidCallback? onUpdated;
  final int? presetClientId;
  final List<Map<String, dynamic>>? clientsCache;
  const AddEditPaymentDialog({
    this.payment,
    this.onCreated,
    this.onUpdated,
    this.presetClientId,
    this.clientsCache,
    super.key,
  });

  @override
  State<AddEditPaymentDialog> createState() => _AddEditPaymentDialogState();
}

class _AddEditPaymentDialogState extends State<AddEditPaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _df = DateFormat('yyyy-MM-dd');

  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();
  int? _clientId;
  String? _repairId;
  final _methodCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _repairs = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.payment;
    if (p != null) {
      _date = p.date;
      _amountCtrl.text = p.amount.toStringAsFixed(2);

      // ✅ إصلاح: p.repairId قد يكون null، لا تستدعِ .isEmpty مباشرة
      final repId = p.repairId;
      _repairId = (repId == null || repId.isEmpty) ? null : repId;

      // ✅ إصلاح: p.method غير قابل للإبطال في موديلك، لا حاجة لـ ?? ''
      _methodCtrl.text = p.method;

      _clientId = p.clientId;
      _accountCtrl.text = p.accountName ?? '';
      _notesCtrl.text = p.notes ?? '';
    } else {
      _clientId = widget.presetClientId;
    }
    _loadClients();
  }

  Future<Database> _db() => DBService.database;

  Future<void> _loadClients() async {
    if (widget.clientsCache != null && widget.clientsCache!.isNotEmpty) {
      setState(() => _clients = widget.clientsCache!);
    } else {
      final db = await _db();
      final rows =
          await db.rawQuery('SELECT id,name FROM clients ORDER BY name');
      setState(() => _clients = rows);
    }
    if (_clientId != null) _loadRepairs(_clientId!);
  }

  Future<void> _loadRepairs(int cid) async {
    final db = await _db();
    final rows = await db.rawQuery(
      'SELECT id, vehicleType || " - " || vehicleModel || " - " || vehicleNumber AS label '
      'FROM repairs WHERE client_id = ? ORDER BY receivedDate DESC',
      [cid],
    );
    setState(() => _repairs = rows);
  }

  String _clientNameById(int id) {
    final hit = _clients.firstWhere(
      (c) => (c['id'] as num).toInt() == id,
      orElse: () => const {'name': ''},
    );
    return hit['name']?.toString() ?? '';
  }

  String _newPaymentId() {
    final rand = Random().nextInt(1 << 32);
    return 'pay_${DateTime.now().microsecondsSinceEpoch}_$rand';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      final method =
          _methodCtrl.text.trim().isEmpty ? 'نقداً' : _methodCtrl.text.trim();
      final accountName = _accountCtrl.text.trim();
      final notes = _notesCtrl.text.trim();

      final editing = widget.payment != null;
      final oldId = widget.payment?.id;

      if (editing && (oldId == null || oldId.isEmpty)) {
        throw StateError('لا يمكن تعديل دفعة بدون معرف.');
      }

      if (_repairId == null) {
        throw StateError('يجب اختيار ملف إصلاح لربط الدفعة به.');
      }
      if (_clientId == null) {
        throw StateError('اختر العميل.');
      }

      final customerName = _clientNameById(_clientId!);

      // في وضع التعديل: احذف القديمة واعكس GL ثم أنشئ جديدة
      if (editing) {
        final db = await _db();
        await db.transaction((txn) async {
          final row = await txn.query('payments',
              where: 'id=?', whereArgs: [oldId], limit: 1);
          if (row.isNotEmpty) {
            final glId = (row.first['gl_entry_id'] is int)
                ? (row.first['gl_entry_id'] as int)
                : int.tryParse(row.first['gl_entry_id']?.toString() ?? '');
            if (glId != null) {
              try {
                await DBService.reverseEntryGL(glId,
                    note: 'Reverse on payment edit');
              } catch (_) {}
            }
          }
          await txn.delete('payments', where: 'id=?', whereArgs: [oldId]);
        });
      }

      final payment = fpay.Payment(
        id: _newPaymentId(),
        isIncome: false, // ← ضروري جداً (هذا ليس قبض بل صرف/مصروف)
        clientId: _clientId,
        repairId: _repairId!,
        relatedRepairId: _repairId!,
        invoiceId: '', // اتركه فارغاً إذا لم تكن مربوطة بفاتورة
        amount: amount,
        date: _date,
        method: method,
        accountName: accountName.isEmpty ? null : accountName,
        status: 'posted', // String وليس Enum
        notes: notes.isEmpty ? null : notes,
        attachments: null, // أفضل من '' إذا ما في مرفقات
        glEntryId: null,
      );

      await PaymentService.insertAndPostReceipt(
        payment: payment,
        customerName: customerName,
        method: method,
        updateInvoice: true,
        descriptionOverride: null,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      (editing ? widget.onUpdated : widget.onCreated)?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _methodCtrl.dispose();
    _accountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.payment != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AdaptiveRow(children: [
                Expanded(
                  child: Text(isEdit ? 'تعديل دفعة' : 'إضافة دفعة',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 8),
              TextFormField(
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'أدخل المبلغ';
                  final x = double.tryParse(v);
                  if (x == null || x <= 0) return 'مبلغ غير صالح';
                  return null;
                },
              ),
              const SizedBox(height: 6),
              AdaptiveRow(children: [
                TextButton(
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 365 * 3)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                  child: Text(_df.format(_date)),
                ),
              ]),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                value: _clientId,
                hint: const Text('اختر العميل'),
                items: _clients
                    .map((c) => DropdownMenuItem(
                          value: (c['id'] as num).toInt(),
                          child: Text(c['name'].toString()),
                        ))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _clientId = v;
                    _repairId = null;
                    _repairs.clear();
                  });
                  if (v != null) _loadRepairs(v);
                },
                validator: (v) => v == null ? 'اختر العميل' : null,
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _repairId,
                hint: const Text('اختر ملف إصلاح'),
                items: _repairs
                    .map((r) => DropdownMenuItem(
                          value: r['id'].toString(),
                          child: Text(r['label'].toString()),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _repairId = v),
                validator: (v) {
                  if (_repairId == null || _repairId!.isEmpty) {
                    return 'يجب اختيار ملف إصلاح لربط الدفعة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 6),
              TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _methodCtrl,
                  decoration: const InputDecoration(
                      labelText: 'طريقة الدفع (نقداً / بنك / شيك …)')),
              const SizedBox(height: 6),
              TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _accountCtrl,
                  decoration: const InputDecoration(
                      labelText: 'اسم الحساب (صندوق / بنك …)')),
              const SizedBox(height: 6),
              TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'ملاحظات')),
              const SizedBox(height: 12),
              AdaptiveRow(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء')),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('حفظ'),
                ),
              ])
            ]),
          ),
        ),
      ),
    );
  }
}
