import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/config/owner_local_access.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_environment.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_factory.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_runtime_access.dart';
import 'package:yalla_accounts/features/commercial_registration/commercial_first_run_screen.dart';
import 'package:yalla_accounts/core/window/desktop_window_service.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_screen.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';

/// Persisted sessions are verified and unlocked by LoginScreen before use.
class StartupScreen extends ConsumerStatefulWidget {
  const StartupScreen({super.key});
  @override
  ConsumerState<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends ConsumerState<StartupScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _route());
  }

  Future<void> _route() async {
    if (!mounted) return;
    ref.read(currentUserProvider.notifier).state = null;

    if (OwnerLocalAccess.enabled) {
      await configureMainAppWindow();
      final user =
          await ref.read(authSessionServiceProvider).startOwnerLocalSession();
      if (!mounted) return;
      ref.read(currentUserProvider.notifier).state = user;
      Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
      return;
    }

    if (CommercialBackendEnvironment.enabled) {
      final service = createCommercialBackendService()!;
      final state = await service.localState();
      if (!mounted) return;
      if (state != CommercialRegistrationState.registered) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const CommercialFirstRunScreen(),
          ),
        );
        return;
      }
      try {
        final license = await service.checkCurrentLicense();
        if (!mounted) return;
        if (license != null) {
          CommercialBackendRuntimeAccess.applyLicense(license);
        }
        if (license == null || license.isBlocked) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const CommercialFirstRunScreen(),
            ),
          );
          return;
        }
      } catch (_) {
        try {
          final lease = await service.checkOfflineLease();
          if (!mounted) return;
          if (lease != null) {
            CommercialBackendRuntimeAccess.applyOfflineLease(lease);
          }
          if (lease == null) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const CommercialFirstRunScreen(),
              ),
            );
            return;
          }
        } catch (_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => const CommercialFirstRunScreen(),
            ),
          );
          return;
        }
      }
      if (!mounted) return;
      final hasUsers = await ref.read(userServiceProvider).hasAnyUsers();
      if (!mounted) return;
      if (!hasUsers) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const CommercialFirstRunScreen(),
          ),
        );
        return;
      }
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      return;
    }

    if (ref.read(cloudConfigProvider).enabled) {
      try {
        final identity = ref.read(supabaseIdentityProvider);
        final handled = await identity.handleStartupCallback();
        if (!mounted) return;
        if (handled) {
          Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: (_) => CloudAuthScreen(
              onboarding: !identity.recoveryPending,
              resumeVerifiedCallback: true,
            ),
          ));
          return;
        }
      } catch (_) {
        // A cloud callback failure must never block ordinary local login.
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
