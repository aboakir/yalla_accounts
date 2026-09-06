import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';

/// TEMPORARY LOGIN MODE route gate.
///
/// During prototype development, a user selected on LoginScreen is sufficient
/// to enter protected routes. Server licensing/session enforcement is deferred
/// until the production authentication implementation replaces this mode.
class AuthenticatedRouteGate extends ConsumerWidget {
  const AuthenticatedRouteGate({
    super.key,
    required this.child,
    this.ownerOnly = false,
  });

  final Widget child;
  final bool ownerOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return _BlockedAccess(
        title: 'تسجيل الدخول مطلوب',
        message: 'اكتب owner أو user في شاشة الدخول.',
        actionLabel: 'تسجيل الدخول',
        onAction: () {
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (_) => false,
          );
        },
      );
    }

    if (ownerOnly && !user.isOwner) {
      return const _BlockedAccess(
        title: 'صلاحية غير كافية',
        message: 'هذه الشاشة متاحة لحساب owner فقط.',
      );
    }

    if (!user.isOwner) {
      final routeName = ModalRoute.of(context)?.settings.name ?? '';
      const employeeRoutes = <String>{
        AppRoutes.repairs,
        AppRoutes.repairsList,
        AppRoutes.repairsAdd,
        AppRoutes.repairsDashboard,
        AppRoutes.repairDetail,
        AppRoutes.vehiclesList,
        AppRoutes.clients,
        AppRoutes.clientsList,
        AppRoutes.clientAdd,
        AppRoutes.clientEdit,
        AppRoutes.technicalSupport,
        AppRoutes.logout,
      };

      if (!employeeRoutes.contains(routeName)) {
        return _BlockedAccess(
          title: 'صلاحية غير كافية',
          message: 'حساب user مخصص للعمل اليومي ولا يملك صلاحية هذه الشاشة.',
          actionLabel: 'العودة إلى واجهة المستخدم',
          onAction: () {
            Navigator.of(context).pushNamedAndRemoveUntil(
              AppRoutes.repairsDashboard,
              (_) => false,
            );
          },
        );
      }
    }

    return child;
  }
}

class _BlockedAccess extends StatelessWidget {
  const _BlockedAccess({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(message, textAlign: TextAlign.center),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
