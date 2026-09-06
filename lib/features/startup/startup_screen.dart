import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/routes/app_routes.dart';

/// TEMPORARY LOGIN MODE startup gate.
///
/// Always opens the simplified local login screen. Activation/licensing and
/// persistent authentication are intentionally deferred during prototyping.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openLogin());
  }

  void _openLogin() {
    if (!mounted || _navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
