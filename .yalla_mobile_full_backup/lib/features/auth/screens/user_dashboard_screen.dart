// 📁 lib/features/auth/screens/user_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/finance/payments/screens/payment_list_screen.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class UserDashboardScreen extends ConsumerStatefulWidget {
  final AppUser user;

  const UserDashboardScreen({super.key, required this.user});

  @override
  ConsumerState<UserDashboardScreen> createState() =>
      _UserDashboardScreenState();
}

class _UserDashboardScreenState extends ConsumerState<UserDashboardScreen> {
  late AppUser user;
  late bool isSubscriptionActive;
  late String subscriptionType;
  late String subscriptionEndDateDisplay;
  late int remainingDays;

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
    _calculateSubscriptionStatus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigated) return;

      // خزّن المستخدم الحالي في الـ provider
      ref.read(currentUserProvider.notifier).state = user;

      if (isSubscriptionActive && remainingDays <= 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔔 تنبيه: اشتراكك سينتهي بعد $remainingDays يوم'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange.shade700,
          ),
        );
      }

      // لو الاشتراك غير فعّال والمستخدم ليس أدمن → توجيه لصفحة الاشتراك
      if (!isSubscriptionActive && user.role != 'admin') {
        _navigated = true;
        Navigator.pushReplacementNamed(context, AppRoutes.subscription);
      }
    });
  }

  void _calculateSubscriptionStatus() {
    final now = DateTime.now();

    if (user.role == 'admin') {
      subscriptionType = 'مشرف';
      isSubscriptionActive = true;
      subscriptionEndDateDisplay = 'لا يوجد انتهاء';
      remainingDays = 9999;
      return;
    }

    final freeTrialValid = user.freeTrialStart != null &&
        user.freeTrialEnd != null &&
        now.isAfter(user.freeTrialStart!) &&
        now.isBefore(user.freeTrialEnd!);

    final subscriptionValid = user.subscriptionDate != null &&
        user.subscriptionEndDate != null &&
        now.isAfter(user.subscriptionDate!) &&
        now.isBefore(user.subscriptionEndDate!);

    if (freeTrialValid) {
      subscriptionType = 'مجاني';
      final end = user.freeTrialEnd!;
      remainingDays = end.difference(now).inDays;
      subscriptionEndDateDisplay = _formatDate(end);
      isSubscriptionActive = true;
    } else if (subscriptionValid) {
      subscriptionType = 'مشترك';
      final end = user.subscriptionEndDate!;
      remainingDays = end.difference(now).inDays;
      subscriptionEndDateDisplay = _formatDate(end);
      isSubscriptionActive = true;
    } else {
      subscriptionType = 'غير مفعل';
      subscriptionEndDateDisplay = user.subscriptionEndDate != null
          ? _formatDate(user.subscriptionEndDate!)
          : 'غير محدد';
      remainingDays = 0;
      isSubscriptionActive = false;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}-${date.month}-${date.year}';
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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
          'عذرًا، لا يمكنك استخدام التطبيق بسبب انتهاء الفترة المجانية أو عدم تجديد الاشتراك. يرجى التواصل مع الدعم الفني.',
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
            color: Colors.green.shade400,
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
              backgroundColor: Colors.green.shade400,
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
                            color: Colors.green,
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
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSubscriptionActive
                            ? Colors.green
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
                            ? Colors.green.shade700
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
      tileColor: isActive ? Colors.green.shade50 : null,
      onTap: onTap,
    );
  }
}
