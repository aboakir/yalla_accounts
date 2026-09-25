// 📁 lib/features/auth/screens/user_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/finance/payments/screens/payment_list_screen.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class UserDashboardScreen extends ConsumerStatefulWidget {
  final AppUser user;

  const UserDashboardScreen({super.key, required this.user});

  @override
  ConsumerState<UserDashboardScreen> createState() =>
      _UserDashboardScreenState();
}

class _UserDashboardScreenState extends ConsumerState<UserDashboardScreen> {
  late AppUser user;
  bool isSubscriptionActive = false;
  String subscriptionType = 'جاري التحقق';
  String subscriptionEndDateDisplay = '—';
  int remainingDays = 0;

  // لمنع تكرار التنقل داخل addPostFrameCallback
  bool _navigated = false;

  final List<Map<String, dynamic>> invoices = const [
    {
      'date': '12 يونيو 2025',
      'amount': 199.99,
      'pdfUrl': 'https://yourdomain.com/invoices/invoice_12_6_2025.pdf',
    },
    {
      'date': '01 مايو 2025',
      'amount': 149.50,
      'pdfUrl': 'https://yourdomain.com/invoices/invoice_01_5_2025.pdf',
    },
  ];

  @override
  void initState() {
    super.initState();
    user = widget.user;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _navigated) return;
      ref.read(currentUserProvider.notifier).state = user;
      await _loadCommercialStatus();
    });
  }

  Future<void> _loadCommercialStatus() async {
    if (CommercialBackendEnvironment.enabled) {
      final service = createCommercialBackendService();
      try {
        final online = await service?.checkCurrentLicense();
        if (online != null) {
          CommercialBackendRuntimeAccess.applyLicense(online);
          await LicenseRuntimeService().refreshFromStoredLicense(
            now: online.serverTime,
          );
        }
      } catch (_) {
        try {
          final lease = await service?.checkOfflineLease();
          if (lease != null) {
            CommercialBackendRuntimeAccess.applyOfflineLease(lease);
            await LicenseRuntimeService().refreshFromStoredLicense(
              now: lease.issuedAt,
            );
          }
        } catch (_) {
          // Keep the last verified PHP/offline runtime state.
        }
      }

      if (!mounted || _navigated) return;
      if (!CommercialBackendRuntimeAccess.canRead) {
        setState(() {
          subscriptionType = 'غير مفعل';
          subscriptionEndDateDisplay = 'غير محدد';
          remainingDays = 0;
          isSubscriptionActive = false;
        });
        _navigated = true;
        Navigator.pushReplacementNamed(context, AppRoutes.subscription);
        return;
      }

      final expiry = CommercialBackendRuntimeAccess.expiresAt;
      final days =
          expiry == null ? 0 : expiry.difference(DateTime.now().toUtc()).inDays;
      setState(() {
        subscriptionType = CommercialBackendRuntimeAccess.planName ??
            CommercialBackendRuntimeAccess.planCode ??
            CommercialBackendRuntimeAccess.subscriptionStatus ??
            'نشط';
        subscriptionEndDateDisplay =
            expiry == null ? 'غير محدد' : _formatDate(expiry);
        remainingDays = days < 0 ? 0 : days;
        isSubscriptionActive = true;
      });
      if (expiry != null && remainingDays <= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تنبيه: الترخيص الحالي ينتهي بعد $remainingDays يوم'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }
      return;
    }

    final license = await ActivationStateRepository()
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (!mounted || _navigated) return;

    if (license == null) {
      setState(() {
        subscriptionType = 'غير مفعل';
        subscriptionEndDateDisplay = 'غير محدد';
        remainingDays = 0;
        isSubscriptionActive = false;
      });
      _navigated = true;
      Navigator.pushReplacementNamed(context, AppRoutes.subscription);
      return;
    }

    final now = DateTime.now().toUtc();
    final days = license.expiresAt.difference(now).inDays;
    setState(() {
      subscriptionType = license.operationalStatus.toUpperCase();
      subscriptionEndDateDisplay = _formatDate(license.expiresAt);
      remainingDays = days < 0 ? 0 : days;
      isSubscriptionActive = true;
    });

    if (remainingDays <= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تنبيه: الترخيص الحالي ينتهي بعد $remainingDays يوم'),
          duration: const Duration(seconds: 5),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}-${date.month}-${date.year}';
  }

  Future<void> _logout() async {
    await ref.read(authSessionServiceProvider).logout();
    ref.read(currentUserProvider.notifier).state = null;
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  void _showSubscriptionAlert() {
    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تنبيه'),
        content: const Text(
          'لا يوجد ترخيص تجاري موثّق لهذا التثبيت. يرجى فتح شاشة التفعيل أو التواصل مع الدعم الفني.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  void _openInvoicePdf(String url) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('فتح الفاتورة: $url')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isDesktop = screenWidth >= 900;

    final sidebar = Container(
      width: 280,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 140,
            color: AppColors.primary,
            alignment: Alignment.center,
            child: Text(
              user.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              children: [
                _buildSidebarButton(
                  label: 'ابدأ الاستخدام الآن',
                  isActive: isSubscriptionActive,
                  onTap: () {
                    if (!isSubscriptionActive) _showSubscriptionAlert();
                  },
                ),
                _buildSidebarButton(
                  label: 'الملف الشخصي',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.settingsUser),
                ),
                _buildSidebarButton(
                  label: 'الرئيسية',
                  icon: Icons.home,
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.homeDashboard),
                ),
                _buildSidebarButton(
                  label: 'المدفوعات',
                  icon: Icons.receipt_long,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaymentListScreen(),
                    ),
                  ),
                ),
                _buildSidebarButton(
                  label: 'تسجيل الخروج',
                  onTap: _logout,
                  icon: Icons.logout,
                  iconColor: Colors.redAccent,
                  labelColor: Colors.redAccent,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: AppColors.primary,
              title: const Text('لوحة تحكم المستخدم'),
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
      drawer: isDesktop ? null : Drawer(child: sidebar),
      body: AdaptiveRow(
        children: [
          if (isDesktop) sidebar,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ListView(
                children: [
                  RichText(
                    text: TextSpan(
                      text: 'مرحبًا ',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontSize: 24,
                        fontWeight: FontWeight.w400,
                      ),
                      children: [
                        TextSpan(
                          text: user.name,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const TextSpan(
                          text: ' في لوحة التحكم 👋',
                        ),
                      ],
                    ),
                  ),
                  if (isSubscriptionActive && remainingDays > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber),
                      ),
                      child: AdaptiveRow(
                        children: [
                          const Icon(Icons.access_time, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '🕒 تبقّى $remainingDays يومًا من اشتراكك $subscriptionType.',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSubscriptionActive
                          ? AppColors.lightGreen
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSubscriptionActive
                            ? AppColors.primary
                            : Colors.redAccent,
                      ),
                    ),
                    child: Text(
                      'حالة الحساب: ${user.status}\n'
                      'نوع الاشتراك: $subscriptionType\n'
                      'انتهاء الاشتراك: $subscriptionEndDateDisplay',
                      style: TextStyle(
                        fontSize: 16,
                        color: isSubscriptionActive
                            ? AppColors.primary
                            : Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'المدفوعات',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  ...invoices.map(
                    (invoice) => Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf, size: 30),
                        title: Text('فاتورة بتاريخ ${invoice['date']}'),
                        subtitle: Text('المبلغ: \$${invoice['amount']}'),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded),
                        onTap: () =>
                            _openInvoicePdf(invoice['pdfUrl'] as String),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarButton({
    required String label,
    VoidCallback? onTap,
    bool isActive = false,
    IconData? icon,
    Color? iconColor,
    Color? labelColor,
  }) {
    return ListTile(
      leading: icon != null ? Icon(icon, color: iconColor) : null,
      title: Text(
        label,
        style: TextStyle(
          color: labelColor ?? Colors.black,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      tileColor: isActive ? AppColors.lightGreen : null,
      onTap: onTap,
    );
  }
}
