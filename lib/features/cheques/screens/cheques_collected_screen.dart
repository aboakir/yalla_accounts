import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesCollectedScreen extends StatelessWidget {
  const ChequesCollectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات المحصلة',
      currentRoute: AppRoutes.chequesCollected,
      emptyText: 'لا توجد شيكات محصلة حاليًا',
      predicate: (c) => c.status == ChequeStatus.collected,
    );
  }
}
