import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/cheques/services/cheque_service.dart';
import 'package:yalla_accounts/features/notifications/models/app_notification.dart';
import 'package:yalla_accounts/features/notifications/services/notification_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = const <AppNotification>[];
  bool _loading = true;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final items = await NotificationService.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  List<AppNotification> get _visible => _items.where((item) {
        switch (_filter) {
          case 'unread':
            return !item.isRead && !item.isHandled;
          case 'urgent':
            return item.status == AppNotificationStatus.urgent;
          case 'overdue':
            return item.status == AppNotificationStatus.overdue;
          case 'handled':
            return item.isHandled;
          default:
            return true;
        }
      }).toList();

  Future<void> _open(AppNotification item) async {
    await NotificationService.markRead(item.key);
    if (!mounted) return;
    try {
      if (item.sourceType == 'repairs') {
        final repair = await RepairDatabaseService.getRepairById(item.sourceId);
        if (!mounted) return;
        if (repair != null) {
          await Navigator.of(context).pushNamed(
            AppRoutes.repairDetail,
            arguments: repair,
          );
        } else {
          await AppRoutes.pushNamedSafe(context, AppRoutes.repairsDashboard);
        }
      } else if (item.sourceType == 'cheques') {
        final id = int.tryParse(item.sourceId);
        final cheque = id == null ? null : await ChequeService().getById(id);
        if (!mounted) return;
        await AppRoutes.pushNamedSafe(
          context,
          cheque == null ? AppRoutes.chequesList : AppRoutes.chequesEdit,
          arguments: cheque,
        );
      } else {
        await AppRoutes.pushNamedSafe(
          context,
          item.route,
          arguments: item.arguments,
        );
      }
    } finally {
      if (mounted) await _load();
    }
  }

  Future<void> _handle(AppNotification item) async {
    await NotificationService.markHandled(item.key);
    if (mounted) await _load();
  }

  String _statusLabel(AppNotification item) {
    if (item.isHandled) return 'تمت المعالجة';
    if (!item.isRead) {
      if (item.status == AppNotificationStatus.overdue) return 'متأخر';
      if (item.status == AppNotificationStatus.urgent) return 'عاجل';
      return 'جديد';
    }
    return switch (item.status) {
      AppNotificationStatus.overdue => 'متأخر',
      AppNotificationStatus.urgent => 'عاجل',
      _ => 'مقروء',
    };
  }

  IconData _icon(String source) => switch (source) {
        'repairs' => Icons.car_repair_outlined,
        'receivables' => Icons.call_received_rounded,
        'payables' => Icons.call_made_rounded,
        'cheques' => Icons.payments_outlined,
        'payroll' => Icons.badge_outlined,
        'inventory' => Icons.inventory_2_outlined,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مركز التنبيهات'),
          actions: [
            if (_items.any((e) => e.countsTowardBadge))
              TextButton(
                onPressed: () async {
                  await NotificationService.markAllRead(_items);
                  if (mounted) await _load();
                },
                child: const Text('تعليم الكل كمقروء'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    for (final option in const <(String, String)>[
                      ('all', 'الكل'),
                      ('unread', 'غير مقروء'),
                      ('urgent', 'عاجل'),
                      ('overdue', 'متأخر'),
                      ('handled', 'تمت المعالجة'),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: FilterChip(
                          label: Text(option.$2),
                          selected: _filter == option.$1,
                          onSelected: (_) =>
                              setState(() => _filter = option.$1),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 120),
                                  Icon(Icons.notifications_none, size: 48),
                                  SizedBox(height: 12),
                                  Center(
                                    child: Text(
                                      'لا توجد تنبيهات تحتاج انتباهك الآن',
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  24,
                                ),
                                itemCount: visible.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final item = visible[index];
                                  return Card(
                                    child: ListTile(
                                      minVerticalPadding: 12,
                                      leading: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Icon(_icon(item.sourceType)),
                                          if (item.countsTowardBadge)
                                            const PositionedDirectional(
                                              end: -3,
                                              top: -3,
                                              child: CircleAvatar(radius: 4),
                                            ),
                                        ],
                                      ),
                                      title: Text(
                                        item.title ?? 'تنبيه',
                                        style: TextStyle(
                                          fontWeight: item.countsTowardBadge
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(item.message),
                                          const SizedBox(height: 6),
                                          Text(
                                            _statusLabel(item),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: item.status ==
                                                          AppNotificationStatus
                                                              .overdue ||
                                                      item.status ==
                                                          AppNotificationStatus
                                                              .urgent
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .error
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      onTap: () => _open(item),
                                      trailing: item.isHandled
                                          ? const Icon(
                                              Icons.task_alt_rounded,
                                              semanticLabel: 'تمت المعالجة',
                                            )
                                          : IconButton(
                                              tooltip: 'تمت المعالجة',
                                              onPressed: () => _handle(item),
                                              icon: const Icon(
                                                Icons.check_circle_outline,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
