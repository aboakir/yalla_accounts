import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// Legacy route name retained for compatibility.
///
/// P18 no longer calculates a local trial expiry. If this route is reached,
/// the safe action is to return to the signed activation flow.
class TrialExpiredScreen extends StatelessWidget {
  const TrialExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 72,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'الترخيص التجاري غير متاح',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'يلزم التحقق من تفعيل صادر عن خادم Yalla لهذا الجهاز '
                  'والتثبيت. لا يتم إنشاء فترة تجريبية محليًا.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.activation,
                        (_) => false,
                      );
                    },
                    child: const Text('فتح التفعيل'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
