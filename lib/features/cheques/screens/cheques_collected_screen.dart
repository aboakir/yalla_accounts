import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';

class ChequesCollectedScreen extends StatelessWidget {
  const ChequesCollectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات المحصلة',
      currentRoute: AppRoutes.chequesCollected,
      predicate: (c) => c.status == ChequeStatus.collected,
      emptyMessage: 'لا توجد شيكات محصلة',
    );
  }
}
