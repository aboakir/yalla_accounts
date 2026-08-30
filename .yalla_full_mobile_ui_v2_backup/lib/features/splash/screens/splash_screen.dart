import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/subscription/services/subscription_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const String logoPath = 'assets/logo/logo.png';
  static const int defaultTimeoutMinutes = 10;

  @override
  void initState() {
    super.initState();
    print("🚀 Splash Started");
    _startAppInitialization();
  }

  Future<void> _startAppInitialization() async {
    debugPrint("🟢 بدء التهيئة...");

    try {
      final prefs = await SharedPreferences.getInstance();
      debugPrint("✅ تم الحصول على SharedPreferences");

      final loggedIn = prefs.getBool('loggedIn') ?? false;
      final username = prefs.getString('username') ?? '';
      final int lastActivityMillis = prefs.getInt('lastActivity') ?? 0;
      final int currentTimeMillis = DateTime.now().millisecondsSinceEpoch;
      final int timeoutMillis =
          (prefs.getInt('timeoutMinutes') ?? defaultTimeoutMinutes) * 60 * 1000;

      debugPrint("🔐 الحالة: loggedIn=$loggedIn, username=$username");

      if (!loggedIn || username.isEmpty) {
        debugPrint("🚪 المستخدم غير مسجل دخول. الانتقال إلى /login");
        print("🧭 Navigating to: ${AppRoutes.login}");
        _navigateTo(AppRoutes.login);
        return;
      }

      if ((currentTimeMillis - lastActivityMillis) > timeoutMillis) {
        debugPrint("⏳ انتهت صلاحية الجلسة. تسجيل الخروج");
        await prefs.setBool('loggedIn', false);
        print("🧭 Navigating to: ${AppRoutes.login}");
        _navigateTo(AppRoutes.login);
        return;
      }

      print("📡 Checking currentUser...");
      final userService = UserService();
      final AppUser? user = await userService.getUserByUsername(username);

      if (user == null) {
        debugPrint("❌ المستخدم غير موجود في قاعدة البيانات");
        await prefs.setBool('loggedIn', false);
        print("🧭 Navigating to: ${AppRoutes.login}");
        _navigateTo(AppRoutes.login);
        return;
      }

      print("✅ User Found: ${user.name}");

      final now = DateTime.now();
      final isTrialExpired =
          user.freeTrialEnd != null && user.freeTrialEnd!.isBefore(now);

      final subscription =
          await SubscriptionService().getActiveSubscription(user.id);

      if (subscription == null && isTrialExpired) {
        debugPrint("⚠️ لا يوجد اشتراك نشط ولا فترة تجريبية");
        print("🧭 Navigating to: ${AppRoutes.subscription}");
        _navigateTo(AppRoutes.subscription);
        return;
      }

      if (user.role == 'admin') {
        print("🧭 Navigating to: ${AppRoutes.admin}");
        _navigateTo(AppRoutes.admin, arguments: user);
        return;
      }

      if (user.role == 'user' || user.role == 'staff') {
        print("🧭 Navigating to: ${AppRoutes.dashboard}");
        _navigateTo(AppRoutes.dashboard, arguments: user);
        return;
      }

      if (user.role == 'manager') {
        print("🧭 Navigating to: ${AppRoutes.managerDashboard}");
        _navigateTo(AppRoutes.managerDashboard, arguments: user);
        return;
      }

      debugPrint("❓ نوع المستخدم غير معروف، توجيه إلى تسجيل الدخول");
      print("🧭 Navigating to: ${AppRoutes.login}");
      _navigateTo(AppRoutes.login);
    } catch (e, s) {
      debugPrint("🚨 خطأ أثناء التهيئة: $e");
      debugPrint("Stack: $s");
      print("🧭 Navigating to: ${AppRoutes.login}");
      _navigateTo(AppRoutes.login);
    }
  }

  void _navigateTo(String route, {Object? arguments}) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacementNamed(context, route, arguments: arguments);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              logoPath,
              width: MediaQuery.of(context).size.width * 0.4,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
