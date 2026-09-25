import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/commercial_backend/commercial_backend_models.dart';

import 'subscription_screen.dart';

class CurrentSubscriptionScreen extends StatelessWidget {
  const CurrentSubscriptionScreen({super.key, this.load});

  final Future<LicenseCheckResult?> Function()? load;

  @override
  Widget build(BuildContext context) => SubscriptionScreen(load: load);
}
