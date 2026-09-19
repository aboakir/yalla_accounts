import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesIncomingScreen extends StatelessWidget {
  const ChequesIncomingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات الواردة',
      currentRoute: AppRoutes.chequesIncoming,
      emptyText: 'لا توجد شيكات واردة حاليًا',
      predicate: (c) => c.direction == ChequeDirection.received,
    );
  }
}
