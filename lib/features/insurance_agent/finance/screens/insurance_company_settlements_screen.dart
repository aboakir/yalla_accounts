import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/finance/services/insurance_company_settlement_service.dart';

typedef SettlementCompaniesLoader = Future<List<InsuranceSettlementCompany>>
    Function();
typedef SettlementRecentLoader
    = Future<List<InsuranceCompanySettlementSnapshot>> Function();
typedef SettlementPreviewer = Future<InsuranceCompanySettlementSnapshot>
    Function({
  required int companyId,
  required DateTime periodStart,
  required DateTime periodEnd,
});
typedef SettlementSaver = Future<InsuranceCompanySettlementSnapshot> Function({
  required int companyId,
  required DateTime periodStart,
  required DateTime periodEnd,
});
typedef SettlementPoster = Future<InsuranceCompanySettlementSnapshot> Function(
    String settlementId);
typedef SettlementPayer = Future<void> Function({
  required String operationId,
  required String settlementId,
  required double amount,
  required DateTime date,
  required String method,
});

class InsuranceCompanySettlementsScreen extends StatefulWidget {
  const InsuranceCompanySettlementsScreen({
    super.key,
    this.companiesLoader,
    this.recentLoader,
    this.previewer,
    this.saver,
    this.poster,
    this.payer,
  });

  final SettlementCompaniesLoader? companiesLoader;
  final SettlementRecentLoader? recentLoader;
  final SettlementPreviewer? previewer;
  final SettlementSaver? saver;
  final SettlementPoster? poster;
  final SettlementPayer? payer;

  @override
  State<InsuranceCompanySettlementsScreen> createState() =>
      _InsuranceCompanySettlementsScreenState();
}

class _InsuranceCompanySettlementsScreenState
    extends State<InsuranceCompanySettlementsScreen> {
  late Future<void> _initialFuture;
  List<InsuranceSettlementCompany> _companies = const [];
  List<InsuranceCompanySettlementSnapshot> _recent = const [];
  InsuranceCompanySettlementSnapshot? _preview;
  int? _companyId;
  late DateTime _periodStart;
  late DateTime _periodEnd;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodStart = DateTime(now.year, now.month, 1);
    _periodEnd = DateTime(now.year, now.month + 1, 0);
    _initialFuture = _load();
  }

  Future<void> _load() async {
    final companies = await (widget.companiesLoader?.call() ??
        InsuranceCompanySettlementService.companies());
    final recent = await (widget.recentLoader?.call() ??
        InsuranceCompanySettlementService.recent());
    if (!mounted) return;
    setState(() {
      _companies = companies;
      _recent = recent;
      _companyId ??= companies.isEmpty ? null : companies.first.id;
    });
  }

  Future<void> _refresh() async {
    setState(() => _initialFuture = _load());
    await _initialFuture;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(UserFacingError.message(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewSelected() async {
    final companyId = _companyId;
    if (companyId == null) return;
    await _run(() async {
      final snapshot = await (widget.previewer?.call(
            companyId: companyId,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
          ) ??
          InsuranceCompanySettlementService.preview(
            companyId: companyId,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
          ));
      if (mounted) setState(() => _preview = snapshot);
    });
  }

  Future<void> _saveDraft() async {
    final companyId = _companyId;
    if (companyId == null) return;
    await _run(() async {
      final snapshot = await (widget.saver?.call(
            companyId: companyId,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
          ) ??
          InsuranceCompanySettlementService.saveDraft(
            companyId: companyId,
            periodStart: _periodStart,
            periodEnd: _periodEnd,
          ));
      if (mounted) setState(() => _preview = snapshot);
      await _refresh();
    });
  }

  Future<void> _postDraft() async {
    final id = _preview?.settlementId;
    if (id == null || id.isEmpty) return;
    await _run(() async {
      final snapshot = await (widget.poster?.call(id) ??
          InsuranceCompanySettlementService.postDraft(id));
      if (mounted) setState(() => _preview = snapshot);
      await _refresh();
    });
  }

  Future<void> _payOutstanding() async {
    final snapshot = _preview;
    final id = snapshot?.settlementId;
    if (snapshot == null || id == null || snapshot.outstanding <= 0.005) return;
    final draft = await showDialog<_SettlementPaymentDraft>(
      context: context,
      builder: (_) => _SettlementPaymentDialog(maxAmount: snapshot.outstanding),
    );
    if (draft == null) return;
    await _run(() async {
      final operationId = 'UI:$id:${DateTime.now().microsecondsSinceEpoch}';
      if (widget.payer != null) {
        await widget.payer!(
          operationId: operationId,
          settlementId: id,
          amount: draft.amount,
          date: draft.date,
          method: draft.method,
        );
      } else {
        await InsuranceCompanySettlementService.paySettlement(
          operationId: operationId,
          settlementId: id,
          amount: draft.amount,
          date: draft.date,
          method: draft.method,
        );
      }
      final refreshed = await InsuranceCompanySettlementService.load(id);
      if (mounted) setState(() => _preview = refreshed);
      await _refresh();
    });
  }

  Future<void> _pickDate(bool start) async {
    final initial = start ? _periodStart : _periodEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _periodStart = picked;
        if (_periodEnd.isBefore(picked)) _periodEnd = picked;
      } else {
        _periodEnd = picked;
        if (_periodStart.isAfter(picked)) _periodStart = picked;
      }
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final date = intl.DateFormat('yyyy-MM-dd');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text('تسويات شركات التأمين'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: FutureBuilder<void>(
          future: _initialFuture,
          builder: (context, state) {
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                          'تعذر تحميل التسويات: ${UserFacingError.message(state.error!)}',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: _refresh,
                          child: const Text('إعادة المحاولة')),
                    ],
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSetupCard(context, date),
                  if (_preview != null) ...[
                    const SizedBox(height: 16),
                    _SettlementSnapshotCard(snapshot: _preview!),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'آخر التسويات',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_recent.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('لا توجد تسويات محفوظة بعد.'),
                      ),
                    )
                  else
                    ..._recent.map((item) => _recentTile(item, date)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSetupCard(BuildContext context, intl.DateFormat date) {
    final status = _preview?.status.toUpperCase();
    final canPost = status == 'DRAFT';
    final canPay = (status == 'POSTED' || status == 'PARTIAL') &&
        (_preview?.outstanding ?? 0) > 0.005;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('إنشاء تسوية',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _companyId,
              decoration: const InputDecoration(
                  labelText: 'شركة التأمين', border: OutlineInputBorder()),
              items: _companies
                  .map((company) => DropdownMenuItem<int>(
                      value: company.id, child: Text(company.name)))
                  .toList(growable: false),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                        _companyId = value;
                        _preview = null;
                      }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(true),
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text('من ${date.format(_periodStart)}'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('إلى ${date.format(_periodEnd)}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed:
                      _busy || _companyId == null ? null : _previewSelected,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('معاينة'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _companyId == null ? null : _saveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ مسودة'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !canPost ? null : _postDraft,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('ترحيل التسوية'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy || !canPay ? null : _payOutstanding,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('تسجيل دفعة'),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recentTile(
      InsuranceCompanySettlementSnapshot item, intl.DateFormat date) {
    return Card(
      child: ListTile(
        onTap: () => setState(() {
          _companyId = item.companyId;
          _periodStart = item.periodStart;
          _periodEnd = item.periodEnd;
          _preview = item;
        }),
        leading:
            const CircleAvatar(child: Icon(Icons.account_balance_outlined)),
        title: Text(item.companyName,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '${date.format(item.periodStart)} — ${date.format(item.periodEnd)} · ${item.status}'),
        trailing: Text(item.outstanding.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SettlementSnapshotCard extends StatelessWidget {
  const _SettlementSnapshotCard({required this.snapshot});
  final InsuranceCompanySettlementSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final money = intl.NumberFormat('#,##0.00');
    final metrics = <MapEntry<String, double>>[
      MapEntry('إجمالي البوالص', snapshot.grossPolicies),
      MapEntry('الإلغاءات/التخفيضات', snapshot.cancellations),
      MapEntry('العمولة', snapshot.commission),
      MapEntry('دفعات سابقة', snapshot.previousPayments),
      MapEntry('صافي المستحق', snapshot.payable),
      MapEntry('دفعات التسوية', snapshot.settlementPayments),
      MapEntry('المتبقي', snapshot.outstanding),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    snapshot.companyName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text(snapshot.status)),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics.map((entry) {
                return SizedBox(
                  width: 175,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key,
                              style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(
                            money.format(entry.value),
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            if (snapshot.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'الحركات الداخلة في التسوية (${snapshot.items.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettlementPaymentDraft {
  const _SettlementPaymentDraft(
      {required this.amount, required this.date, required this.method});
  final double amount;
  final DateTime date;
  final String method;
}

class _SettlementPaymentDialog extends StatefulWidget {
  const _SettlementPaymentDialog({required this.maxAmount});
  final double maxAmount;

  @override
  State<_SettlementPaymentDialog> createState() =>
      _SettlementPaymentDialogState();
}

class _SettlementPaymentDialogState extends State<_SettlementPaymentDialog> {
  late final TextEditingController _amount;
  DateTime _date = DateTime.now();
  String _method = 'CASH';

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: widget.maxAmount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('تسجيل دفعة تسوية'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    'المبلغ (الحد ${widget.maxAmount.toStringAsFixed(2)})',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: const InputDecoration(
                  labelText: 'طريقة الدفع', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('نقدي')),
                DropdownMenuItem(value: 'BANK', child: Text('بنك')),
              ],
              onChanged: (value) => setState(() => _method = value ?? 'CASH'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تاريخ الدفع'),
              subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(_date)),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickPaymentDate,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(onPressed: _submit, child: const Text('حفظ الدفعة')),
      ],
    );
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _submit() {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0 || value - widget.maxAmount > 0.005) return;
    Navigator.pop(
      context,
      _SettlementPaymentDraft(amount: value, date: _date, method: _method),
    );
  }
}
