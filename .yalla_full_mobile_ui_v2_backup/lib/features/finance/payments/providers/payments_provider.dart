// 📁 lib/features/finance/payments/providers/payments_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';

final paymentsProvider =
    StateNotifierProvider<PaymentsNotifier, AsyncValue<List<Payment>>>(
  (ref) => PaymentsNotifier(),
);

class PaymentsNotifier extends StateNotifier<AsyncValue<List<Payment>>> {
  PaymentsNotifier() : super(const AsyncLoading()) {
    loadPayments();
  }

  Future<void> loadPayments() async {
    state = const AsyncLoading();
    try {
      final payments = await PaymentService.getAll();
      state = AsyncValue.data(payments);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => loadPayments();

  Future<void> updatePayment(Payment updated) async {
    await PaymentService.update(updated);
    await loadPayments();
  }

  // تغيّر النوع إلى String لأن المعرفات لدينا نصية (ULID/UUID)
  Future<void> deletePayment(String id) async {
    await PaymentService.delete(id);
    await loadPayments();
  }
}
