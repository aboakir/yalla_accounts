import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesOutgoingScreen extends StatelessWidget {
  const ChequesOutgoingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات الصادرة',
      currentRoute: AppRoutes.chequesOutgoing,
      emptyText: 'لا توجد شيكات صادرة حاليًا',
      predicate: (c) => c.direction == ChequeDirection.issued,
    );
  }
}
