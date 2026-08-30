// -----------------------------------------------------------------------------
// lib/features/cheques/services/cheque_endorsement_service.dart
// P0.008 — compatibility facade to the canonical lifecycle service
// -----------------------------------------------------------------------------

import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_accounting_service.dart';

class ChequeEndorsementService {
  ChequeEndorsementService._();

  static Future<Cheque> endorseCheque({
    required Cheque cheque,
    required String supplierPid,
    required DateTime endorsementDate,
  }) {
    final id = cheque.id;
    if (id == null) {
      throw StateError('Cheque id is required for endorsement.');
    }

    return ChequeAccountingService.endorseToSupplier(
      chequeId: id,
      supplierPid: supplierPid,
      endorsementDate: endorsementDate,
    );
  }
}
