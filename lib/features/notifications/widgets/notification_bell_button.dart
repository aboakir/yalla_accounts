import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/notifications/services/notification_service.dart';

class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton>
    with WidgetsBindingObserver {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final items = await NotificationService.load();
      if (!mounted) return;
      setState(() => _count = items.where((e) => e.countsTowardBadge).length);
    } catch (_) {
      if (mounted) setState(() => _count = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _count == 0 ? 'التنبيهات' : '$_count تنبيهات غير مقروءة',
      onPressed: () async {
        await AppRoutes.pushNamedSafe(context, AppRoutes.notifications);
        if (mounted) await _refresh();
      },
      icon: Badge(
        isLabelVisible: _count > 0,
        label: Text(_count > 99 ? '99+' : '$_count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
