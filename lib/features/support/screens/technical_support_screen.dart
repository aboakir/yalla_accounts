import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class TechnicalSupportScreen extends StatelessWidget {
  const TechnicalSupportScreen({super.key});

  // ===== بيانات التواصل =====
  static const String companyName = 'Yallah Accounts';
  static const String phone = '0594 680 857';
  static const String whatsapp = '+970 566 061 666';

  static String canonicalPhone(String raw) => raw
      .trim()
      .replaceAll(' ', '')
      .replaceAll('-', '')
      .replaceAll('(', '')
      .replaceAll(')', '');

  static Uri phoneUri(String raw) =>
      Uri(scheme: 'tel', path: canonicalPhone(raw));

  static Uri whatsappUri(String raw) {
    final digits = canonicalPhone(raw).replaceFirst('+', '');
    return Uri.https('wa.me', '/$digits');
  }

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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 500),
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
                    _infoLine(
                      context,
                      'الهاتف',
                      phone,
                      launchUri: phoneUri(phone),
                    ),
                    const SizedBox(height: 12),
                    _infoLine(
                      context,
                      'واتساب',
                      whatsapp,
                      launchUri: whatsappUri(whatsapp),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoLine(
    BuildContext context,
    String label,
    String value, {
    required Uri launchUri,
  }) {
    final canonical = canonicalPhone(value);
    return AdaptiveRow(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
        Expanded(
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(
              value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'نسخ الرقم',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: canonical));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(content: Text('تم نسخ الرقم')),
            );
          },
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: 'اتصال / فتح',
          onPressed: () =>
              launchUrl(launchUri, mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    );
  }
}
