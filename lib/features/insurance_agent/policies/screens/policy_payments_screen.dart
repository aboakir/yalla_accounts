// 📁 lib/features/insurance_agent/policies/screens/policy_payments_screen.dart
//
// PolicyPaymentsScreen — دفعات بوليصة التأمين (DB REAL)
// ✅ عرض الدفعات + إجمالي المدفوع + المتبقي (إذا توفر سعر البيع)
// ✅ إضافة دفعة (Dialog) + حذف دفعة
// ✅ بدون RTL / Directionality / TextDirection (محاذاة يمين فقط)
// ✅ يعمل على Desktop/Mobile
//
// ملاحظة مهمة جداً:
// هذا الملف يفترض وجود جدول باسم: insurance_policy_payments
// بالأعمدة المقترحة (مرنة):
// - id (INTEGER PRIMARY KEY AUTOINCREMENT)   أو uuid
// - policy_id / policyId / policy_uuid      (أي واحد منهم)
// - amount (REAL)
// - pay_date (TEXT)  أو payment_date / date
// - method (TEXT)    (CASH / CHEQUE / INSTALLMENT / TRANSFER ...)
// - notes (TEXT)
// - created_at (TEXT)
//
// إذا كان اسم الجدول/الأعمدة مختلف عندك، عدّل فقط الـ getters داخل الملف (مُعلّمة).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';

class PolicyPaymentsScreen extends StatefulWidget {
  final dynamic policyId; // id / uuid / policy_id
  final Map<String, dynamic>? row; // بيانات البوليصة (اختياري)

  const PolicyPaymentsScreen({
    super.key,
    required this.policyId,
    this.row,
  });

  @override
  State<PolicyPaymentsScreen> createState() => _PolicyPaymentsScreenState();
}

class _PolicyPaymentsScreenState extends State<PolicyPaymentsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _payments = [];

  // ---------------------------------------------------------------------------
  // Helpers: policy table values (optional)
  double get _policySellPrice {
    final r = widget.row;
    if (r == null) return 0.0;

    final v = r['sell_price'] ??
        r['policy_sell_price'] ??
        r['sale_price'] ??
        r['price_sell'];
    return _toDouble(v);
  }

  String get _plate {
    final r = widget.row;
    if (r == null) return '';
    return (r['vehicle_plate'] ?? r['plate'] ?? '').toString();
  }

  String get _company {
    final r = widget.row;
    if (r == null) return '';
    return (r['company_name'] ?? r['company'] ?? '').toString();
  }

  // ---------------------------------------------------------------------------
  // Column mapping for payments table (عدّل هنا فقط إذا عندك أسماء مختلفة)
  dynamic _paymentId(Map<String, dynamic> p) =>
      p['id'] ?? p['uuid'] ?? p['payment_id'];

  double _paymentAmount(Map<String, dynamic> p) =>
      _toDouble(p['amount'] ?? p['pay_amount'] ?? p['paid_amount']);

  String _paymentMethod(Map<String, dynamic> p) =>
      (p['method'] ?? p['pay_method'] ?? p['payment_method'] ?? '').toString();

  String _paymentNotes(Map<String, dynamic> p) =>
      (p['notes'] ?? p['note'] ?? '').toString();

  DateTime? _paymentDate(Map<String, dynamic> p) {
    final v = p['pay_date'] ?? p['payment_date'] ?? p['date'];
    return _parseDate(v);
  }

  String _policyFkColumnGuess(Map<String, dynamic> sampleRow) {
    // شوف شو موجود بالصف، واختر الأنسب كـ FK
    if (sampleRow.containsKey('policy_id')) return 'policy_id';
    if (sampleRow.containsKey('policyId')) return 'policyId';
    if (sampleRow.containsKey('policy_uuid')) return 'policy_uuid';
    if (sampleRow.containsKey('policyUuid')) return 'policyUuid';
    // الافتراضي:
    return 'policy_id';
  }

  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  // ---------------------------------------------------------------------------
  Future<void> _loadPayments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await DatabaseMigration.database;

      // تأكيد وجود الجدول
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['insurance_policy_payments'],
      );

      if (tables.isEmpty) {
        setState(() {
          _payments = [];
          _loading = false;
          _error =
              'جدول insurance_policy_payments غير موجود. أنشئه في الـ migration أولاً.';
        });
        return;
      }

      // نجيب عينة صف واحد عشان نخمّن اسم عمود FK
      final sample = await db.query(
        'insurance_policy_payments',
        limit: 1,
      );

      final fkCol =
          sample.isEmpty ? 'policy_id' : _policyFkColumnGuess(sample.first);

      final rows = await db.query(
        'insurance_policy_payments',
        where: '$fkCol = ?',
        whereArgs: [widget.policyId],
        orderBy: 'created_at DESC, id DESC',
      );

      if (!mounted) return;
      setState(() {
        _payments = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '❌ فشل تحميل الدفعات: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  double get _totalPaid {
    double sum = 0;
    for (final p in _payments) {
      sum += _paymentAmount(p);
    }
    return sum;
  }

  double get _remaining {
    final sell = _policySellPrice;
    if (sell <= 0) return 0;
    final rem = sell - _totalPaid;
    return rem < 0 ? 0 : rem;
  }

  // ---------------------------------------------------------------------------
  Future<void> _addPaymentDialog() async {
    if (_loading) return;

    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String method = 'CASH';
    DateTime payDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إضافة دفعة', textAlign: TextAlign.right),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: method,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'طريقة الدفع',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'CASH', child: Text('نقداً')),
                  DropdownMenuItem(value: 'CHEQUE', child: Text('شيك')),
                  DropdownMenuItem(value: 'INSTALLMENT', child: Text('أقساط')),
                  DropdownMenuItem(value: 'TRANSFER', child: Text('تحويل')),
                  DropdownMenuItem(value: 'BANK', child: Text('بنك')),
                ],
                onChanged: (v) => method = v ?? 'CASH',
              ),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: payDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    payDate = picked;
                    // ignore: use_build_context_synchronously
                    (context as Element).markNeedsBuild();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range),
                      const Spacer(),
                      Text(
                        DateFormat('yyyy-MM-dd').format(payDate),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                maxLines: 2,
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            onPressed: () {
              final amt = _toDouble(amountCtrl.text);
              if (amt <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('⚠️ أدخل مبلغ صحيح')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final amount = _toDouble(amountCtrl.text);
    final notes = notesCtrl.text.trim();

    await _insertPayment(
      amount: amount,
      method: method,
      payDate: payDate,
      notes: notes,
    );
  }

  // ---------------------------------------------------------------------------
  Future<void> _insertPayment({
    required double amount,
    required String method,
    required DateTime payDate,
    required String notes,
  }) async {
    try {
      final db = await DatabaseMigration.database;

      // تخمين عمود FK
      final sample = await db.query(
        'insurance_policy_payments',
        limit: 1,
      );
      final fkCol =
          sample.isEmpty ? 'policy_id' : _policyFkColumnGuess(sample.first);

      await db.insert(
        'insurance_policy_payments',
        {
          fkCol: widget.policyId,
          'amount': amount,
          'method': method,
          'pay_date': DateFormat('yyyy-MM-dd').format(payDate),
          'notes': notes,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إضافة الدفعة')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل إضافة الدفعة: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> _deletePayment(Map<String, dynamic> p) async {
    final pid = _paymentId(p);
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا يمكن تحديد معرف الدفعة')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف', textAlign: TextAlign.right),
        content:
            const Text('هل تريد حذف هذه الدفعة؟', textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = await DatabaseMigration.database;

      // حدّد عمود المعرف حسب الموجود
      String idCol = 'id';
      if (p.containsKey('id')) idCol = 'id';
      if (p.containsKey('uuid')) idCol = 'uuid';
      if (p.containsKey('payment_id')) idCol = 'payment_id';

      await db.delete(
        'insurance_policy_payments',
        where: '$idCol = ?',
        whereArgs: [pid],
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حذف الدفعة')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل حذف الدفعة: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  Widget _summaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            color: Color(0x12000000),
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withOpacity(0.20)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _paymentsList() {
    if (_payments.isEmpty) {
      return const Center(child: Text('لا توجد دفعات لهذه البوليصة'));
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final p = _payments[i];

        final amt = _paymentAmount(p);
        final method = _paymentMethod(p);
        final notes = _paymentNotes(p);
        final d = _paymentDate(p);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                blurRadius: 12,
                color: Color(0x10000000),
                offset: Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'حذف',
                    onPressed: () => _deletePayment(p),
                    icon: const Icon(Icons.delete, color: Colors.red),
                  ),
                  const Spacer(),
                  Text(
                    '${amt.toStringAsFixed(2)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'الطريقة: ${_methodLabel(method)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (d != null)
                Text(
                  'التاريخ: ${DateFormat('yyyy-MM-dd').format(d)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'ملاحظات: $notes',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final title = _plate.isEmpty ? 'دفعات البوليصة' : 'دفعات $_plate';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(
          title,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _loadPayments,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          const SizedBox(width: 6),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _loading ? null : _addPaymentDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                )
              : Container(
                  color: const Color(0xFFF7F8FA),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_company.isNotEmpty)
                        Text(
                          'الشركة: $_company',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Summary row (سطر واحد مع Scroll عند الحاجة)
                      SizedBox(
                        height: 92,
                        child: LayoutBuilder(
                          builder: (_, c) {
                            final w = c.maxWidth;
                            final cardW = (w / 3).clamp(220.0, 340.0);

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: cardW,
                                    child: _summaryCard(
                                      title: 'إجمالي الدفعات',
                                      value: _totalPaid.toStringAsFixed(2),
                                      icon: Icons.payments,
                                      accent: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: cardW,
                                    child: _summaryCard(
                                      title: 'سعر البيع',
                                      value: _policySellPrice <= 0
                                          ? '-'
                                          : _policySellPrice.toStringAsFixed(2),
                                      icon: Icons.sell,
                                      accent: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: cardW,
                                    child: _summaryCard(
                                      title: 'المتبقي',
                                      value: _policySellPrice <= 0
                                          ? '-'
                                          : _remaining.toStringAsFixed(2),
                                      icon: Icons.account_balance_wallet,
                                      accent: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 14),
                      Expanded(child: _paymentsList()),
                    ],
                  ),
                )),
    );
  }

  // ---------------------------------------------------------------------------
  // Utils
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '');
    return double.tryParse(s) ?? 0.0;
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    try {
      return DateTime.parse(s);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy').parseStrict(s);
      } catch (_) {
        return null;
      }
    }
  }

  String _methodLabel(String m) {
    switch (m.toUpperCase()) {
      case 'CASH':
        return 'نقداً';
      case 'CHEQUE':
        return 'شيك';
      case 'INSTALLMENT':
        return 'أقساط';
      case 'TRANSFER':
        return 'تحويل';
      case 'BANK':
        return 'بنك';
      default:
        return m.isEmpty ? '-' : m;
    }
  }
}
