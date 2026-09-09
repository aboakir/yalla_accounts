import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/financial_period_filter.dart';
import '../services/party_report_service.dart';
import '../pdf/party_detailed_pdf.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import '../services/party_financial_service.dart';

class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key});
  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  List<PartyBalanceSummary> _rows = [];
  bool _loading = true;
  String _query = '';
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PartyFinancialService.balances();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link(PartyBalanceSummary party) async {
    final candidates = _rows
        .where((p) => party.isCustomer
            ? p.isSupplier && !p.isCustomer
            : p.isCustomer && !p.isSupplier)
        .toList();
    final chosen = await showDialog<PartyBalanceSummary>(
        context: context,
        builder: (ctx) => Dialog(
                child: SizedBox(
              width: 500,
              height: 440,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                        'اختر سجل ${party.isCustomer ? 'المورد' : 'العميل'} لنفس الجهة')),
                Expanded(
                    child: candidates.isEmpty
                        ? const Center(child: Text('لا توجد سجلات متاحة للربط'))
                        : ListView(
                            children: candidates
                                .map((p) => ListTile(
                                      title: Text(p.displayName),
                                      subtitle: Text(
                                          '${p.isSupplier ? 'مورد' : 'عميل'} · ${p.supplierLegacyId ?? p.customerLegacyId}'),
                                      onTap: () => Navigator.pop(ctx, p),
                                    ))
                                .toList())),
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء')),
              ]),
            )));
    if (chosen == null || !mounted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AdaptiveAlertDialog(
              title: const Text('تأكيد هوية الجهة'),
              content: Text(
                  'ربط «${party.displayName}» مع «${chosen.displayName}» باعتبارهما نفس الشخص أو الشركة؟ سيجمع الكشف الحركات دون تسديد أو مقاصة للفواتير.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ربط السجلين'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      final db = await DBService.database;
      await db.transaction((txn) =>
          PartyFinancialService.linkCustomerAndSupplier(
              customerId: party.customerLegacyId ?? chosen.customerLegacyId!,
              supplierId: party.supplierLegacyId ?? chosen.supplierLegacyId!,
              executor: txn));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر الربط: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows
        .where(
            (p) => p.displayName.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('الجهات وكشوف الحساب'), actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        IconButton(
            tooltip: 'إضافة جهة',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PartyFormScreen()));
              if (mounted) await _load();
            }),
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
                decoration: const InputDecoration(
                    labelText: 'بحث باسم الجهة',
                    prefixIcon: Icon(Icons.search)),
                onChanged: (v) => setState(() => _query = v))),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        itemBuilder: (_, i) {
                          final p = rows[i];
                          return Card(
                              child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(p.displayName,
                                            style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold)),
                                        Text(p.isCustomerAndSupplier
                                            ? 'عميل ومورد'
                                            : p.isCustomer
                                                ? 'عميل'
                                                : 'مورد'),
                                        const SizedBox(height: 8),
                                        Text(
                                            'لك: ${MoneyFormatter.format(p.receivableBalance)}'),
                                        Text(
                                            'عليك: ${MoneyFormatter.format(p.payableBalance)}'),
                                        Text(
                                            'الصافي: ${MoneyFormatter.format((p.receivableBalance - p.payableBalance).abs())} ${p.receivableBalance >= p.payableBalance ? 'لصالحك' : 'عليك'}'),
                                        Wrap(spacing: 8, children: [
                                          TextButton.icon(
                                              icon: const Icon(
                                                  Icons.receipt_long),
                                              label: const Text('كشف شامل'),
                                              onPressed: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                      builder: (_) =>
                                                          PartyStatementScreen(
                                                              party: p)))),
                                          if (!p.isCustomerAndSupplier)
                                            TextButton.icon(
                                                icon: const Icon(Icons.link),
                                                label: const Text(
                                                    'ربط بعميل / مورد موجود'),
                                                onPressed: () => _link(p)),
                                        ]),
                                      ])));
                        },
                      )),
      ]),
    );
  }
}

class PartyStatementScreen extends StatefulWidget {
  const PartyStatementScreen({super.key, required this.party});
  final PartyBalanceSummary party;
  @override
  State<PartyStatementScreen> createState() => _PartyStatementScreenState();
}

class _PartyStatementScreenState extends State<PartyStatementScreen> {
  PartyLedgerStatement? _statement;
  DateTimeRange? _range;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _statement = null;
      _error = null;
    });
    try {
      final p = widget.party;
      final statement = await PartyFinancialService.statement(
          role: p.isCustomer ? 'CUSTOMER' : 'SUPPLIER',
          legacyId: p.customerLegacyId ?? p.supplierLegacyId!,
          combined: true,
          from: _range?.start,
          to: _range?.end);
      if (mounted) setState(() => _statement = statement);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _date(DateTime d) => d.toIso8601String().split('T').first;
  String _balance(double n) =>
      '${MoneyFormatter.format(n.abs())} ${n >= 0 ? 'لك' : 'عليك'}';
  bool _exporting = false;
  Future<void> _pdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final p = widget.party;
      final report = await PartyReportService.load(
          role: p.isCustomer ? 'CUSTOMER' : 'SUPPLIER',
          legacyId: p.customerLegacyId ?? p.supplierLegacyId!,
          from: _range?.start,
          to: _range?.end);
      final bytes = await PartyDetailedPdf.generate(report,
          period: _range == null
              ? 'كل التواريخ'
              : _date(_range!.start) + ' — ' + _date(_range!.end));
      await YallaPdfService.saveAndOpen(
          bytes: bytes,
          fileName: 'Party_Detailed_' +
              DateTime.now().millisecondsSinceEpoch.toString() +
              '.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر تصدير الكشف: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _statement;
    return Scaffold(
        appBar:
            AppBar(title: Text('كشف: ${widget.party.displayName}'), actions: [
          IconButton(
              tooltip: 'كشف PDF تفصيلي',
              onPressed: s == null || _exporting ? null : _pdf,
              icon: const Icon(Icons.picture_as_pdf)),
          IconButton(
              tooltip: 'تحديث',
              onPressed: _load,
              icon: const Icon(Icons.refresh)),
        ]),
        body: Column(children: [
          Wrap(children: [
            FinancialPeriodFilter(
                from: _range?.start,
                to: _range?.end,
                onChanged: (range) {
                  _range = range;
                  _load();
                }),
            TextButton.icon(
                icon: const Icon(Icons.date_range),
                label: Text(_range == null
                    ? 'كل التواريخ'
                    : '${_date(_range!.start)} — ${_date(_range!.end)}'),
                onPressed: () async {
                  final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (range != null && mounted) {
                    _range = range;
                    await _load();
                  }
                }),
            if (_range != null)
              IconButton(
                  onPressed: () {
                    _range = null;
                    _load();
                  },
                  icon: const Icon(Icons.clear))
          ]),
          const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                  'مدين يزيد ما لك، ودائن يزيد ما عليك. الصافي للمقارنة ولا يُعدّ مقاصة أو سدادًا.')),
          if (s != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                    'افتتاحي: ${_balance(s.openingBalance)}\nختامي: ${_balance(s.closingBalance)}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
          Expanded(
              child: _error != null
                  ? Center(child: Text(_error!))
                  : s == null
                      ? const Center(child: CircularProgressIndicator())
                      : s.lines.isEmpty
                          ? const Center(child: Text('لا توجد حركات في الفترة'))
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: s.lines.length,
                              itemBuilder: (_, i) {
                                final l = s.lines[i];
                                return Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                  '${_date(l.date)} · ${l.description}'),
                                              if (l.sourceNumber.isNotEmpty)
                                                Text(
                                                    'المستند: ${l.sourceNumber}'),
                                              Text(
                                                  'مدين: ${MoneyFormatter.format(l.debit)}    دائن: ${MoneyFormatter.format(l.credit)}'),
                                              Text(
                                                  'الرصيد: ${_balance(l.runningBalance)}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                            ])));
                              })),
        ]));
  }
}

class PartyFormScreen extends StatefulWidget {
  const PartyFormScreen({super.key});
  @override
  State<PartyFormScreen> createState() => _PartyFormScreenState();
}

class _PartyFormScreenState extends State<PartyFormScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _customer = true;
  bool _supplier = false;
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_key.currentState!.validate()) return;
    if (!_customer && !_supplier) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر عميلًا أو موردًا أو كليهما')));
      return;
    }
    setState(() => _saving = true);
    try {
      await PartyFinancialService.createParty(
          name: _name.text,
          phone: _phone.text,
          address: _address.text,
          customer: _customer,
          supplier: _supplier);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('إضافة جهة')),
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
                key: _key,
                child: Column(children: [
                  TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'اسم الشخص أو الشركة'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null),
                  TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'الهاتف')),
                  TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(labelText: 'العنوان')),
                  const SizedBox(height: 16),
                  const Text('يمكن أن تكون الجهة عميلًا وموردًا في الوقت نفسه'),
                  CheckboxListTile(
                      title: const Text('عميل — أبيع له أو أصلح مركبته'),
                      value: _customer,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _customer = v!)),
                  CheckboxListTile(
                      title: const Text('مورد — أشتري منه'),
                      value: _supplier,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _supplier = v!)),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ الجهة')),
                ]))),
      );
}
