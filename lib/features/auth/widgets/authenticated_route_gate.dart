import 'package:yalla_accounts/core/services/current_user_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';

class AuthenticatedRouteGate extends ConsumerStatefulWidget {
  const AuthenticatedRouteGate(
      {super.key, required this.child, this.ownerOnly = false});
  final Widget child;
  final bool ownerOnly;
  @override
  ConsumerState<AuthenticatedRouteGate> createState() => _GateState();
}

class _GateState extends ConsumerState<AuthenticatedRouteGate> {
  late Future<(AppUser?, CommercialAccessDecision?)> _access;
  @override
  void initState() {
    super.initState();
    _access = _validate();
  }

  Future<(AppUser?, CommercialAccessDecision?)> _validate() async {
    final session = ref.read(authSessionServiceProvider);
    final gate = ref.read(commercialAccessGateServiceProvider);
    final user = await session.restoreSession();
    if (user == null) return (null, null);
    return (user, await gate.evaluate(user));
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(currentUserProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    CurrentUserContext.bindActiveUserReader(
        () => container.read(currentUserProvider)?.id);
    if (selected == null) return _loginRequired();
    return FutureBuilder<(AppUser?, CommercialAccessDecision?)>(
        future: _access,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return _BlockedAccess(
                title: 'تعذر التحقق من الدخول',
                message: 'أعد المحاولة للتحقق من الجلسة والترخيص.',
                actionLabel: 'إعادة المحاولة',
                onAction: () => setState(() => _access = _validate()));
          }
          final user = snapshot.data?.$1;
          if (user == null ||
              user.id != selected.id ||
              user.role != selected.role ||
              user.organizationId != selected.organizationId)
            return _loginRequired();
          final commercial = snapshot.data?.$2;
          if (commercial == null || !commercial.allowed) {
            return _BlockedAccess(
                title: 'التحقق التجاري مطلوب',
                message: commercial?.message ?? 'تعذر التحقق من الترخيص.',
                actionLabel: 'العودة إلى الدخول',
                onAction: _goLogin);
          }
          if (user.mustChangePassword) {
            return _BlockedAccess(
                title: 'تغيير كلمة المرور مطلوب',
                message: 'غيّر كلمة المرور قبل متابعة العمل.',
                actionLabel: 'تغيير كلمة المرور',
                onAction: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => ResetPasswordScreen(
                            authenticatedUserId: user.id))));
          }
          if (widget.ownerOnly && !user.isOwner) {
            return const _BlockedAccess(
                title: 'صلاحية غير كافية',
                message: 'هذه الشاشة متاحة للمالك فقط.');
          }
          // Preserve the current route restrictions; the RBAC expansion is separate.
          if (!user.isOwner) {
            final routeName = ModalRoute.of(context)?.settings.name ?? '';
            const employeeRoutes = {
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
              AppRoutes.logout
            };
            if (!employeeRoutes.contains(routeName)) {
              return const _BlockedAccess(
                  title: 'صلاحية غير كافية',
                  message: 'هذه الشاشة غير متاحة لصلاحيات الحساب الحالية.');
            }
          }
          return widget.child;
        });
  }

  void _goLogin() {
    ref.read(currentUserProvider.notifier).state = null;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  Widget _loginRequired() => _BlockedAccess(
      title: 'تسجيل الدخول مطلوب',
      message: 'تحقق من حسابك لفتح الشاشة.',
      actionLabel: 'تسجيل الدخول',
      onAction: _goLogin);
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
