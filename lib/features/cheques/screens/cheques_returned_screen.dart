import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';

class ChequesReturnedScreen extends StatelessWidget {
  const ChequesReturnedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات الراجعة',
      currentRoute: AppRoutes.chequesReturned,
      predicate: (c) => c.status == ChequeStatus.returned,
      emptyMessage: 'لا توجد شيكات راجعة',
    );
  }
}
