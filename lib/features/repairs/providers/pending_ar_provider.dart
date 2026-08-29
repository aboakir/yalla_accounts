import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/models/accounts_receivable_entry.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';

/// يعيد كل قيود الذمم المرتبطة بملف إصلاح محدد،
/// لو بدك فقط غير المسدد استخدم:
///   ref.watch(pendingArProvider(repairId)).then((all) => all.where((e) => !e.isPaid).toList())
final pendingArProvider =
    FutureProvider.family<List<AccountsReceivableEntry>, String>(
        (ref, repairId) async {
  final svc = AccountsReceivableService.instance;
  final list = await svc.getEntriesByRepair(repairId);
  // مرتّبة من الأحدث للأقدم (لو الخدمة ما رتّبت)
  final sorted = [...list]..sort((a, b) {
      final ad = DateTime.tryParse((a.paidDate ?? a.date) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b.paidDate ?? b.date) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
  return sorted;
});
