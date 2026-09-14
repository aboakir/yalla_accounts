import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/auth_session_service.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/cloud_auth/cloud_auth_service.dart';

class LogoutScreen extends ConsumerStatefulWidget {
  const LogoutScreen({super.key});

  @override
  ConsumerState<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends ConsumerState<LogoutScreen> {
  @override
  void initState() {
    super.initState();
    _logout();
  }

  Future<void> _logout() async {
    final cloudConfig = ref.read(cloudConfigProvider);
    if (cloudConfig.enabled) {
      try {
        await ref.read(supabaseIdentityProvider).signOut();
      } catch (_) {
        // Local workshop logout must still complete when the network is down.
      }
    }

    await ref.read(authSessionServiceProvider).logout();
    ref.read(currentUserProvider.notifier).state = null;
    AuthorizationGuard.enableInteractiveEnforcement();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
