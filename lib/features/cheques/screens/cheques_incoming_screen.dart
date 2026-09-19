import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';

class ChequesIncomingScreen extends StatelessWidget {
  const ChequesIncomingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات الواردة',
      currentRoute: AppRoutes.chequesIncoming,
      predicate: (c) => c.direction == ChequeDirection.received,
      emptyMessage: 'لا توجد شيكات واردة',
    );
  }
}
