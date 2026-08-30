import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/subscription/services/subscription_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';

class PendingSubscriptionsScreen extends ConsumerStatefulWidget {
  const PendingSubscriptionsScreen({super.key});

  @override
  ConsumerState<PendingSubscriptionsScreen> createState() =>
      _PendingSubscriptionsScreenState();
}

class _PendingSubscriptionsScreenState
    extends ConsumerState<PendingSubscriptionsScreen> {
  List<AppUser> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingUsers();
  }

  Future<void> _loadPendingUsers() async {
    final users = await UserService().getAllUsers();
    setState(() {
      _users = users
          .where((u) =>
              u.role != 'admin' &&
              (u.subscriptionDate == null || u.paymentStatus != 'مدفوع'))
          .toList();
      _isLoading = false;
    });
  }

  Future<void> _activateSubscription(AppUser user) async {
    final now = DateTime.now();
    const durationDays = 30; // يمكنك تغييره حسب الاتفاق
    final endDate = now.add(const Duration(days: durationDays));
    const price = 500.0; // أو حسب الباقة الفعلية

    final updatedUser = user.copyWith(
      subscriptionDate: now,
      subscriptionEndDate: endDate,
      subscriptionAmount: price,
      paymentStatus: "مدفوع",
    );

    await SubscriptionService().createSubscription(
      id: UniqueKey().toString(),
      planId: "manual", // أو null لو مش رابط بباقات
      startDate: now,
      endDate: endDate,
      userId: user.id,
      price: price,
    );

    await UserService().updateUser(updatedUser);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ تم تفعيل اشتراك المستخدم")),
    );

    _loadPendingUsers(); // إعادة التحديث
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("طلبات التفعيل"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text("لا يوجد مستخدمين بحاجة للتفعيل"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(user.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("البريد: ${user.email}"),
                            Text(
                                "الحالة: ${user.paymentStatus ?? "غير مدفوع"}"),
                            if (user.subscriptionEndDate != null)
                              Text(
                                  "ينتهي في: ${DateFormat.yMd().format(user.subscriptionEndDate!)}"),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _activateSubscription(user),
                          child: const Text("تفعيل"),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
