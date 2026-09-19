import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_dashboard_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

class ChequesDashboardScreen extends StatefulWidget {
  const ChequesDashboardScreen({super.key});

  @override
  State<ChequesDashboardScreen> createState() => _ChequesDashboardScreenState();
}

class _ChequesDashboardScreenState extends State<ChequesDashboardScreen> {
  final _bank = TextEditingController();
  final _party = TextEditingController();
  final _currency = TextEditingController();
  late Future<ChequeDashboardData> _future;
  DateTime? _from;
  DateTime? _to;
  ChequeStatus? _status;
  ChequeDirection? _direction;
  String _period = 'month';

  @override
  void initState() {
    super.initState();
    _setPeriod('month', refresh: false);
    _reload();
  }

  @override
  void dispose() {
    _bank.dispose();
    _party.dispose();
    _currency.dispose();
    super.dispose();
  }

  void _reload() {
    _future = ChequeDashboardService.load(
      from: _from,
      to: _to,
      bank: _bank.text,
      party: _party.text,
      currency: _currency.text,
      status: _status,
      direction: _direction,
    );
  }

  void _setPeriod(String period, {bool refresh = true}) {
    final now = DateTime.now();
    _period = period;
    if (period == 'today') {
      _from = DateTime(now.year, now.month, now.day);
      _to = _from;
    } else if (period == 'week') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      _from = DateTime(start.year, start.month, start.day);
      _to = DateTime(now.year, now.month, now.day);
    } else if (period == 'month') {
      _from = DateTime(now.year, now.month, 1);
      _to = DateTime(now.year, now.month + 1, 0);
    }
    if (refresh && mounted) setState(_reload);
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : DateTimeRange(start: now, end: now),
    );
    if (range == null || !mounted) return;
    setState(() {
      _period = 'custom';
      _from = range.start;
      _to = range.end;
      _reload();
    });
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
          : const YallaSidebar(currentRoute: AppRoutes.chequesDashboard),
      body: AdaptiveRow(
        children: [
          if (desktop)
            const YallaSidebar(currentRoute: AppRoutes.chequesDashboard),
          Expanded(
            child: FutureBuilder<ChequeDashboardData>(
              future: _future,
              builder: (context, snap) {
                return ListView(
                  padding: const EdgeInsets.all(18),
                  children: [
                    const Text(
                      'لوحة الشيكات',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _filters(),
                    const SizedBox(height: 16),
                    if (snap.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (snap.hasError)
                      Text(
                        UserFacingError.message(snap.error!),
                        style: const TextStyle(color: Colors.red),
                      )
                    else
                      _metrics(snap.data!),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _periodButton('اليوم', 'today'),
                _periodButton('أسبوع', 'week'),
                _periodButton('شهر', 'month'),
                ChoiceChip(
                  label: const Text('فترة مخصصة'),
                  selected: _period == 'custom',
                  onSelected: (_) => _pickCustom(),
                ),
                if (_from != null && _to != null)
                  Chip(
                    label: Text(
                      '${DateFormat('yyyy-MM-dd').format(_from!)} → '
                      '${DateFormat('yyyy-MM-dd').format(_to!)}',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _textFilter(_bank, 'البنك'),
                _textFilter(_party, 'العميل / المورد / الطرف'),
                _textFilter(_currency, 'العملة'),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<ChequeDirection?>(
                    value: _direction,
                    decoration: const InputDecoration(labelText: 'الاتجاه'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('الكل')),
                      DropdownMenuItem(
                        value: ChequeDirection.received,
                        child: Text('وارد'),
                      ),
                      DropdownMenuItem(
                        value: ChequeDirection.issued,
                        child: Text('صادر'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      _direction = v;
                      _reload();
                    }),
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<ChequeStatus?>(
                    value: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الحالة'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      for (final status in ChequeStatus.values)
                        if (status != ChequeStatus.pending)
                          DropdownMenuItem(
                            value: status,
                            child: Text(_statusLabel(status)),
                          ),
                    ],
                    onChanged: (v) => setState(() {
                      _status = v;
                      _reload();
                    }),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodButton(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _period == value,
      onSelected: (_) => _setPeriod(value),
    );
  }

  Widget _textFilter(TextEditingController controller, String label) {
    return SizedBox(
      width: 210,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => setState(_reload),
          ),
        ),
        onSubmitted: (_) => setState(_reload),
      ),
    );
  }

  Widget _metrics(ChequeDashboardData data) {
    final items = <(String, ChequeMetric, IconData)>[
      ('إجمالي الشيكات', data.total, Icons.receipt_long),
      ('وارد — محتفظ به', data.receivedHeld, Icons.inventory_2_outlined),
      ('وارد — مودع', data.receivedDeposited, Icons.account_balance),
      ('وارد — محصل', data.receivedCollected, Icons.verified_outlined),
      ('وارد — راجع', data.receivedReturned, Icons.undo),
      ('وارد — مستحق قريبًا', data.receivedDueSoon, Icons.schedule),
      ('صادر — صادر', data.issuedOpen, Icons.outbox_outlined),
      ('صادر — مسلّم/مقدم', data.issuedDelivered, Icons.send_outlined),
      ('صادر — مستحق قريبًا', data.issuedDueSoon, Icons.event),
      ('صادر — مصروف', data.issuedCleared, Icons.check_circle_outline),
      ('صادر — ملغى', data.issuedCancelled, Icons.cancel_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = MediaQuery.sizeOf(context).width;
        final grid = viewportWidth >= 1024 ? 4 : 2;
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.count(
          crossAxisCount: grid,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: 162 + (textScale > 1 ? (textScale - 1) * 80 : 0),
          children: [
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$3),
                      const SizedBox(height: 6),
                      Text(item.$1,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text(
                        'عدد: ${item.$2.count}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('القيمة: ${_money(item.$2.amount)}'),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _money(double value) => NumberFormat('#,##0.00', 'ar').format(value);

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
