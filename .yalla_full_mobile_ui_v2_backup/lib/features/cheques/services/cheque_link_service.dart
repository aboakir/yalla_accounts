// -----------------------------------------------------------------------------
// lib/features/cheques/services/cheque_link_service.dart
// P0.008 — legacy compatibility gate
// -----------------------------------------------------------------------------

import 'package:yalla_accounts/features/cheques/models/cheque.dart';

class ChequeLinkService {
  ChequeLinkService._();

  static Never _blocked() {
    throw StateError(
      'Legacy cheque-to-payment auto-generation is disabled by P0.008. '
      'Create receipts through PaymentService and payment vouchers through '
      'VoucherPaymentService so cheque + business document + GL are atomic.',
    );
  }

  static Future<void> addChequePayment(Cheque cheque) async => _blocked();

  static Future<void> updateChequePayment({
    required Cheque oldCheque,
    required Cheque newCheque,
  }) async =>
      _blocked();

  static Future<void> deleteChequePayment(Cheque cheque) async => _blocked();
}
