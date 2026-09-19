import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_details_screen.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_trace_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

typedef ChequePredicate = bool Function(Cheque cheque);

class ChequeFilteredScreen extends StatefulWidget {
  const ChequeFilteredScreen({
    super.key,
    required this.title,
    required this.currentRoute,
    required this.predicate,
    this.emptyMessage = 'لا توجد شيكات مطابقة',
  });

  final String title;
  final String currentRoute;
  final ChequePredicate predicate;
  final String emptyMessage;

  @override
  State<ChequeFilteredScreen> createState() => _ChequeFilteredScreenState();
}

class _ChequeFilteredScreenState extends State<ChequeFilteredScreen> {
  final _search = TextEditingController();
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');
  late Future<List<Cheque>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _future = ChequeTraceService.search(_search.text).then(
      (rows) => rows.where(widget.predicate).toList(),
    );
  }

  Future<void> _open(Cheque cheque) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChequeDetailsScreen(cheque: cheque)),
    );
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      drawer: desktop ? null : YallaSidebar(currentRoute: widget.currentRoute),
      body: AdaptiveRow(
        children: [
          if (desktop) YallaSidebar(currentRoute: widget.currentRoute),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                      labelText:
                          'بحث برقم الشيك، الطرف، البنك، السند، الملف أو الفاتورة',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (_) => setState(_reload),
                  ),
                ),
                Expanded(
                  child: FutureBuilder<List<Cheque>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                            child: Text('تعذر تحميل الشيكات: ${snap.error}'));
                      }
                      final rows = snap.data ?? const <Cheque>[];
                      if (rows.isEmpty) {
                        return Center(child: Text(widget.emptyMessage));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final c = rows[i];
                          return Card(
                            child: ListTile(
                              onTap: () => _open(c),
                              leading: Icon(
                                c.direction == ChequeDirection.received
                                    ? Icons.call_received
                                    : Icons.call_made,
                              ),
                              title: Text(
                                  'شيك ${c.chequeNo} — ${_money.format(c.amount)} ${c.currency}'),
                              subtitle: Text(
                                '${c.direction == ChequeDirection.received ? c.drawerName : (c.recipientName ?? c.drawerName)} • '
                                '${c.bankName} • استحقاق ${_date.format(c.dueDate)} • ${_status(c.status)}',
                              ),
                              trailing: const Icon(Icons.chevron_left),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _status(ChequeStatus status) {
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
        return 'مصروف';
      case ChequeStatus.returned:
        return 'راجع';
      case ChequeStatus.cancelled:
        return 'ملغى';
    }
  }
}
