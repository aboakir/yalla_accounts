import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/vehicles/models/vehicle.dart';
import 'package:yalla_accounts/features/vehicles/services/vehicle_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class VehicleHistoryDialog extends StatelessWidget {
  const VehicleHistoryDialog({
    super.key,
    required this.vehicle,
  });

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final formatter = intl.DateFormat('dd-MM-yyyy');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AdaptiveAlertDialog(
        title: Row(
          children: [
            const Icon(Icons.directions_car, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${vehicle.type} • ${vehicle.number}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                      label: Text(
                          'الموديل: ${vehicle.model.isEmpty ? '-' : vehicle.model}')),
                  Chip(
                    label: Text(
                      'المالك: ${vehicle.clientName.isEmpty ? 'غير مرتبط' : vehicle.clientName}',
                    ),
                  ),
                  Chip(label: Text('ملفات الإصلاح: ${vehicle.repairCount}')),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text(
                'تاريخ المركبة',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: FutureBuilder(
                  future: vehicle.id == null
                      ? Future.value(const [])
                      : VehicleService.getHistory(vehicle.id!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    final repairs = snapshot.data ?? const [];
                    if (repairs.isEmpty) {
                      return const Center(
                        child: Text('لا يوجد سجل إصلاح لهذه المركبة'),
                      );
                    }

                    return ListView.separated(
                      itemCount: repairs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final repair = repairs[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            repair.vehicleStatus.trim().isEmpty
                                ? 'ملف إصلاح'
                                : repair.vehicleStatus,
                          ),
                          subtitle: Text(
                            '${formatter.format(repair.receivedDate)}'
                            ' • ${repair.beneficiaryName}',
                          ),
                          trailing: Text(
                            repair.paymentStatus ??
                                repair.computedPaymentStatus,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
