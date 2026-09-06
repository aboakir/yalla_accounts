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
        pi.paid_total,
        pi.status,
        pi.method,
        pi.date,
        pi.note
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
      final pdfRows = lines.map((r) {
        return [
          (r['item_name'] ?? r['item'] ?? '').toString(),
          _d(r['qty']).toStringAsFixed(2),
          MoneyFormatter.format(_d(r['unit_price'])),
          MoneyFormatter.format(_d(r['total'])),
        ];
      }).toList();

      final bytes = await YallaPdfService.generateFullInvoicePdf(
        invoiceNumber: _short(h['id']),
        date: _fmt(h['date']),
        supplierName: h['supplier_name'] ?? '',
        purchaseType: _typeLabel(h['purchase_type']),
        paymentMethod: h['method'],
        totalAmount: _d(h['amount_total']),
        paidAmount: _d(h['paid_total']),
        remainAmount: _d(h['amount_total']) - _d(h['paid_total']),
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
        SnackBar(content: Text('تعذر إنشاء PDF: $e')),
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
    final remain = amount - paid;

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

  // ----------------------------------------------------------------------------
  // HEADER CARD
  // ----------------------------------------------------------------------------
  Widget _headerCard(Map h, double amount, double paid, double remain) {
    final canEditDate = _d(h['paid_total']) == 0 && h['status'] != 'PAID';

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
          _row('الحالة', h['status'] ?? ''),
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
  Widget _actions(double remain) {
    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ------------------------ سند صرف ------------------------
        ElevatedButton(
          onPressed: remain <= 0
              ? null
              : () async {
                  final refresh = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentVoucherScreen(),
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
            onPressed: () async {
              final db = await DBService.database;

              await db.update(
                'purchase_invoices',
                {'date': _editingDate!.toIso8601String()},
                where: 'id = ?',
                whereArgs: [header!['id']],
              );

              setState(() {
                _editingDate = null;
              });

              _load();
            },
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
