import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesCancelledScreen extends StatelessWidget {
  const ChequesCancelledScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات الملغاة',
      currentRoute: AppRoutes.chequesCancelled,
      emptyText: 'لا توجد شيكات ملغاة حاليًا',
      predicate: (c) => c.status == ChequeStatus.cancelled,
    );
  }
}
