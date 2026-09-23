import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/renewals/services/insurance_renewal_service.dart';

typedef InsuranceRenewalLoader = Future<List<InsuranceRenewalCandidate>>
    Function();
typedef InsuranceRenewalUpdater = Future<void> Function({
  required String policyId,
  required String status,
  DateTime? lastContactAt,
  DateTime? nextContactAt,
  String? outcome,
});

enum _Filter { all, due30, expired, renewed }

class InsuranceRenewalsScreen extends StatefulWidget {
  const InsuranceRenewalsScreen({super.key, this.loader, this.updater});

  final InsuranceRenewalLoader? loader;
  final InsuranceRenewalUpdater? updater;

  @override
  State<InsuranceRenewalsScreen> createState() =>
      _InsuranceRenewalsScreenState();
}

class _InsuranceRenewalsScreenState extends State<InsuranceRenewalsScreen> {
  _Filter _filter = _Filter.all;
  late Future<List<InsuranceRenewalCandidate>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.loader?.call() ?? InsuranceRenewalService.listCandidates();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  List<InsuranceRenewalCandidate> _filtered(
      List<InsuranceRenewalCandidate> rows) {
    switch (_filter) {
      case _Filter.all:
        return rows;
      case _Filter.due30:
        return rows
            .where((e) =>
                e.status != 'RENEWED' &&
                e.daysRemaining >= 0 &&
                e.daysRemaining <= 30)
            .toList(growable: false);
      case _Filter.expired:
        return rows.where((e) => e.isExpired).toList(growable: false);
      case _Filter.renewed:
        return rows.where((e) => e.status == 'RENEWED').toList(growable: false);
    }
  }

  Future<void> _update(InsuranceRenewalCandidate item, String status) async {
    final updater = widget.updater;
    if (updater != null) {
      await updater(
        policyId: item.policyId,
        status: status,
        lastContactAt: DateTime.now(),
      );
    } else {
      await InsuranceRenewalService.updateFollowUp(
        policyId: item.policyId,
        status: status,
        lastContactAt: DateTime.now(),
      );
    }
    if (mounted) await _refresh();
  }

  Future<void> _chooseStatus(InsuranceRenewalCandidate item) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Text(
              '\u062a\u062d\u062f\u064a\u062b \u062d\u0627\u0644\u0629 \u0627\u0644\u0645\u062a\u0627\u0628\u0639\u0629',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final status in InsuranceRenewalService.followUpStatuses)
              ListTile(
                key: Key('renewalStatusOption-$status'),
                title: Text(_statusLabel(status)),
                trailing: item.status == status
                    ? const Icon(Icons.check_circle)
                    : null,
                onTap: () => Navigator.pop(context, status),
              ),
          ],
        ),
      ),
    );
    if (value == null || value == item.status) return;
    try {
      await _update(item, value);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '\u062a\u0639\u0630\u0631 \u062a\u062d\u062f\u064a\u062b \u062d\u0627\u0644\u0629 \u0627\u0644\u062a\u062c\u062f\u064a\u062f.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insuranceRenewalsScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
              '\u0645\u0631\u0643\u0632 \u0627\u0644\u062a\u062c\u062f\u064a\u062f\u0627\u062a'),
          actions: [
            IconButton(
              key: const Key('renewalsRefresh'),
              tooltip: '\u062a\u062d\u062f\u064a\u062b',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            _filterBar(),
            Expanded(
              child: FutureBuilder<List<InsuranceRenewalCandidate>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _message(
                      '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0627\u0644\u062a\u062c\u062f\u064a\u062f\u0627\u062a',
                      Icons.error_outline,
                    );
                  }
                  final rows = _filtered(snapshot.data ?? const []);
                  if (rows.isEmpty) {
                    return _message(
                      '\u0644\u0627 \u062a\u0648\u062c\u062f \u062a\u062c\u062f\u064a\u062f\u0627\u062a \u0636\u0645\u0646 \u0647\u0630\u0627 \u0627\u0644\u062a\u0635\u0646\u064a\u0641',
                      Icons.autorenew,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _RenewalCard(
                        item: rows[i],
                        onStatus: () => _chooseStatus(rows[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    const entries = <(_Filter, String, String)>[
      (_Filter.all, '\u0627\u0644\u0643\u0644', 'renewalFilterAll'),
      (
        _Filter.due30,
        '\u062e\u0644\u0627\u0644 30 \u064a\u0648\u0645',
        'renewalFilterDue30'
      ),
      (
        _Filter.expired,
        '\u0645\u0646\u062a\u0647\u064a\u0629',
        'renewalFilterExpired'
      ),
      (_Filter.renewed, '\u0645\u062c\u062f\u062f', 'renewalFilterRenewed'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                key: Key(e.$3),
                label: Text(e.$2),
                selected: _filter == e.$1,
                onSelected: (_) => setState(() => _filter = e.$1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _message(String text, IconData icon) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 80),
          Icon(icon, size: 64),
          const SizedBox(height: 16),
          Center(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonal(
              onPressed: _refresh,
              child: const Text(
                  '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'),
            ),
          ),
        ],
      );
}

class _RenewalCard extends StatelessWidget {
  const _RenewalCard({required this.item, required this.onStatus});

  final InsuranceRenewalCandidate item;
  final VoidCallback onStatus;

  @override
  Widget build(BuildContext context) {
    final policy = item.policyNumber ?? item.documentNumber ?? item.policyId;
    final customer = item.customerName ??
        '\u0639\u0645\u064a\u0644 \u063a\u064a\u0631 \u0645\u0639\u0631\u0648\u0641';
    final due = item.status == 'RENEWED'
        ? '\u062a\u0645 \u0627\u0644\u062a\u062c\u062f\u064a\u062f'
        : item.daysRemaining < 0
            ? '\u0645\u062a\u0623\u062e\u0631 ${item.daysRemaining.abs()} \u064a\u0648\u0645'
            : '\u0645\u062a\u0628\u0642\u064a ${item.daysRemaining} \u064a\u0648\u0645';
    return Card(
      key: Key('renewalCard-${item.policyId}'),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(item.isExpired ? Icons.warning_amber : Icons.autorenew),
        ),
        title:
            Text(customer, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '\u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629: $policy\n'
          '\u0627\u0644\u062a\u062c\u062f\u064a\u062f: ${_date(item.renewalDate)} - $due\n'
          '\u0627\u0644\u062d\u0627\u0644\u0629: ${_statusLabel(item.status)}',
        ),
        isThreeLine: true,
        trailing: IconButton(
          key: Key('renewalStatus-${item.policyId}'),
          tooltip:
              '\u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0645\u062a\u0627\u0628\u0639\u0629',
          onPressed: onStatus,
          icon: const Icon(Icons.edit_note),
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

String _statusLabel(String status) {
  const labels = <String, String>{
    'PENDING':
        '\u0642\u064a\u062f \u0627\u0644\u0645\u062a\u0627\u0628\u0639\u0629',
    'NOT_CONTACTED':
        '\u0644\u0645 \u064a\u062a\u0645 \u0627\u0644\u062a\u0648\u0627\u0635\u0644',
    'CONTACTED': '\u062a\u0645 \u0627\u0644\u062a\u0648\u0627\u0635\u0644',
    'NO_ANSWER': '\u0644\u0627 \u0625\u062c\u0627\u0628\u0629',
    'WHATSAPP_SENT':
        '\u0623\u0631\u0633\u0644 \u0648\u0627\u062a\u0633\u0627\u0628',
    'QUOTE_SENT': '\u0623\u0631\u0633\u0644 \u0639\u0631\u0636',
    'ACCEPTED': '\u0645\u0642\u0628\u0648\u0644',
    'REJECTED': '\u0645\u0631\u0641\u0648\u0636',
    'RENEWED': '\u062a\u0645 \u0627\u0644\u062a\u062c\u062f\u064a\u062f',
    'RENEWED_COMPETITOR':
        '\u062c\u062f\u062f \u0644\u062f\u0649 \u0645\u0646\u0627\u0641\u0633',
    'CANCELLED': '\u0645\u0644\u063a\u0649',
  };
  return labels[status] ?? status;
}
