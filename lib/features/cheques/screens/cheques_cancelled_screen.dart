import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/screens/cheque_filtered_screen.dart';

class ChequesCancelledScreen extends StatelessWidget {
  const ChequesCancelledScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreen(
      title: 'الشيكات الملغاة',
      currentRoute: AppRoutes.chequesCancelled,
      predicate: (c) => c.status == ChequeStatus.cancelled,
      emptyMessage: 'لا توجد شيكات ملغاة',
    );
  }
}
