import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_contact_center_service.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

typedef ContactCenterProspectsLoader = Future<List<InsuranceProspectRecord>>
    Function();
typedef ContactCenterTasksLoader = Future<List<InsuranceFollowUpTask>>
    Function();
typedef ContactCenterRecorder = Future<void> Function({
  required String operationId,
  required String partyId,
  required String channel,
  required String result,
  required String notes,
  required DateTime? nextFollowUpAt,
});
typedef ContactCenterTaskCompleter = Future<void> Function(String taskId);

class InsuranceContactCenterScreen extends StatefulWidget {
  const InsuranceContactCenterScreen({
    super.key,
    this.prospectsLoader,
    this.tasksLoader,
    this.recorder,
    this.taskCompleter,
  });

  final ContactCenterProspectsLoader? prospectsLoader;
  final ContactCenterTasksLoader? tasksLoader;
  final ContactCenterRecorder? recorder;
  final ContactCenterTaskCompleter? taskCompleter;

  @override
  State<InsuranceContactCenterScreen> createState() =>
      _InsuranceContactCenterScreenState();
}

class _InsuranceContactCenterScreenState
    extends State<InsuranceContactCenterScreen> {
  late Future<void> _loadFuture;
  List<InsuranceProspectRecord> _prospects = const [];
  List<InsuranceFollowUpTask> _tasks = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final prospects = await (widget.prospectsLoader?.call() ??
        InsuranceCrmService.listProspects());
    final tasks = await (widget.tasksLoader?.call() ??
        InsuranceContactCenterService.listTasks());
    if (!mounted) return;
    setState(() {
      _prospects = prospects;
      _tasks = tasks;
    });
  }

  Future<void> _refresh() async {
    setState(() => _loadFuture = _load());
    await _loadFuture;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InsuranceProspectRecord? _prospectFor(String? partyId) {
    if (partyId == null) return null;
    for (final prospect in _prospects) {
      if (prospect.partyId == partyId) return prospect;
    }
    return null;
  }

  Future<void> _openContact() async {
    if (_prospects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف عميلاً محتملاً أولاً.')),
      );
      return;
    }
    final draft = await showDialog<_ContactDraft>(
      context: context,
      builder: (_) => _ContactDialog(prospects: _prospects),
    );
    if (draft == null) return;
    await _run(() async {
      final operationId = 'UI-${DateTime.now().microsecondsSinceEpoch}';
      if (widget.recorder != null) {
        await widget.recorder!(
          operationId: operationId,
          partyId: draft.partyId,
          channel: draft.channel,
          result: draft.result,
          notes: draft.notes,
          nextFollowUpAt: draft.nextFollowUpAt,
        );
      } else {
        await InsuranceContactCenterService.recordContact(
          operationId: operationId,
          partyId: draft.partyId,
          channel: draft.channel,
          result: draft.result,
          notes: draft.notes,
          nextFollowUpAt: draft.nextFollowUpAt,
        );
      }
      await _refresh();
    });
  }

  Future<void> _complete(InsuranceFollowUpTask task) async {
    await _run(() async {
      if (widget.taskCompleter != null) {
        await widget.taskCompleter!(task.id);
      } else {
        await InsuranceContactCenterService.completeTask(task.id);
      }
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insuranceContactCenterScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('مركز التواصل'),
          actions: [
            IconButton(
              key: const Key('contactCenterRefresh'),
              tooltip: 'تحديث',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('contactCenterAddContact'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: _busy ? null : _openContact,
          icon: const Icon(Icons.add_call),
          label: const Text('تسجيل تواصل'),
        ),
        body: FutureBuilder<void>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل مركز التواصل.'));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _summaryCard(),
                  const SizedBox(height: 14),
                  const Text(
                    'المتابعات المفتوحة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_tasks.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: Text('لا توجد متابعات مفتوحة.'),
                      ),
                    )
                  else
                    for (final task in _tasks) ...[
                      _taskCard(task),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final now = DateTime.now();
    final overdue = _tasks.where((task) {
      final due = task.dueAt;
      return due != null && due.isBefore(now);
    }).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _metric(
                'عملاء التواصل',
                _prospects.length.toString(),
                Icons.groups_2_outlined,
              ),
            ),
            Expanded(
              child: _metric(
                'متابعات مفتوحة',
                _tasks.length.toString(),
                Icons.event_note_outlined,
              ),
            ),
            Expanded(
              child: _metric(
                'متأخرة',
                overdue.toString(),
                Icons.warning_amber_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon) => Column(
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      );

  Widget _taskCard(InsuranceFollowUpTask task) {
    final prospect = _prospectFor(task.partyId);
    final title = task.partyName ?? prospect?.name ?? task.partyId ?? 'متابعة';
    final phone = prospect?.phone.trim() ?? '';
    final due = task.dueAt;
    final dueText = due == null
        ? 'بدون موعد'
        : intl.DateFormat('yyyy/MM/dd HH:mm').format(due);
    return Card(
      key: Key('contactTask-${task.id}'),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.notifications_active)),
        title: Text(title),
        subtitle: Text([
          if (phone.isNotEmpty) phone,
          'الموعد: $dueText',
          if ((task.notes ?? '').trim().isNotEmpty) task.notes!.trim(),
        ].join('\n')),
        trailing: IconButton(
          key: Key('completeContactTask-${task.id}'),
          tooltip: 'تمت المتابعة',
          onPressed: _busy ? null : () => _complete(task),
          icon: const Icon(Icons.task_alt),
        ),
      ),
    );
  }
}

class _ContactDraft {
  const _ContactDraft({
    required this.partyId,
    required this.channel,
    required this.result,
    required this.notes,
    required this.nextFollowUpAt,
  });

  final String partyId;
  final String channel;
  final String result;
  final String notes;
  final DateTime? nextFollowUpAt;
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.prospects});

  final List<InsuranceProspectRecord> prospects;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late String _partyId;
  String _channel = 'PHONE';
  String _result = 'CONTACTED';
  DateTime? _followUp;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _partyId = widget.prospects.first.partyId;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickFollowUp() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تسجيل تواصل جديد'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('contactCenterParty'),
                value: _partyId,
                decoration: const InputDecoration(
                  labelText: 'العميل',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final prospect in widget.prospects)
                    DropdownMenuItem(
                      value: prospect.partyId,
                      child: Text(prospect.name),
                    ),
                ],
                onChanged: (value) => setState(() => _partyId = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('contactCenterChannel'),
                value: _channel,
                decoration: const InputDecoration(
                  labelText: 'قناة التواصل',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'PHONE', child: Text('هاتف')),
                  DropdownMenuItem(value: 'WHATSAPP', child: Text('واتساب')),
                  DropdownMenuItem(
                      value: 'EMAIL', child: Text('بريد إلكتروني')),
                  DropdownMenuItem(value: 'VISIT', child: Text('زيارة')),
                ],
                onChanged: (value) => setState(() => _channel = value!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('contactCenterResult'),
                value: _result,
                decoration: const InputDecoration(
                  labelText: 'النتيجة',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'CONTACTED', child: Text('تم التواصل')),
                  DropdownMenuItem(value: 'INTERESTED', child: Text('مهتم')),
                  DropdownMenuItem(
                      value: 'QUOTE_REQUESTED', child: Text('طلب عرض')),
                  DropdownMenuItem(value: 'NO_ANSWER', child: Text('لا يجيب')),
                  DropdownMenuItem(
                      value: 'NOT_INTERESTED', child: Text('غير مهتم')),
                ],
                onChanged: (value) => setState(() => _result = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('contactCenterNotes'),
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('contactCenterFollowUp'),
                onPressed: _pickFollowUp,
                icon: const Icon(Icons.event),
                label: Text(
                  _followUp == null
                      ? 'بدون موعد متابعة'
                      : 'متابعة ${intl.DateFormat('yyyy/MM/dd').format(_followUp!)}',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('contactCenterSaveContact'),
          onPressed: () => Navigator.pop(
            context,
            _ContactDraft(
              partyId: _partyId,
              channel: _channel,
              result: _result,
              notes: _notes.text.trim(),
              nextFollowUpAt: _followUp,
            ),
          ),
          child: const Text('حفظ التواصل'),
        ),
      ],
    );
  }
}
