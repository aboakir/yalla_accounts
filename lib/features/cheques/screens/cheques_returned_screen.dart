import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/features/cheques/widgets/cheque_filtered_screen_body.dart';

class ChequesReturnedScreen extends StatelessWidget {
  const ChequesReturnedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChequeFilteredScreenBody(
      title: 'الشيكات الراجعة',
      currentRoute: AppRoutes.chequesReturned,
      emptyText: 'لا توجد شيكات راجعة حاليًا',
      predicate: (c) => c.status == ChequeStatus.returned,
    );
  }
}
