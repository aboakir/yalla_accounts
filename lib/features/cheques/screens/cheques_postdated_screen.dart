import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_maturity_service.dart';

class ChequesPostdatedScreen extends StatelessWidget {
  const ChequesPostdatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات المستحقة والآجلة',
      currentRoute: AppRoutes.chequesPostdated,
      predicate: (c) {
        final cls = ChequeMaturityService.classify(c);
        return cls == ChequeMaturityClass.dueToday ||
            cls == ChequeMaturityClass.dueSoon ||
            cls == ChequeMaturityClass.overdue ||
            cls == ChequeMaturityClass.postDated;
      },
      emptyMessage: 'لا توجد شيكات مستحقة أو آجلة',
    );
  }
}
