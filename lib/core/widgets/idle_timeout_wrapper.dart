// lib/core/widgets/idle_timeout_wrapper.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

/// ويدجت تغلف التطبيق أو شاشة معينة لمراقبة عدم نشاط المستخدم
/// ويقوم بتسجيل الخروج تلقائيًا بعد مدة محددة من عدم النشاط.
class IdleTimeoutWrapper extends StatefulWidget {
  final Widget child;

  /// المهلة الزمنية قبل تسجيل الخروج (بالثواني)
  final int timeoutSeconds;

  const IdleTimeoutWrapper({
    super.key,
    required this.child,
    this.timeoutSeconds = 600, // 10 دقائق افتراضيًا
  });

  @override
  State<IdleTimeoutWrapper> createState() => _IdleTimeoutWrapperState();
}

class _IdleTimeoutWrapperState extends State<IdleTimeoutWrapper> {
  Timer? _timer;

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: widget.timeoutSeconds), _onTimeout);
  }

  void _onTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);
    await prefs.remove('lastActivity');

    if (!mounted) return;

    // أرجع شاشة تسجيل الدخول (نفترض أن لديك طريقة للوصول إلى Navigator عبر context)
    AppRoutes.navigatorKey.currentState
        ?.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  void initState() {
    super.initState();
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleUserInteraction([_]) {
    _resetTimer();
    _updateLastActivity();
  }

  Future<void> _updateLastActivity() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('lastActivity', DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleUserInteraction,
      onPointerMove: _handleUserInteraction,
      onPointerUp: _handleUserInteraction,
      onPointerCancel: _handleUserInteraction,
      child: widget.child,
    );
  }
}
