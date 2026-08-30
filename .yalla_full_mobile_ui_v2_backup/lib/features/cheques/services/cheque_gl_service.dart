// -----------------------------------------------------------------------------
// lib/features/cheques/services/cheque_gl_service.dart
// P0.008 — legacy GL gate
// -----------------------------------------------------------------------------

import 'package:yalla_accounts/features/cheques/models/cheque.dart';

class ChequeGLService {
  ChequeGLService._();

  static Never _blocked() {
    throw StateError(
      'Legacy ChequeGLService is disabled by P0.008. '
      'Use ChequeAccountingService through the canonical voucher/payment '
      'and cheque lifecycle flows.',
    );
  }

  static Future<int> postCheque(Cheque c) async => _blocked();

  static Future<void> reverseCheque(String uuid) async => _blocked();

  static Future<void> postStatusGL({
    required Cheque cheque,
    required ChequeStatus status,
  }) async =>
      _blocked();
}
