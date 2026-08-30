import 'dart:ui' as pw;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/payments/models/payment_record.dart';
import 'package:yalla_accounts/features/payments/services/payment_database_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class PaymentHistoryScreen extends StatefulWidget {
  final String repairId;

  const PaymentHistoryScreen({super.key, required this.repairId});

  @override
  State<PaymentHistoryScreen> createState() => _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends State<PaymentHistoryScreen> {
  List<PaymentRecord> payments = [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    final data =
        await PaymentDatabaseService.getPaymentsByRepairId(widget.repairId);

    if (!mounted) return;
    setState(() => payments = data);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: pw.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سجل السداد')),
        body: Column(
          children: [
            const MaterialBanner(
              content: Text(
                'هذا السجل للعرض فقط. إضافة أو تصحيح دفعة تتم من سند القبض '
                'حتى يبقى الترحيل المحاسبي متزامنًا.',
              ),
              actions: [SizedBox.shrink()],
            ),
            Expanded(
              child: payments.isEmpty
                  ? const Center(child: Text('لا توجد دفعات مسجلة'))
                  : ListView.builder(
                      itemCount: payments.length,
                      itemBuilder: (context, index) {
                        final payment = payments[index];
                        return ListTile(
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                            '${MoneyFormatter.format(payment.amount)}',
                          ),
                          subtitle: Text(
                            '${DateFormat('yyyy-MM-dd').format(payment.date)}'
                            ' - ${payment.notes}',
                          ),
                          trailing: const Icon(Icons.lock_outline),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
