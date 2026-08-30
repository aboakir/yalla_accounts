import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/commercial_access_gate_service.dart';

class AuthenticatedRouteGate extends ConsumerStatefulWidget {
  const AuthenticatedRouteGate({
    super.key,
    required this.child,
    this.ownerOnly = false,
  });

  final Widget child;
  final bool ownerOnly;

  @override
  ConsumerState<AuthenticatedRouteGate> createState() =>
      _AuthenticatedRouteGateState();
}

class _AuthenticatedRouteGateState
    extends ConsumerState<AuthenticatedRouteGate> {
  late final Future<_ProtectedRouteAccess> _accessFuture;

  @override
  void initState() {
    super.initState();
    _accessFuture = _restoreAndAuthorize();
  }

  Future<_ProtectedRouteAccess> _restoreAndAuthorize() async {
    final user = await ref.read(authSessionServiceProvider).restoreSession();
    if (user == null) {
      return const _ProtectedRouteAccess();
    }
    final commercial =
        await ref.read(commercialAccessGateServiceProvider).evaluate(user);
    return _ProtectedRouteAccess(user: user, commercial: commercial);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProtectedRouteAccess>(
      future: _accessFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const _BlockedAccess(
            title: 'تعذر التحقق من صلاحية الدخول',
            message: 'تم منع فتح الشاشة لأن سلسلة الترخيص لم تُثبت بأمان.',
          );
        }

        final access = snapshot.data ?? const _ProtectedRouteAccess();
        final user = access.user;
        if (user == null) {
          return _BlockedAccess(
            title: 'تسجيل الدخول مطلوب',
            message: 'هذه الشاشة محمية بجلسة مستخدم صالحة.',
            actionLabel: 'تسجيل الدخول',
            onAction: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (_) => false,
              );
            },
          );
        }

        final commercial = access.commercial;
        if (commercial == null || !commercial.allowed) {
          return _BlockedAccess(
            title: commercial?.requiresActivation == true
                ? 'التفعيل مطلوب'
                : 'الدخول التجاري غير معتمد',
            message: commercial?.message ??
                'تعذر إثبات ربط الحساب بالمنشأة والترخيص الحالي.',
            actionLabel:
                commercial?.requiresActivation == true ? 'فتح التفعيل' : null,
            onAction: commercial?.requiresActivation == true
                ? () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/activation',
                      (_) => false,
                    );
                  }
                : null,
          );
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(currentUserProvider.notifier).state = user;
          }
        });

        if (user.mustChangePassword) {
          return _BlockedAccess(
            title: 'تغيير كلمة المرور مطلوب',
            message:
                'تمت ترقية نظام الحماية. غيّر كلمة المرور قبل متابعة العمل.',
            actionLabel: 'تغيير كلمة المرور',
            onAction: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => ResetPasswordScreen(
                    authenticatedUserId: user.id,
                  ),
                ),
              );
            },
          );
        }

        if (widget.ownerOnly && !user.isOwner) {
          return const _BlockedAccess(
            title: 'صلاحية غير كافية',
            message: 'هذه العملية متاحة لمالك المنشأة فقط.',
          );
        }

        return widget.child;
      },
    );
  }
}

class _ProtectedRouteAccess {
  const _ProtectedRouteAccess({this.user, this.commercial});

  final AppUser? user;
  final CommercialAccessDecision? commercial;
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
