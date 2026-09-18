import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/activation/license_envelope_verifier.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/release/widgets/release_legal_links.dart';
import 'package:yalla_accounts/core/privacy/account_deletion_request_button.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final String whatsappNumber = '+970598888888';

  VerifiedLicense? _license;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCommercialState();
  }

  Future<void> _loadCommercialState() async {
    final license = await ActivationStateRepository()
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (!mounted) return;
    setState(() {
      _license = license;
      _isLoading = false;
    });
  }

  Future<void> _openWhatsApp() async {
    final url =
        'https://wa.me/$whatsappNumber?text=أحتاج مساعدة في Yallah Accounts';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذر فتح واتساب')),
    );
  }

  void _exitApp() {
    SystemNavigator.pop();
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final license = _license;
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        title: const Text('الاشتراك والترخيص'),
        actions: [
          IconButton(onPressed: _exitApp, icon: const Icon(Icons.close)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    shrinkWrap: true,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: license == null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'لا يوجد ترخيص تجاري موثّق لهذا التثبيت.',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'التجربة والاشتراك والتجديد لا يتم إنشاؤها محليًا داخل التطبيق. '
                                      'يلزم تفعيل صادر عن خادم Yalla.',
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () =>
                                          Navigator.pushReplacementNamed(
                                        context,
                                        AppRoutes.activation,
                                      ),
                                      icon: const Icon(Icons.verified_outlined),
                                      label: const Text('فتح التفعيل'),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'حالة تجارية موثّقة',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'الحالة: ${license.operationalStatus}',
                                    ),
                                    Text(
                                      'الاشتراك: ${license.subscriptionId}',
                                    ),
                                    Text('الاشتراك: ${license.subscriptionId}'),
                                    Text(
                                      'انتهاء الترخيص: '
                                      '${_formatDate(license.expiresAt)}',
                                    ),
                                    Text(
                                      'مراجعة الصلاحيات: '
                                      '${license.entitlementRevision}',
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _openWhatsApp,
                        icon: const FaIcon(FontAwesomeIcons.whatsapp),
                        label: const Text('الدعم الفني عبر واتساب'),
                      ),
                      const SizedBox(height: 12),
                      const AccountDeletionRequestButton(),
                      const SizedBox(height: 8),
                      const ReleaseLegalLinks(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
