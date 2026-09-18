import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_queue_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SyncConflictsScreen extends StatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  State<SyncConflictsScreen> createState() => _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends State<SyncConflictsScreen> {
  List<Map<String, Object?>> _rows = const [];
  bool _loading = true;
  String? _busyConflictId;

  static const _labels = <String, String>{
    'vehicle': 'مركبة',
    'repair': 'ملف إصلاح',
    'repair_line': 'بند إصلاح',
    'repair_workflow': 'مرحلة إصلاح',
    'inventory_item': 'صنف مخزون',
    'inventory_warehouse': 'مستودع',
    'invoice': 'فاتورة',
    'payment': 'دفعة',
    'receipt': 'سند قبض',
    'voucher': 'سند مالي',
    'cheque': 'شيك',
    'purchase_invoice': 'فاتورة شراء',
    'purchase_payment': 'دفعة شراء',
    'inventory_movement': 'حركة مخزون',
    'employee_advance': 'سلفة موظف',
    'payroll_run': 'راتب',
    'payroll_payment': 'دفعة راتب',
    'monthly_expense': 'مصروف شهري',
    'gl_entry': 'قيد محاسبي',
    'gl_line': 'سطر قيد',
    'accounting_audit_event': 'تدقيق محاسبي',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final db = await DBService.database;
      final rows = await UnifiedSyncQueueService.openConflicts(db);
      if (mounted) setState(() => _rows = rows);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isFinancial(Map<String, Object?> row) =>
      UnifiedSyncQueueService.financialConflictTypes
          .contains(row['entity_type']?.toString());

  String _label(Map<String, Object?> row) {
    final type = row['entity_type']?.toString() ?? '';
    return _labels[type] ?? type;
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<bool> _confirm(String title, String body, String action) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(title),
            content: Text(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _resolve(
    Map<String, Object?> row, {
    required String decision,
    required String note,
    String? correctionChangeId,
  }) async {
    final conflictId = row['remote_conflict_id']?.toString() ?? '';
    if (conflictId.isEmpty) {
      _message('معرّف التعارض مفقود. أعد المزامنة أولًا.', error: true);
      return;
    }
    setState(() => _busyConflictId = conflictId);
    try {
      final db = await DBService.database;
      final result = await UnifiedSyncCoordinatorV3.instance.resolveConflict(
        conflictId: conflictId,
        decision: decision,
        note: note,
        correctionChangeId: correctionChangeId,
        database: db,
      );
      if (result.status == 'RESOLVED') {
        await UnifiedSyncCoordinatorV3.instance.cycle(database: db);
        _message('تم حسم التعارض ومزامنة النتيجة.');
      } else {
        _message('تم تسجيل التعارض كحالة تحتاج تصحيحًا ماليًا.');
      }
      await _load();
    } catch (error) {
      _message('تعذر معالجة التعارض: $error', error: true);
    } finally {
      if (mounted) setState(() => _busyConflictId = null);
    }
  }

  Future<void> _resolveOperational(
      Map<String, Object?> row, String decision) async {
    final keepLocal = decision == 'KEEP_LOCAL';
    final ok = await _confirm(
      keepLocal ? 'اعتماد نسختك' : 'اعتماد نسخة السيرفر',
      keepLocal
          ? 'سيتم إنشاء إصدار جديد من السجل اعتمادًا على نسختك، دون حذف تاريخ النسخة الأخرى.'
          : 'سيتم تثبيت نسخة السيرفر كإصدار جديد على هذا الجهاز، دون حذف تاريخ التعارض.',
      'تأكيد',
    );
    if (!ok) return;
    await _resolve(
      row,
      decision: decision,
      note: keepLocal
          ? 'User reviewed conflict and kept local version'
          : 'User reviewed conflict and accepted server version',
    );
  }

  Future<void> _startFinancial(Map<String, Object?> row) async {
    final ok = await _confirm(
      'تعارض مالي',
      'لن يسمح النظام بالكتابة فوق حركة مالية موجودة. يجب إنشاء سند أو قيد تصحيح نظامي أولًا، ثم ربطه بهذا التعارض.',
      'بدء التصحيح',
    );
    if (!ok) return;
    await _resolve(
      row,
      decision: 'FINANCIAL_CORRECTION_REQUIRED',
      note: 'User acknowledged that financial correction is required',
    );
  }

  Future<Map<String, Object?>?> _pickCorrection(
      List<Map<String, Object?>> candidates) async {
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: const Text('اختر حركة التصحيح'),
        content: SizedBox(
          width: 520,
          child: candidates.isEmpty
              ? const Text(
                  'لا توجد حركة مالية جديدة متزامنة بعد تسجيل التعارض. أنشئ سند/قيد التصحيح ثم شغّل المزامنة وعد إلى هنا.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final row = candidates[index];
                    final type = row['entity_type']?.toString() ?? '';
                    final title = _labels[type] ?? type;
                    final id = row['entity_id']?.toString() ?? '';
                    final date = row['occurred_at']?.toString() ?? '';
                    return ListTile(
                      title: Text('$title • $id'),
                      subtitle: Text(date),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.pop(context, row),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeFinancial(Map<String, Object?> row) async {
    try {
      final db = await DBService.database;
      await UnifiedSyncCoordinatorV3.instance.cycle(database: db);
      final candidates =
          await UnifiedSyncQueueService.financialCorrectionCandidates(
        db,
        conflictOutboxId: row['outbox_id']!.toString(),
      );
      if (!mounted) return;
      final selected = await _pickCorrection(candidates);
      if (selected == null) return;
      final ok = await _confirm(
        'تأكيد حركة التصحيح',
        'هل هذه الحركة هي التصحيح المحاسبي المقصود لهذا التعارض؟ لن يتم حذف الحركة الأصلية.',
        'ربط وإغلاق',
      );
      if (!ok) return;
      await _resolve(
        row,
        decision: 'FINANCIAL_CORRECTION_COMPLETED',
        correctionChangeId: selected['change_id']!.toString(),
        note: 'User linked an accepted financial correction to the conflict',
      );
    } catch (error) {
      _message('تعذر تحميل حركات التصحيح: $error', error: true);
    }
  }

  Widget _card(Map<String, Object?> row) {
    final conflictId = row['remote_conflict_id']?.toString() ?? '';
    final financial = _isFinancial(row);
    final actionRequired = row['resolution_status'] == 'ACTION_REQUIRED';
    final busy = _busyConflictId == conflictId;
    final entityId = row['entity_id']?.toString() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(financial ? Icons.account_balance : Icons.sync_problem),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_label(row)} • $entityId',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              financial
                  ? (actionRequired
                      ? 'بانتظار ربط حركة التصحيح المالية.'
                      : 'تعارض مالي محمي: لا يُسمح بالكتابة فوق السجل.')
                  : 'يوجد إصداران لنفس السجل. اختر النسخة التي يجب أن تصبح الإصدار التالي.',
            ),
            const SizedBox(height: 12),
            if (!financial)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => _resolveOperational(row, 'KEEP_LOCAL'),
                    icon: const Icon(Icons.phone_android),
                    label: const Text('اعتماد نسختي'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => _resolveOperational(row, 'ACCEPT_SERVER'),
                    icon: const Icon(Icons.cloud_done),
                    label: const Text('اعتماد نسخة السيرفر'),
                  ),
                ],
              )
            else if (!actionRequired)
              FilledButton.icon(
                onPressed: busy ? null : () => _startFinancial(row),
                icon: const Icon(Icons.rule),
                label: const Text('بدء مسار التصحيح المالي'),
              )
            else
              FilledButton.icon(
                onPressed: busy ? null : () => _completeFinancial(row),
                icon: const Icon(Icons.link),
                label: const Text('ربط حركة التصحيح وإغلاق التعارض'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز تعارضات المزامنة'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.cloud_done, size: 64),
                      SizedBox(height: 16),
                      Center(
                        child: Text(
                          'لا توجد تعارضات مفتوحة في المزامنة.',
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rows.length,
                    itemBuilder: (_, index) => _card(_rows[index]),
                  ),
      ),
    );
  }
}
