// ---------------------------------------------------------------------------
// 📁 lib/features/finance/payments/screens/payment_list_screen.dart
// شاشة عرض الدفعات — نسخة نهائية متوافقة مع Payment model الحالي
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/payments/screens/add_payment_screen.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/empty_state.dart';
import 'package:yalla_accounts/shared/widgets/error_widget.dart';
import 'package:yalla_accounts/shared/widgets/loading.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PaymentListScreen extends StatefulWidget {
  final String? initialRepairId;
  final bool allowReverse;

  const PaymentListScreen({
    super.key,
    this.initialRepairId,
    this.allowReverse = false,
  });

  @override
  State<PaymentListScreen> createState() => _PaymentListScreenState();
}

class _PaymentListScreenState extends State<PaymentListScreen> {
  final _df = DateFormat('yyyy-MM-dd');
  final _nf = NumberFormat.decimalPattern();

  DateTime? _from;
  DateTime? _to;
  String? _status; // نص فقط: confirmed | pending | cancelled | null
  final _searchCtrl = TextEditingController();

  bool _loading = false;
  String? _loadError;
  List<Payment> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _from ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _from = picked);
      _load();
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _to ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _to = picked);
      _load();
    }
  }

  Future<void> _clearDates() async {
    setState(() {
      _from = null;
      _to = null;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      List<Payment> rows;

      if (_from != null ||
          _to != null ||
          (_status != null && _status!.isNotEmpty)) {
        rows = await PaymentService.filterByDateOrStatus(
          from: _from,
          to: _to,
          status: _status,
        );
      } else {
        rows = await PaymentService.getAll();
      }

      // STAGE1_P0_REPAIR_PAYMENT_SCOPE
      final scopedRepairId = widget.initialRepairId?.trim();
      if (scopedRepairId != null && scopedRepairId.isNotEmpty) {
        rows = rows.where((p) {
          return p.repairId == scopedRepairId ||
              p.relatedRepairId == scopedRepairId;
        }).toList();
      }

      // بحث نصي شامل
      final q = _searchCtrl.text.trim().toLowerCase();
      if (q.isNotEmpty) {
        rows = rows.where((p) {
          final hay = [
            p.notes ?? '',
            p.method,
            p.accountName ?? '',
            p.invoiceId ?? '',
            p.repairId ?? '',
            p.relatedRepairId ?? '',
          ].join(' ').toLowerCase();
          return hay.contains(q);
        }).toList();
      }

      setState(() => _items = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalAmount => _items.fold<double>(0, (s, p) => s + p.amount);

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
        return 'مؤكد';
      case 'pending':
        return 'قيد الانتظار';
      case 'cancelled':
        return 'ملغى';
      case 'reversed':
        return 'معكوس';
      case 'reversal':
        return 'قيد عكسي';
      default:
        return status.isEmpty ? 'غير محدد' : status;
    }
  }

  // Chip للحالة (status نصّي)
  Widget _statusChip(String status) {
    Color c;
    switch (status) {
      case 'confirmed':
        c = Colors.green;
        break;
      case 'pending':
        c = Colors.orange;
        break;
      case 'cancelled':
      case 'reversed':
        c = Colors.red;
        break;
      case 'reversal':
        c = Colors.blueGrey;
        break;
      default:
        c = Colors.grey;
    }

    return Chip(
      label: Text(
        _statusLabel(status),
        style: const TextStyle(color: Colors.white),
      ),
      backgroundColor: c,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  bool _canReverse(Payment payment) {
    return widget.allowReverse &&
        payment.isIncome &&
        payment.amount > 0 &&
        payment.status != 'reversed' &&
        payment.status != 'reversal' &&
        payment.reversalOfPaymentId == null;
  }

  Future<void> _reversePayment(Payment payment) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AdaptiveAlertDialog(
        title: const Text('عكس سند القبض'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'لن تُحذف الحركة الأصلية. سيتم إنشاء عكس محاسبي رسمي للسند.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'سبب العكس',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('اكتب سبب العكس أولًا')),
                );
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            child: const Text('عكس رسمي'),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;

    try {
      await PaymentService.reverseReceiptByPaymentId(
        payment.id,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء العكس الرسمي دون حذف الحركة الأصلية'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر عكس الدفعة: $e')),
      );
    }
  }

  Future<void> _goAdd() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddPaymentScreen()),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalTxt = _nf.format(_totalAmount);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initialRepairId == null ? 'الدفعات' : 'دفعات ملف الإصلاح',
        ),
      ),
      floatingActionButton: widget.initialRepairId == null
          ? FloatingActionButton.extended(
              onPressed: _goAdd,
              icon: const Icon(Icons.add),
              label: const Text('إضافة'),
            )
          : null,
      body: Column(
        children: [
          // -----------------------------------------------
          // فلاتر البحث
          // -----------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: TextField(
                    inputFormatters: const [YallaDigitNormalizer()],
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث في الملاحظات/الطريقة/الحساب/المعرفات…',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: (_searchCtrl.text.isEmpty)
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                _load();
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),

                // فلتر الحالة النصّي
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String?>(
                    value: _status,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('كل الحالات')),
                      DropdownMenuItem(
                          value: 'confirmed', child: Text('تم التأكيد')),
                      DropdownMenuItem(
                          value: 'pending', child: Text('قيد الانتظار')),
                      DropdownMenuItem(
                          value: 'cancelled', child: Text('أُلغي')),
                    ],
                    onChanged: (v) {
                      setState(() => _status = v);
                      _load();
                    },
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // -----------------------------------------------
          // فلاتر التاريخ
          // -----------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickFrom,
                    icon: const Icon(Icons.date_range),
                    label: Text(_from == null ? 'من' : _df.format(_from!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTo,
                    icon: const Icon(Icons.event),
                    label: Text(_to == null ? 'إلى' : _df.format(_to!)),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _clearDates,
                  child: const Text('مسح التواريخ'),
                ),
              ],
            ),
          ),

          // -----------------------------------------------
          // الإجمالي + تحديث
          // -----------------------------------------------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: AdaptiveRow(
              children: [
                Text('الإجمالي: $totalTxt'),
                const Spacer(),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // -----------------------------------------------
          // القائمة
          // -----------------------------------------------
          Expanded(
            child: _loading
                ? const LoadingWidget(message: 'جاري تحميل الدفعات...')
                : _loadError != null
                    ? ErrorDisplay(
                        message: 'تعذر تحميل الدفعات.\n$_loadError',
                        onRetry: _load,
                      )
                    : _items.isEmpty
                        ? const YallaEmptyState(
                            title: 'لا توجد دفعات',
                            message: 'ستظهر سندات الدفعات هنا بعد تسجيلها.',
                            icon: Icons.payments_outlined,
                          )
                        : ListView.separated(
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = _items[i];
                              final amt = _nf.format(p.amount);
                              final dateTxt = _df.format(p.date);

                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.payment, size: 18),
                                ),
                                title: Text('المبلغ: $amt'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('التاريخ: $dateTxt'),
                                    Text(
                                        'الطريقة: ${p.method}  •  الحساب: ${p.accountName ?? '-'}'),
                                    Text(
                                        'Repair: ${p.repairId ?? '-'}  •  Invoice: ${p.invoiceId ?? '-'}'),
                                    if ((p.notes ?? '').isNotEmpty)
                                      Text('ملاحظات: ${p.notes}'),
                                    Text('الحالة: ${_statusLabel(p.status)}'),
                                  ],
                                ),
                                trailing: _canReverse(p)
                                    ? IconButton(
                                        tooltip: 'عكس الدفعة رسميًا',
                                        onPressed: () => _reversePayment(p),
                                        icon: const Icon(
                                          Icons.undo_rounded,
                                          color: Colors.red,
                                        ),
                                      )
                                    : _statusChip(p.status),
                                isThreeLine: true,
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
