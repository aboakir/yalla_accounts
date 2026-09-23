import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

class UnderDevelopmentScreen extends StatelessWidget {
  final String featureName;

  const UnderDevelopmentScreen({super.key, required this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحت التطوير'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => AppRoutes.popOrDashboard(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 80,
                color: Colors.orange.shade700,
              ),
              const SizedBox(height: 24),
              Text(
                'ميزة "$featureName" قيد التطوير حالياً.',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => AppRoutes.popOrDashboard(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('العودة إلى لوحة التحكم'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
