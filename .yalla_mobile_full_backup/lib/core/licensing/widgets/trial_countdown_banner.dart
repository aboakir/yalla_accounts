import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/licensing/trial_manager.dart';

class TrialCountdownBanner extends StatelessWidget {
  const TrialCountdownBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: TrialManager.getRemainingHours(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final remainingHours = snapshot.data!;
        if (remainingHours <= 0) {
          return const SizedBox.shrink();
        }

        return Container(
          height: 38,
          width: double.infinity,
          color: Colors.orange.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerRight,
          child: Text(
            '⏳ الفترة التجريبية: متبقي $remainingHours ساعة',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
