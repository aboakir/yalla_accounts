import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/features/auth/providers/current_user_provider.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';

/// TEMPORARY LOGIN MODE
///
/// This screen intentionally bypasses password, activation, licensing and
/// remote authentication while the product is being prototyped.
///
/// Accepted identifiers:
///   owner -> owner account / full-owner UI identity
///   user  -> default employee UI identity
///
/// Replace this screen when the production authentication flow is implemented.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;

    final identifier = _usernameController.text.trim().toLowerCase();
    if (identifier != 'owner' && identifier != 'user') {
      _showError('اكتب owner أو user فقط');
      return;
    }

    setState(() => _loading = true);

    try {
      final user = identifier == 'owner'
          ? await _resolveOwner()
          : await _resolveDefaultUser();

      // This is deliberately an in-memory preview session. Do not enable the
      // production AuthorizationGuard here; the real auth implementation will
      // restore the normal server/license/session chain later.
      AuthorizationGuard.disableInteractiveEnforcement();
      ref.read(currentUserProvider.notifier).state = user;

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        user.isOwner ? AppRoutes.dashboard : AppRoutes.repairsDashboard,
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        _showError('تعذر فتح الحساب المؤقت');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<AppUser> _resolveOwner() async {
    // On an existing Windows installation, preserve the real local owner
    // profile when it is already present. On a fresh mobile installation,
    // fall back to an in-memory owner identity without creating DB rows.
    try {
      final service = ref.read(userServiceProvider);
      if (await service.hasAnyUsers()) {
        final owner = await service.getOwner();
        if (owner != null) {
          return owner.copyWith(mustChangePassword: false);
        }
      }
    } catch (_) {
      // Fresh/partial installs intentionally fall back to preview identity.
    }

    return AppUser(
      id: 'temporary-owner',
      name: 'owner',
      email: 'owner@yalla.local',
      role: RoleKeys.owner,
      status: 'active',
      createdAt: DateTime.now(),
      isOwner: true,
      mustChangePassword: false,
    );
  }

  Future<AppUser> _resolveDefaultUser() async {
    // Reuse a real local user named "user" when one already exists.
    try {
      final existing =
          await ref.read(userServiceProvider).getUserByUsername('user');
      if (existing != null &&
          existing.status == 'active' &&
          !existing.isOwner) {
        return existing.copyWith(mustChangePassword: false);
      }
    } catch (_) {
      // No local default user is required in temporary preview mode.
    }

    return AppUser(
      id: 'temporary-user',
      name: 'user',
      email: 'user@yalla.local',
      role: RoleKeys.employee,
      status: 'active',
      createdAt: DateTime.now(),
      isOwner: false,
      mustChangePassword: false,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 620;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 22 : 32,
                vertical: 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Card(
                  elevation: 3,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 24 : 42,
                      vertical: compact ? 34 : 44,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/logo/logo.png',
                          width: compact ? 110 : 125,
                          height: compact ? 110 : 125,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Yalla Accounts',
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 27,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 38),
                        TextField(
                          controller: _usernameController,
                          autofocus: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'اسم الدخول',
                            hintText: 'owner أو user',
                            prefixIcon: const Icon(
                              Icons.person_outline,
                              color: AppColors.primary,
                            ),
                            filled: true,
                            fillColor: AppColors.inputFill,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.lightGrey,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.lightGrey,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 17),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'دخول',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'دخول مؤقت للتجربة: owner للمالك • user للمستخدم',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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
