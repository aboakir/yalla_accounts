// 📁 lib/features/repairs/providers/pending_ar_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/models/accounts_receivable_entry.dart';
import 'package:yalla_accounts/features/finance/services/accounts_receivable_service.dart';

/// هذا الموفر يعيد قائمة الدفعات (كلها) لإصلاح معين
/// وللحصول على الدفعات غير المسددة فقط:
///   ref.watch(pendingArProvider(repairId)).then((all) => all.where((e) => !e.isPaid))
final pendingArProvider = FutureProvider.family<List<AccountsReceivableEntry>, String>(
  (ref, repairId) => AccountsReceivableService.instance.getEntriesByRepair(repairId),
);
