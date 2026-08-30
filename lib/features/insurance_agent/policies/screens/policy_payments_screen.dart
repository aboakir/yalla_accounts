// ًں“پ lib/features/insurance_agent/policies/screens/policy_payments_screen.dart
//
// PolicyPaymentsScreen â€” ط¯ظپط¹ط§طھ ط¨ظˆظ„ظٹطµط© ط§ظ„طھط£ظ…ظٹظ† (DB REAL)
// âœ… ط¹ط±ط¶ ط§ظ„ط¯ظپط¹ط§طھ + ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ظ…ط¯ظپظˆط¹ + ط§ظ„ظ…طھط¨ظ‚ظٹ (ط¥ط°ط§ طھظˆظپط± ط³ط¹ط± ط§ظ„ط¨ظٹط¹)
// âœ… ط¥ط¶ط§ظپط© ط¯ظپط¹ط© (Dialog) + ط­ط°ظپ ط¯ظپط¹ط©
// âœ… ط¨ط¯ظˆظ† RTL / Directionality / TextDirection (ظ…ط­ط§ط°ط§ط© ظٹظ…ظٹظ† ظپظ‚ط·)
// âœ… ظٹط¹ظ…ظ„ ط¹ظ„ظ‰ Desktop/Mobile
//
// ظ…ظ„ط§ط­ط¸ط© ظ…ظ‡ظ…ط© ط¬ط¯ط§ظ‹:
// ظ‡ط°ط§ ط§ظ„ظ…ظ„ظپ ظٹظپطھط±ط¶ ظˆط¬ظˆط¯ ط¬ط¯ظˆظ„ ط¨ط§ط³ظ…: insurance_policy_payments
// ط¨ط§ظ„ط£ط¹ظ…ط¯ط© ط§ظ„ظ…ظ‚طھط±ط­ط© (ظ…ط±ظ†ط©):
// - id (INTEGER PRIMARY KEY AUTOINCREMENT)   ط£ظˆ uuid
// - policy_id / policyId / policy_uuid      (ط£ظٹ ظˆط§ط­ط¯ ظ…ظ†ظ‡ظ…)
// - amount (REAL)
// - pay_date (TEXT)  ط£ظˆ payment_date / date
// - method (TEXT)    (CASH / CHEQUE / INSTALLMENT / TRANSFER ...)
// - notes (TEXT)
// - created_at (TEXT)
//
// ط¥ط°ط§ ظƒط§ظ† ط§ط³ظ… ط§ظ„ط¬ط¯ظˆظ„/ط§ظ„ط£ط¹ظ…ط¯ط© ظ…ط®طھظ„ظپ ط¹ظ†ط¯ظƒطŒ ط¹ط¯ظ‘ظ„ ظپظ‚ط· ط§ظ„ظ€ getters ط¯ط§ط®ظ„ ط§ظ„ظ…ظ„ظپ (ظ…ظڈط¹ظ„ظ‘ظ…ط©).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PolicyPaymentsScreen extends StatefulWidget {
  final dynamic policyId; // id / uuid / policy_id
  final Map<String, dynamic>?
      row; // ط¨ظٹط§ظ†ط§طھ ط§ظ„ط¨ظˆظ„ظٹطµط© (ط§ط®طھظٹط§ط±ظٹ)

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
  // Column mapping for payments table (ط¹ط¯ظ‘ظ„ ظ‡ظ†ط§ ظپظ‚ط· ط¥ط°ط§ ط¹ظ†ط¯ظƒ ط£ط³ظ…ط§ط، ظ…ط®طھظ„ظپط©)
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
    // ط´ظˆظپ ط´ظˆ ظ…ظˆط¬ظˆط¯ ط¨ط§ظ„طµظپطŒ ظˆط§ط®طھط± ط§ظ„ط£ظ†ط³ط¨ ظƒظ€ FK
    if (sampleRow.containsKey('policy_id')) return 'policy_id';
    if (sampleRow.containsKey('policyId')) return 'policyId';
    if (sampleRow.containsKey('policy_uuid')) return 'policy_uuid';
    if (sampleRow.containsKey('policyUuid')) return 'policyUuid';
    // ط§ظ„ط§ظپطھط±ط§ط¶ظٹ:
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

      // طھط£ظƒظٹط¯ ظˆط¬ظˆط¯ ط§ظ„ط¬ط¯ظˆظ„
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        ['insurance_policy_payments'],
      );

      if (tables.isEmpty) {
        setState(() {
          _payments = [];
          _loading = false;
          _error =
              'ط¬ط¯ظˆظ„ insurance_policy_payments ط؛ظٹط± ظ…ظˆط¬ظˆط¯. ط£ظ†ط´ط¦ظ‡ ظپظٹ ط§ظ„ظ€ migration ط£ظˆظ„ط§ظ‹.';
        });
        return;
      }

      // ظ†ط¬ظٹط¨ ط¹ظٹظ†ط© طµظپ ظˆط§ط­ط¯ ط¹ط´ط§ظ† ظ†ط®ظ…ظ‘ظ† ط§ط³ظ… ط¹ظ…ظˆط¯ FK
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
        _error = 'â‌Œ ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ط¯ظپط¹ط§طھ: $e';
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AdaptiveAlertDialog(
          title: const Text('ط¥ط¶ط§ظپط© ط¯ظپط¹ط©', textAlign: TextAlign.right),
          content: SizedBox(
            width: MediaQuery.sizeOf(dialogContext).width < 600
                ? double.infinity
                : 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    labelText: 'ط§ظ„ظ…ط¨ظ„ط؛',
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
                    labelText: 'ط·ط±ظٹظ‚ط© ط§ظ„ط¯ظپط¹',
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF7F8FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CASH', child: Text('ظ†ظ‚ط¯ط§ظ‹')),
                    DropdownMenuItem(value: 'CHEQUE', child: Text('ط´ظٹظƒ')),
                    DropdownMenuItem(
                        value: 'INSTALLMENT', child: Text('ط£ظ‚ط³ط§ط·')),
                    DropdownMenuItem(
                        value: 'TRANSFER', child: Text('طھط­ظˆظٹظ„')),
                    DropdownMenuItem(value: 'BANK', child: Text('ط¨ظ†ظƒ')),
                  ],
                  onChanged: (v) => method = v ?? 'CASH',
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: payDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      payDate = picked;
                      if (!dialogContext.mounted) return;
                      setDialogState(() => payDate = picked);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: AdaptiveRow(
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
                    labelText: 'ظ…ظ„ط§ط­ط¸ط§طھ (ط§ط®طھظٹط§ط±ظٹ)',
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
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ط¥ظ„ط؛ط§ط،'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: () {
                final amt = _toDouble(amountCtrl.text);
                if (amt <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('âڑ ï¸ڈ ط£ط¯ط®ظ„ ظ…ط¨ظ„ط؛ طµط­ظٹط­')),
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child:
                  const Text('ط­ظپط¸', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
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

      // طھط®ظ…ظٹظ† ط¹ظ…ظˆط¯ FK
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
        const SnackBar(content: Text('âœ… طھظ… ط¥ط¶ط§ظپط© ط§ظ„ط¯ظپط¹ط©')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ ط¥ط¶ط§ظپط© ط§ظ„ط¯ظپط¹ط©: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> _deletePayment(Map<String, dynamic> p) async {
    final pid = _paymentId(p);
    if (pid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('âڑ ï¸ڈ ظ„ط§ ظٹظ…ظƒظ† طھط­ط¯ظٹط¯ ظ…ط¹ط±ظپ ط§ظ„ط¯ظپط¹ط©')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('طھط£ظƒظٹط¯ ط§ظ„ط­ط°ظپ', textAlign: TextAlign.right),
        content: const Text('ظ‡ظ„ طھط±ظٹط¯ ط­ط°ظپ ظ‡ط°ظ‡ ط§ظ„ط¯ظپط¹ط©طں',
            textAlign: TextAlign.right),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ط­ط°ظپ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = await DatabaseMigration.database;

      // ط­ط¯ظ‘ط¯ ط¹ظ…ظˆط¯ ط§ظ„ظ…ط¹ط±ظپ ط­ط³ط¨ ط§ظ„ظ…ظˆط¬ظˆط¯
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
        const SnackBar(content: Text('âœ… طھظ… ط­ط°ظپ ط§ظ„ط¯ظپط¹ط©')),
      );
      await _loadPayments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ ط­ط°ظپ ط§ظ„ط¯ظپط¹ط©: $e')),
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
      child: AdaptiveRow(
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
      return const Center(
          child: Text('ظ„ط§ طھظˆط¬ط¯ ط¯ظپط¹ط§طھ ظ„ظ‡ط°ظ‡ ط§ظ„ط¨ظˆظ„ظٹطµط©'));
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
              AdaptiveRow(
                children: [
                  IconButton(
                    tooltip: 'ط­ط°ظپ',
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
                'ط§ظ„ط·ط±ظٹظ‚ط©: ${_methodLabel(method)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (d != null)
                Text(
                  'ط§ظ„طھط§ط±ظٹط®: ${DateFormat('yyyy-MM-dd').format(d)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'ظ…ظ„ط§ط­ط¸ط§طھ: $notes',
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
    final title =
        _plate.isEmpty ? 'ط¯ظپط¹ط§طھ ط§ظ„ط¨ظˆظ„ظٹطµط©' : 'ط¯ظپط¹ط§طھ $_plate';

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
            tooltip: 'طھط­ط¯ظٹط«',
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
                          'ط§ظ„ط´ط±ظƒط©: $_company',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      const SizedBox(height: 12),

                      // Summary row (ط³ط·ط± ظˆط§ط­ط¯ ظ…ط¹ Scroll ط¹ظ†ط¯ ط§ظ„ط­ط§ط¬ط©)
                      SizedBox(
                        height: 92,
                        child: LayoutBuilder(
                          builder: (_, c) {
                            final w = c.maxWidth;
                            final cardW = (w / 3).clamp(220.0, 340.0);

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              reverse: true,
                              child: AdaptiveRow(
                                children: [
                                  SizedBox(
                                    width: cardW,
                                    child: _summaryCard(
                                      title: 'ط¥ط¬ظ…ط§ظ„ظٹ ط§ظ„ط¯ظپط¹ط§طھ',
                                      value: _totalPaid.toStringAsFixed(2),
                                      icon: Icons.payments,
                                      accent: Colors.teal,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: cardW,
                                    child: _summaryCard(
                                      title: 'ط³ط¹ط± ط§ظ„ط¨ظٹط¹',
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
                                      title: 'ط§ظ„ظ…طھط¨ظ‚ظٹ',
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
        return 'ظ†ظ‚ط¯ط§ظ‹';
      case 'CHEQUE':
        return 'ط´ظٹظƒ';
      case 'INSTALLMENT':
        return 'ط£ظ‚ط³ط§ط·';
      case 'TRANSFER':
        return 'طھط­ظˆظٹظ„';
      case 'BANK':
        return 'ط¨ظ†ظƒ';
      default:
        return m.isEmpty ? '-' : m;
    }
  }
}
