import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/services/insurance_endorsement_service.dart';

typedef InsuranceEndorsementLoader = Future<List<Map<String, Object?>>>
    Function(
  String policyId,
);

class InsurancePolicyEndorsementsScreen extends StatefulWidget {
  const InsurancePolicyEndorsementsScreen({
    super.key,
    required this.policyId,
    this.loader,
  });

  final String policyId;
  final InsuranceEndorsementLoader? loader;

  @override
  State<InsurancePolicyEndorsementsScreen> createState() =>
      _InsurancePolicyEndorsementsScreenState();
}

class _InsurancePolicyEndorsementsScreenState
    extends State<InsurancePolicyEndorsementsScreen> {
  late Future<List<Map<String, Object?>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.loader?.call(widget.policyId) ??
        InsuranceEndorsementService.listForPolicy(widget.policyId);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  double _number(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

  Future<void> _createEndorsement() async {
    if (_busy) return;
    final draft = await showDialog<_EndorsementDraft>(
      context: context,
      builder: (dialogContext) => const _EndorsementDialog(),
    );
    if (draft == null) return;
    setState(() => _busy = true);
    try {
      await InsuranceEndorsementService.postEndorsement(
        InsuranceEndorsementCommand(
          operationId: 'ui-${DateTime.now().microsecondsSinceEpoch}',
          policyId: widget.policyId,
          endorsementType: draft.type,
          effectiveDate: draft.effectiveDate,
          deltaSale: draft.deltaSale,
          deltaCost: draft.deltaCost,
          deltaTax: draft.deltaTax,
          payload: const {'source': 'ENDORSEMENTS_SCREEN'},
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '\u062a\u0645 \u062a\u0631\u062d\u064a\u0644 \u0627\u0644\u0645\u0644\u062d\u0642 \u0627\u0644\u062a\u0623\u0645\u064a\u0646\u064a \u0628\u0646\u062c\u0627\u062d.'),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '\u062a\u0639\u0630\u0631 \u062a\u0631\u062d\u064a\u0644 \u0627\u0644\u0645\u0644\u062d\u0642: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverse(Map<String, Object?> row) async {
    if (_busy || (row['status'] ?? '').toString().toUpperCase() != 'POSTED') {
      return;
    }
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _ReversalReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await InsuranceEndorsementService.reverseEndorsement(
        endorsementId: row['id'].toString(),
        reversalDate: DateTime.now(),
        reason: reason.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '\u062a\u0645 \u0639\u0643\u0633 \u0627\u0644\u0645\u0644\u062d\u0642 \u0628\u0646\u062c\u0627\u062d.'),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '\u062a\u0639\u0630\u0631 \u0639\u0643\u0633 \u0627\u0644\u0645\u0644\u062d\u0642: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insurancePolicyEndorsementsScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
              '\u0645\u0644\u062d\u0642\u0627\u062a \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629'),
          actions: [
            IconButton(
              key: const Key('endorsementsRefresh'),
              tooltip: '\u062a\u062d\u062f\u064a\u062b',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('addInsuranceEndorsement'),
          onPressed: _busy ? null : _createEndorsement,
          icon: const Icon(Icons.add),
          label: const Text(
              '\u0625\u0636\u0627\u0641\u0629 \u0645\u0644\u062d\u0642'),
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _message(
                '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0645\u0644\u062d\u0642\u0627\u062a \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629',
                Icons.error_outline,
              );
            }
            final rows = snapshot.data ?? const <Map<String, Object?>>[];
            if (rows.isEmpty) {
              return _message(
                '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0644\u062d\u0642\u0627\u062a \u0644\u0647\u0630\u0647 \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629.',
                Icons.note_add_outlined,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final row = rows[index];
                  final status = (row['status'] ?? '').toString().toUpperCase();
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      title: Text(
                        (row['endorsement_type'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${row['effective_date']}\n'
                          '\u0641\u0631\u0642 \u0627\u0644\u0628\u064a\u0639: ${_number(row['delta_sale']).toStringAsFixed(2)} \u2022 '
                          '\u0641\u0631\u0642 \u0627\u0644\u062a\u0643\u0644\u0641\u0629: ${_number(row['delta_cost']).toStringAsFixed(2)}',
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Chip(label: Text(status)),
                          if (status == 'POSTED')
                            IconButton(
                              key: Key('reverseEndorsement-${row['id']}'),
                              tooltip:
                                  '\u0639\u0643\u0633 \u0627\u0644\u0645\u0644\u062d\u0642',
                              onPressed: _busy ? null : () => _reverse(row),
                              icon: const Icon(Icons.undo),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
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
          Center(child: Text(text, textAlign: TextAlign.center)),
        ],
      );
}

class _EndorsementDraft {
  const _EndorsementDraft({
    required this.type,
    required this.effectiveDate,
    required this.deltaSale,
    required this.deltaCost,
    required this.deltaTax,
  });

  final String type;
  final DateTime effectiveDate;
  final double deltaSale;
  final double deltaCost;
  final double deltaTax;
}

class _EndorsementDialog extends StatefulWidget {
  const _EndorsementDialog();

  @override
  State<_EndorsementDialog> createState() => _EndorsementDialogState();
}

class _EndorsementDialogState extends State<_EndorsementDialog> {
  final _type = TextEditingController();
  final _date = TextEditingController(
    text: DateTime.now().toIso8601String().split('T').first,
  );
  final _sale = TextEditingController(text: '0');
  final _cost = TextEditingController(text: '0');
  final _tax = TextEditingController(text: '0');
  @override
  void dispose() {
    _type.dispose();
    _date.dispose();
    _sale.dispose();
    _cost.dispose();
    _tax.dispose();
    super.dispose();
  }

  void _submit() {
    final type = _type.text.trim();
    final effectiveDate = DateTime.tryParse(_date.text.trim());
    final sale = double.tryParse(_sale.text.trim());
    final cost = double.tryParse(_cost.text.trim());
    final tax = double.tryParse(_tax.text.trim());
    if (type.isEmpty ||
        effectiveDate == null ||
        sale == null ||
        cost == null ||
        tax == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              '\u0623\u0643\u0645\u0644 \u0627\u0644\u062d\u0642\u0648\u0644 \u0628\u0642\u064a\u0645 \u0635\u062d\u064a\u062d\u0629.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _EndorsementDraft(
        type: type,
        effectiveDate: effectiveDate,
        deltaSale: sale,
        deltaCost: cost,
        deltaTax: tax,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const numberKeyboard = TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );
    return AlertDialog(
      title: const Text(
          '\u0625\u0636\u0627\u0641\u0629 \u0645\u0644\u062d\u0642 \u062a\u0623\u0645\u064a\u0646\u064a'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('endorsementTypeField'),
                controller: _type,
                decoration: const InputDecoration(
                  labelText:
                      '\u0646\u0648\u0639 \u0627\u0644\u0645\u0644\u062d\u0642',
                ),
              ),
              TextField(
                key: const Key('endorsementDateField'),
                controller: _date,
                decoration: const InputDecoration(
                  labelText:
                      '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u0633\u0631\u064a\u0627\u0646 YYYY-MM-DD',
                ),
              ),
              TextField(
                key: const Key('endorsementSaleField'),
                controller: _sale,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText:
                      '\u0641\u0631\u0642 \u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639',
                ),
              ),
              TextField(
                key: const Key('endorsementCostField'),
                controller: _cost,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText:
                      '\u0641\u0631\u0642 \u062a\u0643\u0644\u0641\u0629 \u0627\u0644\u0634\u0631\u0627\u0621',
                ),
              ),
              TextField(
                key: const Key('endorsementTaxField'),
                controller: _tax,
                keyboardType: numberKeyboard,
                decoration: const InputDecoration(
                  labelText:
                      '\u0641\u0631\u0642 \u0627\u0644\u0636\u0631\u064a\u0628\u0629',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('\u0625\u0644\u063a\u0627\u0621'),
        ),
        FilledButton(
          key: const Key('endorsementSubmitButton'),
          onPressed: _submit,
          child: const Text('\u062a\u0631\u062d\u064a\u0644'),
        ),
      ],
    );
  }
}

class _ReversalReasonDialog extends StatefulWidget {
  const _ReversalReasonDialog();

  @override
  State<_ReversalReasonDialog> createState() => _ReversalReasonDialogState();
}

class _ReversalReasonDialogState extends State<_ReversalReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          const Text('\u0639\u0643\u0633 \u0627\u0644\u0645\u0644\u062d\u0642'),
      content: TextField(
        key: const Key('endorsementReversalReasonField'),
        controller: _reason,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '\u0633\u0628\u0628 \u0627\u0644\u0639\u0643\u0633',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('\u0625\u0644\u063a\u0627\u0621'),
        ),
        FilledButton(
          key: const Key('endorsementReverseConfirm'),
          onPressed: () {
            final value = _reason.text.trim();
            if (value.isEmpty) return;
            Navigator.pop(context, value);
          },
          child: const Text(
              '\u062a\u0623\u0643\u064a\u062f \u0627\u0644\u0639\u0643\u0633'),
        ),
      ],
    );
  }
}
