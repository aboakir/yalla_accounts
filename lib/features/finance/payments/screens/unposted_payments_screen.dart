// 📁 lib/features/finance/payments/screens/unposted_payments_screen.dart
//
// UnpostedPaymentsScreen — دفعات بلا قيد محاسبي (GL)
// - P0.003: غير مرحّل = لا يوجد PAYMENT GL فعلي للمستند
// - أزرار: ترحيل فردي، فتح GL إذا صار موجود، "ترحيل الكل"
// - واجهة عربية بدون فرض RTL

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/gl/screens/gl_entry_screen.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';

class UnpostedPaymentsScreen extends StatefulWidget {
  const UnpostedPaymentsScreen({super.key});

  @override
  State<UnpostedPaymentsScreen> createState() => _UnpostedPaymentsScreenState();
}

class _UnpostedPaymentsScreenState extends State<UnpostedPaymentsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  final _nf = NumberFormat('#,##0.00', 'ar');
  final _df = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows = [];
    });

    final db = await DBService.database;
    final rows = await db.rawQuery('''
      SELECT
        p.id,
        p.party_id,
        p.client_id,
        p.repair_id,
        p.invoice_id,
        p.amount,
        p.date,
        p.method,
        p.gl_entry_id
      FROM payments p
      WHERE p.isIncome = 1
        AND NOT EXISTS (
          SELECT 1
          FROM gl_entries e
          WHERE e.source = 'PAYMENT'
            AND e.source_id = p.id
        )
      ORDER BY p.date DESC, p.id DESC
    ''');

    _rows = rows
        .map((r) => {
              'id': r['id']?.toString(),
              'client_id': r['client_id'],
              'party_id': r['party_id']?.toString(),
              'repair_id': r['repair_id']?.toString(),
              'invoice_id': r['invoice_id']?.toString(),
              'amount': ((r['amount'] as num?) ?? 0).toDouble(),
              'date': r['date']?.toString(),
              'method': r['method']?.toString(),
              'gl_entry_id': r['gl_entry_id'],
            })
        .toList();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _postOne(String paymentId) async {
    setState(() => _loading = true);
    try {
      final glId = await PaymentService.postPaymentFromDbId(paymentId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم نشر قيد GL #$glId للدفعة $paymentId')),
      );
      await _load();
    } on DatabaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ قاعدة البيانات: $e')),
      );
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      setState(() => _loading = false);
    }
  }

  Future<void> _postAll() async {
    if (_rows.isEmpty) return;
    setState(() => _loading = true);
    int ok = 0, fail = 0;
    for (final r in List<Map<String, dynamic>>.from(_rows)) {
      final id = r['id'] as String?;
      if (id == null) continue;
      try {
        await PaymentService.postPaymentFromDbId(id);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تم ترحيل: $ok — فشل: $fail')));
    await _load();
  }

  Future<void> _openGlIfExists(String paymentId) async {
    final glId = await DBService.getGlEntryIdBySource('PAYMENT', paymentId);
    if (glId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد قيد GL لهذه الدفعة')),
      );
      return;
    }
    if (!mounted) return;
    await GLEntryScreen.open(context, glId);
  }

  String _fmtDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final d = DateTime.tryParse(iso);
    return d == null ? iso : _df.format(d);
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _rows.isEmpty
            ? const Center(child: Text('لا توجد دفعات غير مُرحَّلة'))
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final id = r['id'] as String?;
                  final amount = r['amount'] as double;
                  final date = _fmtDate(r['date'] as String?);
                  final method = r['method'] as String? ?? '';
                  final rid = r['repair_id'] as String? ?? '-';
                  final inv = r['invoice_id'] as String? ?? '-';

                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.payment)),
                    title: Text('المبلغ: ${_nf.format(amount)}  •  $method'),
                    subtitle:
                        Text('التاريخ: $date  •  إصلاح: $rid  •  فاتورة: $inv'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'ترحيل',
                          icon: const Icon(Icons.publish),
                          onPressed: id == null ? null : () => _postOne(id),
                        ),
                        IconButton(
                          tooltip: 'فتح القيد',
                          icon: const Icon(Icons.open_in_new),
                          onPressed:
                              id == null ? null : () => _openGlIfExists(id),
                        ),
                      ],
                    ),
                  );
                },
              );

    return Scaffold(
      appBar: AppBar(
        title: const Text('دفعات بلا GL'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          if (_rows.isNotEmpty)
            TextButton.icon(
              onPressed: _loading ? null : _postAll,
              icon: const Icon(Icons.publish, color: Colors.white),
              label: const Text('ترحيل الكل',
                  style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: body,
    );
  }
}
