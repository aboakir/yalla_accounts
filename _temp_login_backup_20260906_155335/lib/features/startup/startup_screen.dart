import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/licensing/activation/activation_state_repository.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/screens/reset_password_screen.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

/// P1.002 single startup gate.
///
/// Authentication is authoritative. Licensing/trial code is intentionally not
/// allowed to delete, rewrite, or hide access to existing financial data.
class StartupScreen extends ConsumerStatefulWidget {
  const StartupScreen({super.key});

  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted || _navigated) return;

    final users = ref.read(userServiceProvider);
    if (!await users.hasAnyUsers()) {
      final activation = ActivationStateRepository();
      final active =
          await activation.hasUsableActivationForCurrentInstallation();
      _replaceNamed(active ? AppRoutes.register : AppRoutes.activation);
      return;
    }

    final user = await ref.read(authSessionServiceProvider).restoreSession();
    if (!mounted) return;

    if (user == null) {
      _replaceNamed(AppRoutes.login);
      return;
    }

    ref.read(currentUserProvider.notifier).state = user;
    AuthorizationGuard.enableInteractiveEnforcement();

    if (user.mustChangePassword) {
      _navigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(
            authenticatedUserId: user.id,
          ),
        ),
      );
      return;
    }

    _replaceNamed(AppRoutes.dashboard);
  }

  void _replaceNamed(String route) {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
