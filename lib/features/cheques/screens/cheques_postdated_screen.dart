import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_maturity_service.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesPostdatedScreen extends StatelessWidget {
  const ChequesPostdatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات المستحقة والآجلة',
      currentRoute: AppRoutes.chequesPostdated,
      emptyText: 'لا توجد شيكات مستحقة أو آجلة حاليًا',
      predicate: (c) {
        final classification = ChequeMaturityService.classify(c);
        return {
          ChequeMaturityClass.dueToday,
          ChequeMaturityClass.dueSoon,
          ChequeMaturityClass.postDated,
          ChequeMaturityClass.overdue,
        }.contains(classification);
      },
    );
  }
}
