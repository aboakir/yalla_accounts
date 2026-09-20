import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';

class ChequesOutgoingScreen extends StatelessWidget {
  const ChequesOutgoingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات الصادرة',
      currentRoute: AppRoutes.chequesOutgoing,
      predicate: (c) => c.direction == ChequeDirection.issued,
      emptyMessage: 'لا توجد شيكات صادرة',
    );
  }
}
