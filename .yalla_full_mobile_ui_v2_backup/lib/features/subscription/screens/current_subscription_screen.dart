import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/subscription/services/subscription_service.dart';
import 'package:yalla_accounts/features/subscription/services/plan_service.dart';
import 'package:yalla_accounts/features/subscription/models/plan.dart';

class CurrentSubscriptionScreen extends ConsumerStatefulWidget {
  const CurrentSubscriptionScreen({super.key});

  @override
  ConsumerState<CurrentSubscriptionScreen> createState() =>
      _CurrentSubscriptionScreenState();
}

class _CurrentSubscriptionScreenState
    extends ConsumerState<CurrentSubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  Plan? _plan;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSubscription();
  }

  Future<void> _loadCurrentSubscription() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final subscription =
        await SubscriptionService().getActiveSubscription(user.id);

    if (subscription != null) {
      final plan = await PlanService().getPlanById(subscription['planId']);
      setState(() {
        _subscription = subscription;
        _plan = plan;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('الاشتراك الحالي'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subscription == null
              ? const Center(
                  child: Text(
                    '❌ لا يوجد اشتراك نشط حاليًا',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _plan?.name ?? 'باقة غير معروفة',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          Text(
                              "تاريخ البداية: ${formatter.format(DateTime.parse(_subscription!['startDate']))}"),
                          Text(
                              "تاريخ الانتهاء: ${formatter.format(DateTime.parse(_subscription!['endDate']))}"),
                          Text("السعر: ${_subscription!['price']} شيكل"),
                          const SizedBox(height: 16),
                          _buildRemainingDaysText(),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildRemainingDaysText() {
    final end = DateTime.parse(_subscription!['endDate']);
    final remaining = end.difference(DateTime.now()).inDays;
    return Text(
      "🕒 عدد الأيام المتبقية: $remaining يوم",
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 16,
        color: Colors.green,
      ),
    );
  }
}
