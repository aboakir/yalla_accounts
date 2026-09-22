import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/insurance_agent/alerts/services/insurance_alert_center_service.dart';

class InsuranceAlertsScreen extends StatefulWidget {
  const InsuranceAlertsScreen({super.key});

  @override
  State<InsuranceAlertsScreen> createState() => _InsuranceAlertsScreenState();
}

class _InsuranceAlertsScreenState extends State<InsuranceAlertsScreen> {
  InsuranceAlertWindow _window = InsuranceAlertWindow.all;
  late Future<List<InsuranceAlertItem>> _alerts;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _alerts = InsuranceAlertCenterService.listAlerts(window: _window);
  }

  Future<void> _refresh() async {
    setState(_reload);
    await _alerts;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          title: const Text(
            'التنبيهات والمتابعة',
            style: TextStyle(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            _windowBar(),
            Expanded(
              child: FutureBuilder<List<InsuranceAlertItem>>(
                future: _alerts,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                      message: snapshot.error.toString(),
                      onRetry: _refresh,
                    );
                  }
                  final alerts = snapshot.data ?? const <InsuranceAlertItem>[];
                  if (alerts.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.notifications_none, size: 64),
                          SizedBox(height: 16),
                          Center(
                            child: Text(
                              'لا توجد تنبيهات ضمن الفترة المحددة',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: 8),
                          Center(
                            child: Text(
                              'اسحب للتحديث أو اختر فترة أخرى',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: alerts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _AlertCard(alert: alerts[index]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowBar() {
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(
          children: InsuranceAlertWindow.values.map((window) {
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(_windowLabel(window)),
                selected: _window == window,
                onSelected: (_) {
                  setState(() {
                    _window = window;
                    _reload();
                  });
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static String _windowLabel(InsuranceAlertWindow window) {
    switch (window) {
      case InsuranceAlertWindow.today:
        return 'اليوم';
      case InsuranceAlertWindow.next7:
        return '7 أيام';
      case InsuranceAlertWindow.next14:
        return '14 يومًا';
      case InsuranceAlertWindow.next30:
        return '30 يومًا';
      case InsuranceAlertWindow.overdue:
        return 'متأخر';
      case InsuranceAlertWindow.all:
        return 'الكل';
    }
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});

  final InsuranceAlertItem alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.severity) {
      'HIGH' => Colors.red.shade700,
      'MEDIUM' => Colors.orange.shade800,
      _ => Colors.blue.shade700,
    };
    final date =
        '${alert.dueAt.year.toString().padLeft(4, '0')}/${alert.dueAt.month.toString().padLeft(2, '0')}/${alert.dueAt.day.toString().padLeft(2, '0')}';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(_iconFor(alert.type)),
        ),
        title: Text(
          alert.message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('${_typeLabel(alert.type)} • $date'),
        trailing: Text(
          _severityLabel(alert.severity),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static IconData _iconFor(String type) {
    if (type.contains('CHEQUE')) return Icons.receipt_long_outlined;
    if (type.contains('CLAIM')) return Icons.car_crash_outlined;
    if (type.contains('LICENSE')) return Icons.badge_outlined;
    if (type.contains('SETTLEMENT')) return Icons.account_balance_outlined;
    if (type.contains('QUOTE')) return Icons.request_quote_outlined;
    if (type.contains('INSTALLMENT')) return Icons.payments_outlined;
    return Icons.policy_outlined;
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'POLICY_EXPIRY':
        return 'انتهاء بوليصة';
      case 'DRIVING_LICENSE_EXPIRY':
        return 'انتهاء رخصة';
      case 'OUTSTANDING_INSTALLMENT':
        return 'دفعة مستحقة';
      case 'CHEQUE_DUE':
        return 'شيك مستحق';
      case 'RETURNED_CHEQUE':
        return 'شيك مرتجع';
      case 'CLAIM_FOLLOW_UP':
        return 'متابعة مطالبة';
      case 'MISSING_DOCUMENTS':
        return 'وثائق ناقصة';
      case 'PENDING_SETTLEMENT':
        return 'تسوية معلقة';
      case 'CUSTOMER_FOLLOW_UP':
        return 'متابعة عميل';
      case 'QUOTE_RESPONSE':
        return 'متابعة عرض';
      default:
        return type;
    }
  }

  static String _severityLabel(String severity) {
    switch (severity) {
      case 'HIGH':
        return 'عاجل';
      case 'MEDIUM':
        return 'قريب';
      default:
        return 'متابعة';
    }
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'تعذر تحميل التنبيهات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
