import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

/// P12 collection queue = deposited incoming cheques waiting for bank result.
class ChequesCollectionScreen extends StatefulWidget {
  const ChequesCollectionScreen({super.key});

  @override
  State<ChequesCollectionScreen> createState() =>
      _ChequesCollectionScreenState();
}

class _ChequesCollectionScreenState extends State<ChequesCollectionScreen> {
  final _service = ChequeService();
  final _money = NumberFormat('#,##0.00', 'ar');
  final _date = DateFormat('yyyy-MM-dd');
  late Future<List<Cheque>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = _service.fetchFiltered(status: ChequeStatus.deposited);
  }

  Future<void> _transition(Cheque cheque, ChequeStatus status) async {
    if (cheque.id == null) return;
    String? reason;
    if (status == ChequeStatus.returned) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AdaptiveAlertDialog(
          title: const Text('إرجاع الشيك'),
          content: TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'سبب الإرجاع')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('تأكيد')),
          ],
        ),
      );
      if (ok != true) {
        controller.dispose();
        return;
      }
      reason = controller.text.trim();
      controller.dispose();
    }
    try {
      await _service.transitionStatus(
          chequeId: cheque.id!, status: status, reason: reason);
      if (!mounted) return;
      setState(_reload);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر تحديث الشيك: ${UserFacingError.message(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الشيكات قيد التحصيل')),
      drawer: desktop
          ? null
          : const YallaSidebar(currentRoute: AppRoutes.chequesCollection),
      body: AdaptiveRow(children: [
        if (desktop)
          const YallaSidebar(currentRoute: AppRoutes.chequesCollection),
        Expanded(
          child: FutureBuilder<List<Cheque>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('تعذر تحميل الشيكات: ${snap.error}'));
              }
              final rows = snap.data ?? const <Cheque>[];
              if (rows.isEmpty) {
                return const Center(
                    child: Text('لا توجد شيكات مودعة قيد التحصيل'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final c = rows[i];
                  return Card(
                    child: ListTile(
                      title: Text(
                          'شيك ${c.chequeNo} — ${_money.format(c.amount)}'),
                      subtitle: Text(
                          '${c.bankName} • استحقاق ${_date.format(c.dueDate)}'),
                      trailing: Wrap(spacing: 6, children: [
                        FilledButton.tonal(
                            onPressed: () =>
                                _transition(c, ChequeStatus.collected),
                            child: const Text('تم التحصيل')),
                        OutlinedButton(
                            onPressed: () =>
                                _transition(c, ChequeStatus.returned),
                            child: const Text('راجع')),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
