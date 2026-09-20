import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/features/finance/services/financial_void_service.dart';
import 'package:yalla_accounts/features/finance/purchases/services/purchase_balance_sql.dart';
// ============================================================================
// 📄 PurchaseDetailsScreen — FINAL MODERN UI EDITION
// متوافق 100% مع purchase_invoices + purchase_invoice_lines
// بدون أي اعتماد على RTL — تم استخدام محاذاة عربية فقط
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:yalla_accounts/features/vouchers/screens/payment_voucher_screen.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

// ============================================================================
// SCREEN
// ============================================================================

class PurchaseDetailsScreen extends StatefulWidget {
  final String invoiceId;

  const PurchaseDetailsScreen({
    super.key,
    required this.invoiceId,
  });

  @override
  State<PurchaseDetailsScreen> createState() => _PurchaseDetailsScreenState();
}

class _PurchaseDetailsScreenState extends State<PurchaseDetailsScreen> {
  Map<String, dynamic>? header;
  List<Map<String, dynamic>> lines = [];
  bool loading = true;

  bool _voiding = false;
  Future<void> _voidInvoice() async {
    if (_voiding) return;
    var reason = '';
    final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AdaptiveAlertDialog(
              title: const Text('إلغاء فاتورة المشتريات'),
              content: TextField(
                  onChanged: (value) => reason = value,
                  decoration: const InputDecoration(
                      labelText: 'سبب الإلغاء',
                      helperText: 'يُحفظ الأصل ويُعكس أثره المالي.')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('رجوع')),
                TextButton(
                    onPressed: () {
                      if (reason.trim().isNotEmpty) {
                        Navigator.pop(dialogContext, true);
                      }
                    },
                    child: const Text('تأكيد الإلغاء'))
              ],
            ));
    if (approved != true || !mounted) return;
    setState(() => _voiding = true);
    try {
      await FinancialVoidService.voidInvoice(widget.invoiceId,
          purchase: true, reason: reason);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('تعذر الإلغاء: ${UserFacingError.message(error)}')));
      }
    } finally {
      if (mounted) setState(() => _voiding = false);
    }
  }

  DateTime? _editingDate;

  // ----------------------------------------------------------------------------
  // INIT
  // ----------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _load();
  }

  // ----------------------------------------------------------------------------
  // LOAD DATA
  // ----------------------------------------------------------------------------
  Future<void> _load() async {
    final db = await DBService.database;

    final h = await db.rawQuery("""
      SELECT 
        pi.id,
        pi.invoice_number,
        pi.supplier_id,
        s.name AS supplier_name,
        pi.purchase_type,
        pi.subtotal,
        pi.vat,
        pi.total,
        pi.amount_total,
        ${PurchaseBalanceSql.paid('pi.id')} AS paid_total,
        CASE WHEN UPPER(pi.status) IN ('VOID','CANCELLED','REVERSED') THEN 'VOID' WHEN pi.amount_total - ${PurchaseBalanceSql.paid('pi.id')} <= 0.0001 THEN 'PAID' WHEN ${PurchaseBalanceSql.paid('pi.id')} > 0 THEN 'PARTIAL' ELSE 'UNPAID' END AS status,
        pi.method,
        pi.date,
        pi.note,
        pi.gl_entry_id
      FROM purchase_invoices pi
      LEFT JOIN suppliers s ON s.id = pi.supplier_id
      WHERE pi.id = ?
      LIMIT 1
    """, [widget.invoiceId]);

    final l = await db.rawQuery("""
      SELECT
        item,
        item_name,
        qty,
        unit_price,
        price,
        total,
        note
      FROM purchase_invoice_lines
      WHERE invoice_id = ?
    """, [widget.invoiceId]);

    setState(() {
      header = h.isNotEmpty ? h.first : null;
      lines = l;
      loading = false;
    });
  }

  // ----------------------------------------------------------------------------
  // HELPERS
  // ----------------------------------------------------------------------------
  double _d(v) => (v as num?)?.toDouble() ?? 0.0;

  String _fmt(dynamic d) {
    if (d == null) return '';
    try {
      return DateFormat('yyyy-MM-dd', 'ar').format(DateTime.parse(d));
    } catch (_) {
      return d.toString().split(' ').first;
    }
  }

  String _typeLabel(String? v) {
    switch (v) {
      case 'RAW':
        return 'مواد خام';
      case 'PARTS':
        return 'قطع غيار';
      case 'TOOLS':
        return 'أدوات';
      case 'OTHER':
        return 'أخرى';
      default:
        return '';
    }
  }

  String _short(String? id) {
    if (id == null) return '';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  Future<void> _exportPdf() async {
    if (header == null) return;
    final h = header!;

    try {
      final purchaseCategory = _typeLabel(h['purchase_type']?.toString());

      final pdfRows = lines.map((r) {
        return [
          (r['item_name'] ?? r['item'] ?? '').toString(),
          _d(r['qty']).toStringAsFixed(2),
          MoneyFormatter.format(_d(r['unit_price'])),
          MoneyFormatter.format(_d(r['total'])),
          // STAGE1_RUNTIME_FIX3_PURCHASE_PDF_COLUMNS
          // generateFullInvoicePdf renders five columns, including
          // "التصنيف". The old mobile handoff supplied only four cells and
          // crashed with RangeError 0..3:4 before the iOS share sheet opened.
          purchaseCategory,
        ];
      }).toList();

      final bytes = await YallaPdfService.generateFullInvoicePdf(
        invoiceNumber: _short(h['id']),
        date: _fmt(h['date']),
        supplierName: h['supplier_name'] ?? '',
        purchaseType: h['status'] == 'VOID'
            ? 'ملغاة — ${_typeLabel(h['purchase_type'])}'
            : _typeLabel(h['purchase_type']),
        paymentMethod: h['method'],
        totalAmount: _d(h['amount_total']),
        paidAmount: _d(h['paid_total']),
        remainAmount: h['status'] == 'VOID'
            ? 0
            : _d(h['amount_total']) - _d(h['paid_total']),
        rows: pdfRows,
      );

      final fileName = 'purchase_${_short(h['id'])}.pdf';
      // STAGE1_P0_PURCHASE_PDF_IOS
      // saveAndOpen is desktop-oriented. On iOS use the native PDF share
      // sheet so the generated document is actually accessible to the user.
      if (Platform.isIOS || Platform.isAndroid) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        await YallaPdfService.saveAndOpen(
          bytes: bytes,
          fileName: fileName,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذر إنشاء PDF: ${UserFacingError.message(e)}')),
      );
    }
  }

  // ----------------------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FFF0),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          'تفاصيل فاتورة الشراء',
          style: TextStyle(fontSize: 20, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : header == null
              ? const Center(
                  child: Text(
                    'الفاتورة غير موجودة',
                    style: TextStyle(fontSize: 20),
                  ),
                )
              : _content(),
    );
  }

  // ----------------------------------------------------------------------------
  // MAIN BODY
  // ----------------------------------------------------------------------------
  Widget _content() {
    final h = header!;
    final amount = _d(h['amount_total']);
    final paid = _d(h['paid_total']);
    final remain = h['status'] == 'VOID' ? 0.0 : amount - paid;
    final isPhone = MediaQuery.sizeOf(context).width < YallaBreakpoints.desktop;

    if (isPhone) {
      return _phoneContent(h, amount, paid, remain);
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1300),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Expanded(
                child: AdaptiveRow(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                        flex: 5, child: _headerCard(h, amount, paid, remain)),
                    const SizedBox(width: 26),
                    Expanded(flex: 7, child: _linesCard()),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _actions(remain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _phoneContent(Map h, double amount, double paid, double remain) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _headerCard(h, amount, paid, remain),
          const SizedBox(height: 12),
          _phoneLinesCard(),
          const SizedBox(height: 12),
          _phoneActions(remain),
        ],
      ),
    );
  }

  Widget _phoneLinesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بنود الفاتورة',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('لا توجد بنود', textAlign: TextAlign.center),
            )
          else
            ...lines.asMap().entries.map((entry) {
              final index = entry.key;
              final row = entry.value;
              final item = (row['item_name'] ?? row['item'] ?? '').toString();
              final qty = _d(row['qty']);
              final unit = _d(row['unit_price']);
              final total = _d(row['total']);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: index == lines.length - 1
                      ? null
                      : Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.isEmpty ? 'صنف بدون اسم' : item,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text('الكمية: ${qty.toStringAsFixed(2)}'),
                        Text('الوحدة: ${MoneyFormatter.format(unit)}'),
                        Text(
                          'الإجمالي: ${MoneyFormatter.format(total)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // HEADER CARD
  // ----------------------------------------------------------------------------
  Widget _headerCard(Map h, double amount, double paid, double remain) {
    final canEditDate = h['gl_entry_id'] == null &&
        _d(h['paid_total']) == 0 &&
        h['status'] != 'PAID' &&
        h['status'] != 'VOID';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'بيانات الفاتورة',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 18),
          _row('رقم الفاتورة', _short(h['id'])),
          _row('رقم المورد', h['supplier_id']?.toString() ?? ''),
          _row('اسم المورد', h['supplier_name'] ?? ''),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('التاريخ', style: TextStyle(fontSize: 15)),
                AdaptiveRow(
                  children: [
                    Text(
                      _editingDate != null
                          ? DateFormat('yyyy-MM-dd').format(_editingDate!)
                          : _fmt(h['date']),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (canEditDate)
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(h['date']),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() {
                              _editingDate = picked;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          _row('نوع الشراء', _typeLabel(h['purchase_type'])),
          _row('طريقة الدفع', h['method'] ?? ''),
          _row(
              'الحالة',
              h['status'] == 'VOID'
                  ? 'ملغاة — عُكس الأثر المالي'
                  : h['status'] ?? ''),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFFFF1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withOpacity(.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _row('الإجمالي', MoneyFormatter.format(amount)),
                _row('المدفوع', MoneyFormatter.format(paid)),
                _row('المتبقي', MoneyFormatter.format(remain)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // LINES TABLE
  // ----------------------------------------------------------------------------
  Widget _linesCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'بنود الفاتورة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: AdaptiveDataTable(
                dataRowMinHeight: 38,
                headingRowColor: WidgetStateProperty.all(
                  AppColors.primary.withOpacity(.10),
                ),
                columns: const [
                  DataColumn(label: Text('الصنف')),
                  DataColumn(label: Text('الكمية')),
                  DataColumn(label: Text('سعر الوحدة')),
                  DataColumn(label: Text('الإجمالي')),
                ],
                rows: lines.map((r) {
                  return DataRow(
                    cells: [
                      DataCell(Text(r['item_name'] ?? r['item'] ?? '')),
                      DataCell(Text(_d(r['qty']).toStringAsFixed(2))),
                      DataCell(
                          Text(MoneyFormatter.format(_d(r['unit_price'])))),
                      DataCell(Text(MoneyFormatter.format(_d(r['total'])))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // ACTION BUTTONS
  // ----------------------------------------------------------------------------
  Widget _phoneActions(double remain) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: remain <= 0 || _voiding || header?['status'] == 'VOID'
                ? null
                : () async {
                    final refresh = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentVoucherScreen(
                            purchaseId: widget.invoiceId,
                            supplierPid: header?['supplier_id']?.toString(),
                            supplierName: header?['supplier_name']?.toString()),
                      ),
                    );
                    if (refresh == true) _load();
                  },
            icon: const Icon(Icons.payments_outlined),
            label: const Text('سند صرف'),
          ),
          if (_editingDate != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saveEditedDate,
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              icon: const Icon(Icons.save_outlined),
              label: const Text('حفظ التاريخ'),
            ),
          ],
          const SizedBox(height: 8),
          if (header?['status'] != 'VOID')
            TextButton.icon(
                onPressed: _voiding ? null : _voidInvoice,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء الفاتورة وعكس القيد')),
          OutlinedButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            label: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveEditedDate() async {
    final date = _editingDate;
    final h = header;
    if (date == null || h == null) return;
    if (h['gl_entry_id'] != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا يمكن تغيير تاريخ فاتورة مُرحّلة. ألغِ الفاتورة وأعد إصدارها لتبقى مطابقة للقيد.',
            ),
          ),
        );
      }
      return;
    }

    final db = await DBService.database;
    await db.update(
      'purchase_invoices',
      {'date': date.toIso8601String()},
      where: 'id = ?',
      whereArgs: [h['id']],
    );

    if (!mounted) return;
    setState(() => _editingDate = null);
    await _load();
  }

  Widget _actions(double remain) {
    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ------------------------ سند صرف ------------------------
        ElevatedButton(
          onPressed: remain <= 0 || _voiding || header?['status'] == 'VOID'
              ? null
              : () async {
                  final refresh = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PaymentVoucherScreen(
                          purchaseId: widget.invoiceId,
                          supplierPid: header?['supplier_id']?.toString(),
                          supplierName: header?['supplier_name']?.toString()),
                    ),
                  );

                  if (refresh == true) _load();
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: remain <= 0 ? Colors.grey : AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
          child: const Text(
            'سند صرف',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),

        const SizedBox(width: 26),
        if (_editingDate != null) ...[
          ElevatedButton(
            onPressed: _saveEditedDate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
            ),
            child: const Text(
              'حفظ التاريخ',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          const SizedBox(width: 26),
        ],

        // ------------------------ PDF ------------------------
        if (header?['status'] != 'VOID')
          TextButton(
              onPressed: _voiding ? null : _voidInvoice,
              child: const Text('إلغاء الفاتورة وعكس القيد')),
        OutlinedButton(
          onPressed: _exportPdf,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
            side: BorderSide(color: AppColors.primary, width: 1.4),
          ),
          child: const Text('PDF', style: TextStyle(fontSize: 16)),
        ),

        const SizedBox(width: 26),

        // ------------------------ إغلاق ------------------------
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          ),
          child: const Text('إغلاق', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------------------
  // SMALL HELPERS
  // ----------------------------------------------------------------------------
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(.06),
          blurRadius: 10,
          offset: const Offset(0, 3),
        )
      ],
    );
  }
}
