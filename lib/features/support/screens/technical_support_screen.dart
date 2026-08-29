import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class TechnicalSupportScreen extends StatelessWidget {
  const TechnicalSupportScreen({super.key});

  // ===== بيانات التواصل =====
  static const String companyName = 'Yalla Accounts';
  static const String phone = '0594 680 857';
  static const String whatsapp = '+970 566 061 666';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl, // ✅ RTL
      child: Scaffold(
        backgroundColor: const Color(0xffF5F7FA),
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          centerTitle: true,
          title: const Text(
            'التواصل مع الشركة',
            style: TextStyle(color: Colors.white),
          ),
        ),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, // RTL-friendly
              children: [
                const Text(
                  companyName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لتفعيل الاشتراك أو للاستفسار، '
                  'يرجى التواصل معنا عبر بيانات الاتصال التالية:',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 24),
                _infoLine('الهاتف', phone),
                const SizedBox(height: 12),
                _infoLine('واتساب', whatsapp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    return AdaptiveRow(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
