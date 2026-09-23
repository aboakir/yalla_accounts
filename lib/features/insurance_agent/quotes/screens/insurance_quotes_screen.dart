import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';
import 'package:yalla_accounts/features/insurance_agent/master_data/services/insurance_master_data_service.dart';
import 'package:yalla_accounts/features/insurance_agent/quotes/services/insurance_quote_service.dart';

typedef InsuranceQuoteLoader = Future<List<InsuranceQuoteSummary>> Function();
typedef InsuranceQuoteItemLoader = Future<List<InsuranceQuoteItemRecord>>
    Function(String quoteId);
typedef InsuranceQuoteAcceptor = Future<void> Function(
    String quoteId, String itemId);
typedef InsuranceQuoteIssuer = Future<void> Function(
  String quoteId,
  String policyNumber,
  DateTime startDate,
  DateTime endDate,
);

class InsuranceQuotesScreen extends StatefulWidget {
  const InsuranceQuotesScreen({
    super.key,
    this.loader,
    this.itemLoader,
    this.acceptor,
    this.issuer,
  });

  final InsuranceQuoteLoader? loader;
  final InsuranceQuoteItemLoader? itemLoader;
  final InsuranceQuoteAcceptor? acceptor;
  final InsuranceQuoteIssuer? issuer;

  @override
  State<InsuranceQuotesScreen> createState() => _InsuranceQuotesScreenState();
}

class _InsuranceQuotesScreenState extends State<InsuranceQuotesScreen> {
  late Future<List<InsuranceQuoteSummary>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = widget.loader?.call() ?? InsuranceQuoteService.listQuotes();
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _future;
  }

  Future<List<InsuranceQuoteItemRecord>> _items(String quoteId) {
    return widget.itemLoader?.call(quoteId) ??
        InsuranceQuoteService.listQuoteItems(quoteId);
  }

  Future<void> _accept(String quoteId, String itemId) async {
    final acceptor = widget.acceptor;
    if (acceptor != null) {
      await acceptor(quoteId, itemId);
    } else {
      await InsuranceQuoteService.acceptQuote(quoteId: quoteId, itemId: itemId);
    }
  }

  Future<void> _issue(
    String quoteId,
    String policyNumber,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final issuer = widget.issuer;
    if (issuer != null) {
      await issuer(quoteId, policyNumber, startDate, endDate);
    } else {
      await InsuranceQuoteService.issueAcceptedQuote(
        quoteId: quoteId,
        policyNumber: policyNumber,
        startDate: startDate,
        endDate: endDate,
        postingDate: DateTime.now(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: const Key('insuranceQuotesScreen'),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Text(
              '\u0645\u0631\u0643\u0632 \u0627\u0644\u0639\u0631\u0648\u0636'),
          actions: [
            IconButton(
              key: const Key('quotesRefresh'),
              tooltip: '\u062a\u062d\u062f\u064a\u062b',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('newInsuranceQuote'),
          onPressed: _createQuote,
          icon: const Icon(Icons.add),
          label: const Text('\u0639\u0631\u0636 \u062c\u062f\u064a\u062f'),
        ),
        body: FutureBuilder<List<InsuranceQuoteSummary>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.error_outline,
                text:
                    '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0639\u0631\u0648\u0636 \u0627\u0644\u062a\u0623\u0645\u064a\u0646',
                onRetry: _refresh,
              );
            }
            final rows = snapshot.data ?? const <InsuranceQuoteSummary>[];
            if (rows.isEmpty) {
              return _MessageState(
                icon: Icons.request_quote_outlined,
                text:
                    '\u0644\u0627 \u062a\u0648\u062c\u062f \u0639\u0631\u0648\u0636 \u062a\u0623\u0645\u064a\u0646 \u0628\u0639\u062f',
                onRetry: _refresh,
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _QuoteCard(
                  quote: rows[index],
                  onOpen: () => _openQuote(rows[index]),
                  onIssue: rows[index].status == 'ACCEPTED'
                      ? () => _issueDialog(rows[index])
                      : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openQuote(InsuranceQuoteSummary quote) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FutureBuilder<List<InsuranceQuoteItemRecord>>(
        future: _items(quote.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
                height: 260, child: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return const SizedBox(
              height: 220,
              child: Center(
                  child: Text(
                      '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u062a\u0641\u0627\u0635\u064a\u0644 \u0627\u0644\u0639\u0631\u0636')),
            );
          }
          final items = snapshot.data ?? const <InsuranceQuoteItemRecord>[];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${quote.quoteNumber} - ${quote.partyName}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return ListTile(
                          key: Key('quoteItem-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.companyName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${item.productName ?? '\u0628\u062f\u0648\u0646 \u0645\u0646\u062a\u062c'}\n'
                            '\u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639: ${item.finalPrice.toStringAsFixed(2)} - '
                            '\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621: ${item.purchasePrice.toStringAsFixed(2)}',
                          ),
                          isThreeLine: true,
                          trailing: quote.status == 'DRAFT'
                              ? FilledButton.tonal(
                                  key: Key('acceptQuoteItem-${item.id}'),
                                  onPressed: () async {
                                    try {
                                      await _accept(quote.id, item.id);
                                      if (!sheetContext.mounted) return;
                                      Navigator.pop(sheetContext);
                                      await _refresh();
                                    } catch (_) {
                                      if (!sheetContext.mounted) return;
                                      ScaffoldMessenger.of(sheetContext)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                '\u062a\u0639\u0630\u0631 \u0642\u0628\u0648\u0644 \u0639\u0631\u0636 \u0627\u0644\u0634\u0631\u0643\u0629.')),
                                      );
                                    }
                                  },
                                  child: const Text(
                                      '\u0627\u0639\u062a\u0645\u0627\u062f'),
                                )
                              : _StatusChip(status: item.status),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _issueDialog(InsuranceQuoteSummary quote) async {
    final policyNumber = TextEditingController();
    var start = DateTime.now();
    var end = DateTime(start.year + 1, start.month, start.day)
        .subtract(const Duration(days: 1));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AdaptiveAlertDialog(
          title: const Text(
              '\u0625\u0635\u062f\u0627\u0631 \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('quotePolicyNumber'),
                  controller: policyNumber,
                  decoration: const InputDecoration(
                      labelText:
                          '\u0631\u0642\u0645 \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629 \u0644\u062f\u0649 \u0634\u0631\u0643\u0629 \u0627\u0644\u062a\u0623\u0645\u064a\u0646'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text(
                      '\u0628\u062f\u0627\u064a\u0629 \u0627\u0644\u062a\u063a\u0637\u064a\u0629'),
                  subtitle: Text(_date(start)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: start,
                    );
                    if (picked != null) setLocal(() => start = picked);
                  },
                ),
                ListTile(
                  title: const Text(
                      '\u0646\u0647\u0627\u064a\u0629 \u0627\u0644\u062a\u063a\u0637\u064a\u0629'),
                  subtitle: Text(_date(end)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: start,
                      lastDate: DateTime(2100),
                      initialDate: end.isBefore(start) ? start : end,
                    );
                    if (picked != null) setLocal(() => end = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('\u0625\u0644\u063a\u0627\u0621')),
            FilledButton(
              key: const Key('confirmQuoteIssue'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('\u0625\u0635\u062f\u0627\u0631'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final number = policyNumber.text.trim();
    if (number.isEmpty || end.isBefore(start)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u0623\u062f\u062e\u0644 \u0631\u0642\u0645 \u0628\u0648\u0644\u064a\u0635\u0629 \u0635\u062d\u064a\u062d \u0648\u0641\u062a\u0631\u0629 \u062a\u063a\u0637\u064a\u0629 \u0635\u062d\u064a\u062d\u0629.')),
      );
      return;
    }
    try {
      await _issue(quote.id, number, start, end);
      if (mounted) await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u062a\u0639\u0630\u0631 \u0625\u0635\u062f\u0627\u0631 \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629.')),
      );
    }
  }

  Future<void> _createQuote() async {
    List<InsuranceProspectRecord> prospects;
    List<InsuranceCompanyRecord> companies;
    try {
      prospects = await InsuranceCrmService.listProspects();
      companies = (await InsuranceMasterDataService.listCompanies())
          .where((e) => e.isActive)
          .toList();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u062a\u0639\u0630\u0631 \u062a\u062d\u0645\u064a\u0644 \u0628\u064a\u0627\u0646\u0627\u062a \u0627\u0644\u0639\u0631\u0636.')),
      );
      return;
    }
    if (!mounted) return;
    if (prospects.isEmpty || companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u064a\u0644\u0632\u0645 \u0648\u062c\u0648\u062f \u0639\u0645\u064a\u0644 \u0645\u062d\u062a\u0645\u0644 \u0648\u0634\u0631\u0643\u0629 \u062a\u0623\u0645\u064a\u0646 \u0646\u0634\u0637\u0629 \u0623\u0648\u0644\u0627\u064b.')),
      );
      return;
    }

    final quoteNo = TextEditingController();
    final purchase = TextEditingController();
    final sale = TextEditingController();
    final premium = TextEditingController();
    InsuranceProspectRecord prospect = prospects.first;
    InsuranceCompanyRecord company = companies.first;
    List<InsuranceProductRecord> products =
        await InsuranceMasterDataService.listProducts(companyId: company.id);
    if (!mounted) return;
    InsuranceProductRecord? product =
        products.where((e) => e.isActive).firstOrNull;
    double commission =
        product?.defaultCommissionRate ?? company.defaultCommissionRate;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AdaptiveAlertDialog(
          title: const Text(
              '\u0639\u0631\u0636 \u062a\u0623\u0645\u064a\u0646 \u062c\u062f\u064a\u062f'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: quoteNo,
                      decoration: const InputDecoration(
                          labelText:
                              '\u0631\u0642\u0645 \u0627\u0644\u0639\u0631\u0636')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<InsuranceProspectRecord>(
                    initialValue: prospect,
                    decoration: const InputDecoration(
                        labelText:
                            '\u0627\u0644\u0639\u0645\u064a\u0644 / \u0627\u0644\u0645\u0633\u062a\u0647\u062f\u0641'),
                    items: prospects
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e.name)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setLocal(() => prospect = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<InsuranceCompanyRecord>(
                    initialValue: company,
                    decoration: const InputDecoration(
                        labelText:
                            '\u0634\u0631\u0643\u0629 \u0627\u0644\u062a\u0623\u0645\u064a\u0646'),
                    items: companies
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text(e.name)))
                        .toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      company = value;
                      products = await InsuranceMasterDataService.listProducts(
                          companyId: company.id);
                      if (!dialogContext.mounted) return;
                      setLocal(() {
                        product = products.where((e) => e.isActive).firstOrNull;
                        commission = product?.defaultCommissionRate ??
                            company.defaultCommissionRate;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<InsuranceProductRecord?>(
                    value: product,
                    decoration: const InputDecoration(
                        labelText: '\u0627\u0644\u0645\u0646\u062a\u062c'),
                    items: <DropdownMenuItem<InsuranceProductRecord?>>[
                      const DropdownMenuItem(
                          value: null,
                          child: Text(
                              '\u0628\u062f\u0648\u0646 \u0645\u0646\u062a\u062c \u0645\u062d\u062f\u062f')),
                      ...products.where((e) => e.isActive).map((e) =>
                          DropdownMenuItem(value: e, child: Text(e.name))),
                    ],
                    onChanged: (value) => setLocal(() {
                      product = value;
                      commission = value?.defaultCommissionRate ??
                          company.defaultCommissionRate;
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: premium,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText:
                              '\u0627\u0644\u0642\u0633\u0637 \u0627\u0644\u0623\u0633\u0627\u0633\u064a')),
                  TextField(
                      controller: purchase,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText:
                              '\u0633\u0639\u0631 \u0627\u0644\u0634\u0631\u0627\u0621')),
                  TextField(
                      controller: sale,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText:
                              '\u0633\u0639\u0631 \u0627\u0644\u0628\u064a\u0639')),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '\u0646\u0633\u0628\u0629 \u0627\u0644\u0639\u0645\u0648\u0644\u0629: ${commission.toStringAsFixed(2)}%'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('\u0625\u0644\u063a\u0627\u0621')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                    '\u062d\u0641\u0638 \u0627\u0644\u0639\u0631\u0636')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final p = double.tryParse(premium.text.trim()) ?? -1;
    final buy = double.tryParse(purchase.text.trim()) ?? -1;
    final sell = double.tryParse(sale.text.trim()) ?? -1;
    if (quoteNo.text.trim().isEmpty || p < 0 || buy < 0 || sell <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u062a\u062d\u0642\u0642 \u0645\u0646 \u0631\u0642\u0645 \u0627\u0644\u0639\u0631\u0636 \u0648\u0627\u0644\u0623\u0633\u0639\u0627\u0631.')),
      );
      return;
    }
    try {
      await InsuranceQuoteService.createQuote(
        quoteNumber: quoteNo.text.trim(),
        partyId: prospect.partyId,
        prospectId: prospect.id,
        items: [
          InsuranceQuoteItemInput(
            companyId: company.id,
            productId: product?.id,
            premium: p,
            purchasePrice: buy,
            salePrice: sell,
            commissionRate: commission,
          ),
        ],
      );
      if (mounted) await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                '\u062a\u0639\u0630\u0631 \u062d\u0641\u0638 \u0639\u0631\u0636 \u0627\u0644\u062a\u0623\u0645\u064a\u0646.')),
      );
    }
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.onOpen, this.onIssue});

  final InsuranceQuoteSummary quote;
  final VoidCallback onOpen;
  final VoidCallback? onIssue;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('quoteCard-${quote.id}'),
      child: ListTile(
        onTap: onOpen,
        leading: const CircleAvatar(child: Icon(Icons.request_quote_outlined)),
        title: Text('${quote.quoteNumber} - ${quote.partyName}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '\u0627\u0644\u062d\u0627\u0644\u0629: ${_quoteStatus(quote.status)} - \u0639\u0631\u0648\u0636 \u0627\u0644\u0634\u0631\u0643\u0627\u062a: ${quote.itemCount}\n${_date(quote.requestedAt)}'),
        isThreeLine: true,
        trailing: onIssue == null
            ? _StatusChip(status: quote.status)
            : FilledButton.tonal(
                key: Key('issueQuote-${quote.id}'),
                onPressed: onIssue,
                child: const Text('\u0625\u0635\u062f\u0627\u0631'),
              ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => Chip(label: Text(_quoteStatus(status)));
}

class _MessageState extends StatelessWidget {
  const _MessageState(
      {required this.icon, required this.text, required this.onRetry});
  final IconData icon;
  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 100),
          Icon(icon, size: 64),
          const SizedBox(height: 16),
          Center(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600))),
          const SizedBox(height: 12),
          Center(
              child: FilledButton.tonal(
                  onPressed: onRetry,
                  child: const Text(
                      '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'))),
        ],
      );
}

String _quoteStatus(String status) {
  const labels = <String, String>{
    'DRAFT': '\u0645\u0633\u0648\u062f\u0629',
    'ACCEPTED': '\u0645\u0642\u0628\u0648\u0644',
    'ISSUED':
        '\u0635\u062f\u0631\u062a \u0627\u0644\u0628\u0648\u0644\u064a\u0635\u0629',
    'OFFERED': '\u0645\u0639\u0631\u0648\u0636',
    'DECLINED': '\u0645\u0631\u0641\u0648\u0636',
  };
  return labels[status] ?? status;
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
