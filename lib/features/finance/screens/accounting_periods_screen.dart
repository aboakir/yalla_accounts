import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/services/accounting_period_service.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';

typedef AccountingPeriodsLoader = Future<List<Map<String, Object?>>> Function();
typedef AccountingPeriodCloseAction = Future<void> Function(
    DateTime start, DateTime end, String? note);
typedef AccountingPeriodReopenAction = Future<void> Function(
    int closeId, String reason);

class AccountingPeriodsScreen extends StatefulWidget {
  const AccountingPeriodsScreen({
    super.key,
    this.loadPeriods,
    this.closePeriod,
    this.reopenPeriod,
  });

  final AccountingPeriodsLoader? loadPeriods;
  final AccountingPeriodCloseAction? closePeriod;
  final AccountingPeriodReopenAction? reopenPeriod;

  @override
  State<AccountingPeriodsScreen> createState() =>
      _AccountingPeriodsScreenState();
}

class _AccountingPeriodsScreenState extends State<AccountingPeriodsScreen> {
  final _monthFormat = DateFormat('yyyy-MM');
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _periods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await (widget.loadPeriods?.call() ??
          AccountingPeriodService.periods());
      if (!mounted) return;
      setState(() {
        _periods = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.message(e);
        _loading = false;
      });
    }
  }

  DateTime get _monthEnd => DateTime(_month.year, _month.month + 1, 0);

  Future<String?> _reasonDialog({
    required String title,
    required String label,
    bool requiredValue = false,
  }) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final clean = controller.text.trim();
              if (requiredValue && clean.isEmpty) return;
              Navigator.pop(dialogContext, clean);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _closeMonth() async {
    final note = await _reasonDialog(
      title: 'إغلاق الفترة ${_monthFormat.format(_month)}',
      label: 'ملاحظة الإغلاق',
    );
    if (note == null) return;
    try {
      final custom = widget.closePeriod;
      if (custom == null) {
        await AccountingPeriodService.closePeriod(
          start: _month,
          end: _monthEnd,
          note: note,
        );
      } else {
        await custom(_month, _monthEnd, note);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إغلاق الفترة ${_monthFormat.format(_month)}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر إغلاق الفترة: ${UserFacingError.message(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _reopen(Map<String, Object?> row) async {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) return;
    final reason = await _reasonDialog(
      title: 'إعادة فتح الفترة',
      label: 'سبب إعادة الفتح',
      requiredValue: true,
    );
    if (reason == null || reason.trim().isEmpty) return;
    try {
      final custom = widget.reopenPeriod;
      if (custom == null) {
        await AccountingPeriodService.reopenPeriod(
          id,
          reason: reason,
        );
      } else {
        await custom(id, reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إعادة فتح الفترة')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر إعادة فتح الفترة: ${UserFacingError.message(e)}',
          ),
        ),
      );
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  String _dateText(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    final local = parsed.toLocal();
    return DateFormat('yyyy-MM-dd').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: const Text('الفترات المحاسبية'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('خطأ: $_error'))
              : ListView(
                  padding: EdgeInsets.all(compact ? 10 : 16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'الفترة المراد إغلاقها',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'الشهر السابق',
                                  onPressed: () => _changeMonth(-1),
                                  icon: const Icon(Icons.chevron_right),
                                ),
                                Text(
                                  _monthFormat.format(_month),
                                  key: const ValueKey(
                                    'accounting-period-selected-month',
                                  ),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                IconButton(
                                  tooltip: 'الشهر التالي',
                                  onPressed: () => _changeMonth(1),
                                  icon: const Icon(Icons.chevron_left),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              key: const ValueKey(
                                'accounting-period-close-button',
                              ),
                              onPressed: _closeMonth,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('إغلاق الفترة'),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'يتم فحص سلامة القيود قبل الإغلاق. بعد الإغلاق '
                              'تُرفض أي حركة مالية بتاريخ يقع داخل الفترة.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'سجل الفترات',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (_periods.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'لا توجد فترات مغلقة بعد.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      for (final row in _periods)
                        Card(
                          child: ListTile(
                            leading: Icon(
                              row['status'] == 'CLOSED'
                                  ? Icons.lock
                                  : Icons.lock_open,
                            ),
                            title: Text(
                              '${_dateText(row['period_start_utc'])} — '
                              '${_dateText(row['period_end_exclusive_utc'])}',
                            ),
                            subtitle: Text(
                              'الحالة: ${row['status']}'
                              '${row['note'] == null || row['note'].toString().trim().isEmpty ? '' : '\n${row['note']}'}',
                            ),
                            isThreeLine: row['note'] != null &&
                                row['note'].toString().trim().isNotEmpty,
                            trailing: row['status'] == 'CLOSED'
                                ? TextButton(
                                    onPressed: () => _reopen(row),
                                    child: const Text('إعادة فتح'),
                                  )
                                : const Text('مفتوحة'),
                          ),
                        ),
                  ],
                ),
    );
  }
}
