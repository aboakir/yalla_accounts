import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/subscription/models/plan.dart';
import 'package:yalla_accounts/features/subscription/services/plan_service.dart';
import 'package:yalla_accounts/features/subscription/services/subscription_service.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  List<Plan> _plans = [];
  bool _isLoading = true;
  bool _trialActivated = false;

  final String whatsappNumber = '+970598888888'; // ✅ غيّر الرقم حسب فريقك

  @override
  void initState() {
    super.initState();
    _checkAndActivateTrial();
  }

  Future<void> _checkAndActivateTrial() async {
    final user = ModalRoute.of(context)?.settings.arguments as AppUser?;
    if (user == null || _trialActivated) return;

    try {
      final plans = await PlanService().getAllActivePlans();
      setState(() {
        _plans = plans;
        _isLoading = false;
      });

      final freePlan = plans.firstWhere(
        (p) => p.price == 0,
        orElse: () => Plan.empty(),
      );

      final subscriptionService = SubscriptionService();
      final alreadyActive =
          await subscriptionService.isSubscriptionActive(user.id);

      if (!alreadyActive) {
        await subscriptionService.activateTrial(user.id, freePlan.durationDays);
        setState(() => _trialActivated = true);

        if (!mounted) return;

        await Future.delayed(const Duration(milliseconds: 300));
        showDialog(
          context: context,
          builder: (_) => AdaptiveAlertDialog(
            title: const Text("🎉 تم التفعيل"),
            content: Text(
                "تم تفعيل الباقة المجانية لمدة ${freePlan.durationDays} يوم."),
            actions: [
              TextButton(
                child: const Text("ابدأ"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(
                    context,
                    '/dashboard', // ✅ عدّل هذا إذا اسم الشاشة مختلف
                    arguments: user,
                  );
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ حدث خطأ أثناء تحميل الباقات: $e")),
      );
    }
  }

  Future<void> _openWhatsApp() async {
    final url =
        'https://wa.me/$whatsappNumber?text=أرغب بالاشتراك في Yalla Accounts';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ تعذر فتح واتساب")),
      );
    }
  }

  void _exitApp() {
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: Center(
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      AdaptiveRow(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "تفعيل الاشتراك",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          AdaptiveRow(
                            children: [
                              IconButton(
                                onPressed: () {
                                  Navigator.pushReplacementNamed(
                                      context, '/login');
                                },
                                icon: const Icon(Icons.arrow_back_ios),
                              ),
                              IconButton(
                                onPressed: _exitApp,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          )
                        ],
                      ),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text(
                        "💡 خطوات تفعيل الاشتراك:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text("1️⃣ اختر الباقة المناسبة من القائمة أدناه."),
                      const Text("2️⃣ حوّل المبلغ إلى الحساب البنكي."),
                      const Text("3️⃣ أرسل صورة الحوالة عبر واتساب."),
                      const Text("4️⃣ يتم التفعيل يدويًا خلال 24 ساعة."),
                      const SizedBox(height: 16),

                      ElevatedButton.icon(
                        onPressed: _openWhatsApp,
                        icon: const FaIcon(FontAwesomeIcons.whatsapp),
                        label: const Text("تواصل مع فريق يلا عبر واتساب"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(45),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        "🧾 الباقات المتوفرة:",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),

                      ..._plans.map((plan) => GestureDetector(
                            onTap: () {
                              if (plan.price != 0) {
                                _openWhatsApp();
                              }
                            },
                            child: Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: ListTile(
                                  title: Text(plan.name),
                                  subtitle:
                                      Text(plan.description ?? "بدون وصف"),
                                  trailing: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("${plan.price} شيكل"),
                                      Text("لمدة ${plan.durationDays} يوم"),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
