// 📁 lib/features/finance/invoices/screens/invoice_view_screen.dart
// عربي كامل بلا RTL. محاذاة يمين يدويًا. إصلاح صارم لأنواع String/DateTime.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/finance/invoices/widgets/invoice_add_payment_button.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class InvoiceViewScreen extends StatefulWidget {
  final String invoiceId;
  const InvoiceViewScreen({super.key, required this.invoiceId});

  static Future<void> open(BuildContext context, String invoiceId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => InvoiceViewScreen(invoiceId: invoiceId)),
    );
  }

  @override
  State<InvoiceViewScreen> createState() => _InvoiceViewScreenState();
}

class _InvoiceViewScreenState extends State<InvoiceViewScreen> {
  Map<String, Object?>? _invoice;

  int? _glEntryId;
  List<Map<String, Object?>> _glLines = const [];
  double _sumDebit = 0.0;
  double _sumCredit = 0.0;

  List<Map<String, Object?>> _payments = const [];
  int _payLimit = 50;

  bool _loading = true;
  String? _error;

  final DateFormat _dateFmt = DateFormat('yyyy-MM-dd', 'ar');

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ===== Helpers =====
  String _partyLabel(String type, String id) {
    final pid = id.trim().isEmpty ? '—' : '#$id';
    switch (type.toUpperCase()) {
      case 'CLIENT':
        return 'عميل $pid';
      case 'SUPPLIER':
        return 'مورد $pid';
      case 'EMPLOYEE':
        return 'موظف $pid';
      case 'INSURANCE':
        return 'شركة تأمين $pid';
      default:
        return type.isEmpty ? '' : '$type $pid';
    }
  }

  Future<void> _snack(String msg, {bool error = false}) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[700] : null,
        action: SnackBarAction(
          label: 'نسخ',
          onPressed: () => Clipboard.setData(ClipboardData(text: msg)),
        ),
      ),
    );
  }

  Future<void> _recomputeInvoicePaidAndStatus() async {
    try {
      await InvoiceService.I.recomputePaidFromPayments(widget.invoiceId);
    } catch (e) {
      await _snack('فشل إعادة احتساب حالة الفاتورة: $e', error: true);
    }
  }

  String _asText(Object? v) {
    if (v == null) return '—';
    if (v is DateTime) return _dateFmt.format(v);
    return '$v';
  }

  DateTime _asDate(Object? raw) {
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.now();
  }

  double _asD(Object? v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

  // ===== Load =====
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DBService.database;

      final inv = await InvoiceService.I.getById(widget.invoiceId);

      // P0.003 — authoritative posting state comes from GL itself.
      // gl_entry_id/post_to_gl are compatibility caches, never the truth.
      int? glId;
      try {
        final row = await db.rawQuery(
          '''
          SELECT id
          FROM gl_entries
          WHERE source = ? AND source_id = ?
          ORDER BY id DESC
          LIMIT 1
          ''',
          ['INVOICE', widget.invoiceId],
        );
        if (row.isNotEmpty) {
          final v = row.first['id'];
          glId = v is int ? v : int.tryParse('$v');
        }
      } catch (_) {}

      List<Map<String, Object?>> lines = const [];
      double sD = 0, sC = 0;
      if (glId != null) {
        try {
          lines = await db.rawQuery('''
            SELECT
              l.id,
              l.entry_id,
              l.account_id,
              l.debit,
              l.credit,
              l.party_type,
              l.party_id,
              a.code AS account_code,
              a.name AS account_name
            FROM gl_lines l
            JOIN accounts a ON a.id = l.account_id
            WHERE l.entry_id = ?
            ORDER BY l.id ASC
          ''', [glId]);

          final sums = await db.rawQuery(
            'SELECT IFNULL(SUM(debit),0) sD, IFNULL(SUM(credit),0) sC FROM gl_lines WHERE entry_id=?',
            [glId],
          );
          if (sums.isNotEmpty) {
            final m = sums.first;
            sD = _asD(m['sD']);
            sC = _asD(m['sC']);
          }
        } catch (_) {}
      }

      List<Map<String, Object?>> pays = const [];
      try {
        pays = await db.rawQuery('''
          SELECT id, date, amount, method, status, gl_entry_id
          FROM payments
          WHERE invoice_id = ?
          ORDER BY date DESC, id DESC
          LIMIT ?
        ''', [widget.invoiceId, _payLimit]);
      } catch (_) {}

      setState(() {
        _invoice = inv;
        _glEntryId = glId;
        _glLines = lines;
        _sumDebit = double.parse(sD.toStringAsFixed(2));
        _sumCredit = double.parse(sC.toStringAsFixed(2));
        _payments = pays;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ===== Actions =====
  Future<void> _postInvoiceGLIfMissing() async {
    if (_glEntryId != null) {
      await _snack('قيد GL موجود بالفعل (#$_glEntryId)');
      return;
    }

    if (_invoice == null) return;

    final inv = _invoice!;
    final String invoiceIdStr = (inv['id'] ?? '').toString();
    final String repairIdStr = (inv['repair_id'] ?? '').toString();
    final int clientId = (() {
      final v = inv['client_id'];
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    })();

    final double total = _asD(inv['total']);
    final double vat = _asD(inv['vat']);

    try {
      final newId = await DBService.postInvoiceGL(
        invoiceId: invoiceIdStr,
        date: DateTime.now(),
        clientId: clientId,
        total: total,
        vatAmount: vat,
        repairId: repairIdStr.isEmpty ? null : repairIdStr,
      );

      await _snack('تم ترحيل قيد الفاتورة GL (#$newId)');
      await _load();
    } catch (e) {
      await _snack('فشل ترحيل GL: $e', error: true);
    }
  }

  Future<void> _reverseInvoiceGL() async {
    if (_glEntryId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('عكس القيد'),
        content: Text('عكس قيد الفاتورة #$_glEntryId ؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('عكس')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await DBService.reverseEntryGL(
        _glEntryId!,
        note: 'Reverse from InvoiceViewScreen',
      );

      await _recomputeInvoicePaidAndStatus();
      await _snack('تم عكس قيد الفاتورة');
      await _load();
    } catch (e) {
      await _snack('فشل العكس: $e', error: true);
    }
  }

  Future<void> _reversePaymentGL(int glEntryId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('عكس القيد'),
        content: Text('عكس قيد الدفعة #$glEntryId ؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('عكس')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await DBService.reverseEntryGL(glEntryId,
          note: 'Reverse payment from InvoiceViewScreen');
      await _recomputeInvoicePaidAndStatus();
      await _snack('تم عكس قيد الدفعة');
      await _load();
    } catch (e) {
      await _snack('فشل العكس: $e', error: true);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
            title: const Align(
                alignment: Alignment.centerRight, child: Text('فاتورة'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('تعذر التحميل:\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }
    if (_invoice == null) {
      return const Scaffold(body: Center(child: Text('الفاتورة غير موجودة')));
    }

    final inv = _invoice!;

    // ثبّت الأنواع إلى String غير nullable قبل التمرير لأي معاملات تتطلب String
    final String invoiceIdStr = (inv['id'] ?? '').toString();
    final String repairIdStr = (inv['repair_id'] ?? '').toString();
    final String statusStr = (inv['status'] ?? '').toString();
    final String methodStr = (inv['method'] ?? '').toString();
    final String noteStr = (inv['note'] ?? '').toString();

    final invDate = _asDate(inv['date']);
    final dateStr = _dateFmt.format(invDate);

    final subtotal = _asD(inv['subtotal']);
    final vat = _asD(inv['vat']);
    final total = _asD(inv['total']);
    final paid = _asD(inv['paid']);

    final clientId = inv['client_id'];
    final balanced = (_sumDebit - _sumCredit).abs() < 0.005;
    final hasPaymentsNoGL = (_glEntryId == null) && _payments.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Align(
            alignment: Alignment.centerRight,
            child: Text('فاتورة $invoiceIdStr')),
        actions: [
          IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== بطاقة الفاتورة =====
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.bodyMedium!,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _row(
                        label: 'ملف الإصلاح',
                        value: repairIdStr.isEmpty ? '—' : repairIdStr),
                    const SizedBox(height: 4),
                    _row(label: 'التاريخ', value: dateStr),
                    _row(
                        label: 'الصافي قبل الضريبة',
                        value: MoneyFormatter.format(subtotal)),
                    _row(
                        label: 'ضريبة القيمة المضافة',
                        value: MoneyFormatter.format(vat)),
                    _row(
                        label: 'الإجمالي', value: MoneyFormatter.format(total)),
                    _row(label: 'المدفوع', value: MoneyFormatter.format(paid)),
                    _row(
                        label: 'حالة السداد',
                        value: statusStr.isEmpty ? '—' : statusStr),
                    if (methodStr.isNotEmpty)
                      _row(label: 'طريقة الدفع', value: methodStr),
                    if (noteStr.isNotEmpty)
                      _row(label: 'ملاحظة', value: noteStr),
                    if (clientId != null)
                      _row(label: 'رقم العميل', value: clientId),
                    if (_glEntryId != null)
                      _row(label: 'قيد GL', value: '#$_glEntryId'),
                    if (hasPaymentsNoGL) ...[
                      const SizedBox(height: 8),
                      AdaptiveRow(
                        children: const [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                'هناك دفعات مسجلة لكن لا يوجد قيد GL للفاتورة.',
                                style: TextStyle(color: Colors.orange)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('نسخ رقم الفاتورة'),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: invoiceIdStr));
                            _snack('تم النسخ');
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.travel_explore),
                          label: const Text('فتح دفتر GL'),
                          onPressed: () {
                            Navigator.of(context).pushNamed(
                              AppRoutes.financeGL,
                              arguments: {
                                'from': null,
                                'to': null,
                                'query': '',
                                'accountId': null,
                                'entryId': _glEntryId,
                                'source': 'INVOICE',
                                'source_id': invoiceIdStr, // ← String ثابت
                              },
                            );
                          },
                        ),
                        if (_glEntryId != null)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.account_balance),
                            label: Text('عرض قيد #$_glEntryId'),
                            onPressed: () {
                              Navigator.of(context).pushNamed(
                                AppRoutes.financeGLEntry,
                                arguments: _glEntryId,
                              );
                            },
                          )
                        else
                          OutlinedButton.icon(
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('ترحيل قيد GL'),
                            onPressed: _postInvoiceGLIfMissing,
                          ),
                        // تمرير String غير nullable حسب توقيع الويدجت
                        InvoiceAddPaymentButton(
                          invoiceId: invoiceIdStr,
                          repairId: repairIdStr, // ← String
                          clientId: clientId is int ? clientId : null,
                          onDone: _load,
                        ),
                        if (_glEntryId != null)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.undo),
                            label: const Text('عكس قيد الفاتورة'),
                            onPressed: _reverseInvoiceGL,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ===== سطور قيد الفاتورة =====
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _glEntryId == null
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: Text('لا توجد سطور لعرضها'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AdaptiveRow(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Chip(
                              label: Text(balanced ? 'متوازن' : 'غير متوازن',
                                  style: TextStyle(
                                      color: balanced
                                          ? Colors.green[900]
                                          : Colors.red[900],
                                      fontWeight: FontWeight.w700)),
                              backgroundColor:
                                  balanced ? Colors.green[50] : Colors.red[50],
                              side: BorderSide(
                                  color: balanced
                                      ? Colors.green[200]!
                                      : Colors.red[200]!),
                            ),
                            const SizedBox(width: 12),
                            const Text('قيد الفاتورة (GL)',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _glLines.isEmpty ? _emptyLines() : _glTable(context),
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                              '∑ مدين: ${MoneyFormatter.format(_sumDebit)}    ∑ دائن: ${MoneyFormatter.format(_sumCredit)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
            ),
          ),

          // ===== الدفعات =====
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('الدفعات',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _payments.isEmpty
                      ? const Align(
                          alignment: Alignment.centerRight,
                          child: Text('لا توجد دفعات بعد'))
                      : Column(
                          children: [
                            _paymentsTable(context),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () {
                                  setState(() => _payLimit += 50);
                                  _load();
                                },
                                icon: const Icon(Icons.expand_more),
                                label: const Text('تحميل المزيد'),
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===== Tables =====
  Widget _glTable(BuildContext ctx) {
    final isWide = MediaQuery.of(ctx).size.width >= 720;
    if (isWide) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AdaptiveDataTable(
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
          columns: const [
            DataColumn(label: Text('رقم السطر')),
            DataColumn(label: Text('كود الحساب')),
            DataColumn(label: Text('اسم الحساب')),
            DataColumn(label: Text('مدين')),
            DataColumn(label: Text('دائن')),
            DataColumn(label: Text('الطرف')),
          ],
          rows: _glLines.map((m) {
            final id = '${m['id']}';
            final code = '${m['account_code'] ?? ''}';
            final name = '${m['account_name'] ?? ''}';
            final debit = _asD(m['debit']);
            final credit = _asD(m['credit']);
            final partyType = (m['party_type'] ?? '').toString();
            final partyId = (m['party_id'] ?? '').toString();
            final party =
                partyType.isEmpty ? '' : _partyLabel(partyType, partyId);

            return DataRow(cells: [
              DataCell(Text(id)),
              DataCell(Text(code)),
              DataCell(Text(name)),
              DataCell(Text(MoneyFormatter.format(debit))),
              DataCell(Text(MoneyFormatter.format(credit))),
              DataCell(Text(party)),
            ]);
          }).toList(),
        ),
      );
    }

    return Column(
      children: _glLines.map((m) {
        final id = '${m['id']}';
        final code = '${m['account_code'] ?? ''}';
        final name = '${m['account_name'] ?? ''}';
        final debit = _asD(m['debit']);
        final credit = _asD(m['credit']);
        final partyType = (m['party_type'] ?? '').toString();
        final partyId = (m['party_id'] ?? '').toString();
        final party = partyType.isEmpty ? '' : _partyLabel(partyType, partyId);

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(child: Text(id)),
          title: Text('$code — $name', textAlign: TextAlign.right),
          subtitle: Text(
              'مدين: ${MoneyFormatter.format(debit)}   •   دائن: ${MoneyFormatter.format(credit)}\n$party',
              textAlign: TextAlign.right),
        );
      }).toList(),
    );
  }

  Widget _paymentsTable(BuildContext ctx) {
    final isWide = MediaQuery.of(ctx).size.width >= 720;
    if (isWide) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: AdaptiveDataTable(
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
          columns: const [
            DataColumn(label: Text('المعرف')),
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('المبلغ')),
            DataColumn(label: Text('الطريقة')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('قيد GL')),
            DataColumn(label: Text('')),
          ],
          rows: _payments.map((m) {
            final id = '${m['id']}';
            final d = _asDate(m['date']);
            final date = _dateFmt.format(d);
            final amount = _asD(m['amount']);
            final method = (m['method'] ?? '').toString();
            final status = (m['status'] ?? '').toString();
            final gl = m['gl_entry_id'];
            return DataRow(cells: [
              DataCell(Text(id)),
              DataCell(Text(date)),
              DataCell(Text(MoneyFormatter.format(amount))),
              DataCell(Text(method.isEmpty ? '—' : method)),
              DataCell(Text(status.isEmpty ? '—' : status)),
              DataCell(Text(gl == null ? '—' : '#$gl')),
              DataCell(
                gl is int
                    ? TextButton.icon(
                        icon: const Icon(Icons.undo),
                        label: const Text('عكس'),
                        onPressed: () => _reversePaymentGL(gl),
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          }).toList(),
        ),
      );
    }

    return Column(
      children: _payments.map((m) {
        final id = '${m['id']}';
        final d = _asDate(m['date']);
        final date = _dateFmt.format(d);
        final amount = _asD(m['amount']);
        final method = (m['method'] ?? '').toString();
        final status = (m['status'] ?? '').toString();
        final gl = m['gl_entry_id'];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
              '${MoneyFormatter.format(amount)} — ${method.isEmpty ? '—' : method}',
              textAlign: TextAlign.right),
          subtitle: Text(
              'ID: $id  •  $date  •  ${gl == null ? 'GL: —' : 'GL: #$gl'}\n'
              '${status.isEmpty ? '—' : status}',
              textAlign: TextAlign.right),
          trailing: gl is int
              ? IconButton(
                  icon: const Icon(Icons.undo),
                  tooltip: 'عكس',
                  onPressed: () => _reversePaymentGL(gl))
              : null,
        );
      }).toList(),
    );
  }

  Widget _row({required String label, required Object? value}) {
    return AdaptiveRow(
      children: [
        Expanded(
          child: Align(
              alignment: Alignment.centerLeft,
              child: Text(_asText(value), textAlign: TextAlign.left)),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 200,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(label,
                textAlign: TextAlign.right,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _emptyLines() =>
      const Align(alignment: Alignment.centerRight, child: Text('بدون أسطر'));
}
