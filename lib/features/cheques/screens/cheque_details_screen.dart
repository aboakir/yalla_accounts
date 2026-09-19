import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/features/auth/services/permission_service.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequeDetailsScreen extends StatefulWidget {
  const ChequeDetailsScreen({super.key, required this.cheque});
  final Cheque cheque;

  @override
  State<ChequeDetailsScreen> createState() => _ChequeDetailsScreenState();
}

class _ChequeDetailsScreenState extends State<ChequeDetailsScreen> {
  final _service = ChequeService();
  final _permissions = PermissionService();
  late Cheque _cheque;
  late Future<ChequeTraceResult> _trace;
  final _allowed = <String, bool>{};
  final _date = DateFormat('yyyy-MM-dd');
  final _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  final _money = NumberFormat('#,##0.00', 'ar');

  @override
  void initState() {
    super.initState();
    _cheque = widget.cheque;
    _reloadTrace();
    _loadPermissions();
  }

  void _reloadTrace() {
    _trace = ChequeTraceService.load(_cheque.id!);
  }

  Future<void> _loadPermissions() async {
    const keys = [
      PermissionKeys.chequeEdit,
      PermissionKeys.chequeDeposit,
      PermissionKeys.chequeCollect,
      PermissionKeys.chequeReturn,
      PermissionKeys.chequeCancel,
      PermissionKeys.chequeEndorse,
      PermissionKeys.chequeDueDateEdit,
      PermissionKeys.chequePrint,
    ];
    final values = await Future.wait(keys.map(_permissions.canCurrent));
    if (!mounted) return;
    setState(() {
      for (var i = 0; i < keys.length; i++) {
        _allowed[keys[i]] = values[i];
      }
    });
  }

  bool _can(String permission) => _allowed[permission] == true;

  Future<void> _refresh() async {
    final id = _cheque.id;
    if (id == null) return;
    final updated = await _service.getById(id);
    if (!mounted || updated == null) return;
    setState(() {
      _cheque = updated;
      _reloadTrace();
    });
  }

  Future<void> _transition(ChequeStatus status, {String? reason}) async {
    try {
      await _service.transitionStatus(
        chequeId: _cheque.id!,
        status: status,
        reason: reason,
        eventDate: DateTime.now(),
      );
      await _refresh();
    } catch (e) {
      _snack('تعذر تنفيذ الحركة: ${UserFacingError.message(e)}');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: 'Yallah Accounts',
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesList),
      body: AdaptiveRow(
        children: [
          if (desktop) const YallaSidebar(currentRoute: AppRoutes.chequesList),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                _headerCard(),
                const SizedBox(height: 12),
                _actionsCard(),
                const SizedBox(height: 12),
                _traceCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard() {
    final c = _cheque;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'شيك ${c.chequeNo}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _fact('الاتجاه',
                    c.direction == ChequeDirection.received ? 'وارد' : 'صادر'),
                _fact('الحالة', _statusLabel(c.status)),
                _fact('القيمة', '${_money.format(c.amount)} ${c.currency}'),
                _fact(
                    'البنك',
                    c.bankBranch.isEmpty
                        ? c.bankName
                        : '${c.bankName} — ${c.bankBranch}'),
                _fact('الساحب', c.drawerName),
                if ((c.recipientName ?? '').isNotEmpty)
                  _fact('المستفيد', c.recipientName!),
                _fact('تاريخ الإصدار', _date.format(c.issueDate)),
                _fact('الاستحقاق', _date.format(c.dueDate)),
                if (c.depositedAt != null)
                  _fact('الإيداع', _dateTime.format(c.depositedAt!)),
                if (c.collectionDate != null)
                  _fact('التحصيل', _dateTime.format(c.collectionDate!)),
                if (c.deliveredAt != null)
                  _fact('التسليم', _dateTime.format(c.deliveredAt!)),
                if (c.presentedAt != null)
                  _fact('التقديم', _dateTime.format(c.presentedAt!)),
                if (c.clearedAt != null)
                  _fact('الصرف', _dateTime.format(c.clearedAt!)),
                if (c.returnedAt != null)
                  _fact('الإرجاع', _dateTime.format(c.returnedAt!)),
                if (c.cancelledAt != null)
                  _fact('الإلغاء', _dateTime.format(c.cancelledAt!)),
              ],
            ),
            if ((c.notes ?? '').trim().isNotEmpty) ...[
              const Divider(),
              Text('ملاحظات: ${c.notes}'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return SizedBox(
      width: 250,
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard() {
    final c = _cheque;
    final terminal = const {
      ChequeStatus.collected,
      ChequeStatus.cleared,
      ChequeStatus.returned,
      ChequeStatus.cancelled,
    }.contains(c.status);
    final actions = <Widget>[];

    if (_can(PermissionKeys.chequeDueDateEdit) && !terminal) {
      actions.add(OutlinedButton.icon(
        onPressed: _changeDueDate,
        icon: const Icon(Icons.event),
        label: const Text('تعديل الاستحقاق'),
      ));
    }

    if (c.direction == ChequeDirection.received) {
      if (_can(PermissionKeys.chequeDeposit) &&
          const {ChequeStatus.received, ChequeStatus.held}.contains(c.status)) {
        actions.add(FilledButton.icon(
          onPressed: () =>
              Navigator.pushNamed(context, AppRoutes.chequesCollection),
          icon: const Icon(Icons.account_balance),
          label: const Text('إيداع للتحصيل'),
        ));
      }
      if (_can(PermissionKeys.chequeCollect) &&
          c.status == ChequeStatus.deposited) {
        actions.add(FilledButton.tonalIcon(
          onPressed: () => _transition(ChequeStatus.collected),
          icon: const Icon(Icons.verified),
          label: const Text('تأكيد التحصيل'),
        ));
      }
      if (_can(PermissionKeys.chequeEndorse) &&
          c.isEndorsed != 1 &&
          const {ChequeStatus.received, ChequeStatus.held}.contains(c.status)) {
        actions.add(OutlinedButton.icon(
          onPressed: _endorse,
          icon: const Icon(Icons.call_made),
          label: const Text('تظهير لمورد'),
        ));
      }
    } else {
      if (c.status == ChequeStatus.issued) {
        actions.add(FilledButton.tonalIcon(
          onPressed: () => _transition(ChequeStatus.delivered),
          icon: const Icon(Icons.outbox),
          label: const Text('تسجيل التسليم'),
        ));
      }
      if (c.status == ChequeStatus.delivered) {
        actions.add(OutlinedButton.icon(
          onPressed: () => _transition(ChequeStatus.presented),
          icon: const Icon(Icons.present_to_all),
          label: const Text('تسجيل التقديم'),
        ));
      }
      if (_can(PermissionKeys.chequeCollect) &&
          const {ChequeStatus.delivered, ChequeStatus.presented}
              .contains(c.status)) {
        actions.add(FilledButton.icon(
          onPressed: () => _transition(ChequeStatus.cleared),
          icon: const Icon(Icons.account_balance),
          label: const Text('تم الصرف من البنك'),
        ));
      }
    }

    if (_can(PermissionKeys.chequeReturn) &&
        !terminal &&
        c.status != ChequeStatus.issued) {
      actions.add(OutlinedButton.icon(
        onPressed: () => _reasonTransition(ChequeStatus.returned),
        icon: const Icon(Icons.undo),
        label: const Text('راجع'),
      ));
    }
    if (_can(PermissionKeys.chequeCancel) && !terminal && c.isEndorsed != 1) {
      actions.add(OutlinedButton.icon(
        onPressed: () => _reasonTransition(ChequeStatus.cancelled),
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('إلغاء'),
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(spacing: 8, runSpacing: 8, children: actions),
      ),
    );
  }

  Future<void> _reasonTransition(ChequeStatus status) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: Text(
            status == ChequeStatus.returned ? 'إرجاع الشيك' : 'إلغاء الشيك'),
        content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'السبب')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (ok != true || reason.isEmpty) return;
    await _transition(status, reason: reason);
  }

  Future<void> _changeDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _cheque.dueDate,
      firstDate: _cheque.issueDate,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    try {
      await _service.updateDueDate(
        chequeId: _cheque.id!,
        dueDate: picked,
        reason: 'User updated maturity date',
      );
      await _refresh();
    } catch (e) {
      _snack('تعذر تعديل الاستحقاق: ${UserFacingError.message(e)}');
    }
  }

  Future<void> _endorse() async {
    final trace = await _trace;
    final db = await DBService.database;
    final suppliers = await db.query('suppliers', orderBy: 'name');
    if (!mounted || suppliers.isEmpty) return;
    String supplierId = suppliers.first['id'].toString();
    DateTime date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AdaptiveAlertDialog(
          title: const Text('تظهير الشيك لمورد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: supplierId,
                isExpanded: true,
                items: [
                  for (final s in suppliers)
                    DropdownMenuItem(
                        value: s['id'].toString(),
                        child: Text(s['name'].toString())),
                ],
                onChanged: (v) => setD(() => supplierId = v ?? supplierId),
              ),
              ListTile(
                title: const Text('تاريخ التظهير'),
                subtitle: Text(_date.format(date)),
                onTap: () async {
                  final d = await showDatePicker(
                      context: ctx,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (d != null) setD(() => date = d);
                },
              ),
              Text(
                  'سيتم حفظ سلسلة الملكية؛ التظهير السابق: ${trace.endorsements.length}'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تظهير')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _service.endorseCheque(
        chequeId: _cheque.id!,
        supplierPid: supplierId,
        endorsementDate: date,
      );
      await _refresh();
    } catch (e) {
      _snack('تعذر التظهير: ${UserFacingError.message(e)}');
    }
  }

  Widget _traceCard() {
    return FutureBuilder<ChequeTraceResult>(
      future: _trace,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Card(
              child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator())));
        }
        if (snap.hasError)
          return Card(
              child: ListTile(
                  title: const Text('تعذر تحميل مسار الشيك'),
                  subtitle: Text('${snap.error}')));
        final t = snap.data!;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('التتبع المالي الكامل',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                _traceGroup(
                    'السند',
                    t.voucherLinks
                        .map((r) =>
                            '${r['voucher_type']} #${r['voucher_id']} — ${r['amount']}')
                        .toList()),
                _traceGroup(
                    'التخصيصات',
                    t.allocations
                        .map((r) =>
                            '${r['allocation_type']} → ${r['target_id']} — ${r['amount']}')
                        .toList()),
                _traceGroup(
                    'الأطراف',
                    t.parties
                        .map((r) =>
                            '${r['party_type']} — ${r['name'] ?? r['id']}')
                        .toList()),
                _traceGroup(
                    'Payments',
                    t.payments
                        .map((r) =>
                            '${r['id']} • Repair ${r['repair_id'] ?? r['relatedRepairId'] ?? '—'} • Invoice ${r['invoice_id'] ?? '—'}')
                        .toList()),
                _traceGroup(
                    'قيود GL',
                    t.glEntries
                        .map((r) =>
                            '#${r['entry_id']} ${r['source']}/${r['source_id']} • ${r['account_code']} • D ${r['debit']} / C ${r['credit']}')
                        .toList()),
                _traceGroup(
                    'دفعات الإيداع',
                    t.depositItems
                        .map((r) =>
                            '${r['batch_id']} • ${r['deposit_date']} • ${r['amount']}')
                        .toList()),
                _traceGroup(
                    'سلسلة التظهير',
                    t.endorsements
                        .map((r) =>
                            '#${r['sequence_no']} ${r['from_party_name'] ?? '—'} → ${r['to_party_name']} • ${r['amount']}')
                        .toList()),
                _timeline(t.events),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _traceGroup(String title, List<String> lines) {
    return ExpansionTile(
      title: Text('$title (${lines.length})'),
      children: lines.isEmpty
          ? const [ListTile(title: Text('لا توجد بيانات'))]
          : [
              for (final line in lines) ListTile(dense: true, title: Text(line))
            ],
    );
  }

  Widget _timeline(List<Map<String, Object?>> events) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text('Timeline (${events.length})'),
      children: [
        for (final e in events)
          ListTile(
            leading: const Icon(Icons.timeline),
            title: Text(e['event_type']?.toString() ?? ''),
            subtitle: Text(
              '${e['event_date']} • ${e['from_status'] ?? '—'} → ${e['to_status'] ?? '—'}'
              '${(e['reason'] ?? '').toString().isEmpty ? '' : ' • ${e['reason']}'}',
            ),
          ),
      ],
    );
  }

  String _statusLabel(ChequeStatus status) {
    switch (status) {
      case ChequeStatus.pending:
        return 'قديم/معلّق';
      case ChequeStatus.received:
        return 'مستلم';
      case ChequeStatus.held:
        return 'محتفظ به';
      case ChequeStatus.deposited:
        return 'مودع';
      case ChequeStatus.collected:
        return 'محصل';
      case ChequeStatus.endorsed:
        return 'مظهّر';
      case ChequeStatus.issued:
        return 'صادر';
      case ChequeStatus.delivered:
        return 'مسلّم';
      case ChequeStatus.presented:
        return 'مقدم/مستحق';
      case ChequeStatus.cleared:
        return 'مصروف من البنك';
      case ChequeStatus.returned:
        return 'راجع';
      case ChequeStatus.cancelled:
        return 'ملغى';
    }
  }
}
