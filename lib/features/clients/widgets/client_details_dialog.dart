import 'package:flutter/material.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ClientDetailsDialog extends StatelessWidget {
  const ClientDetailsDialog({
    super.key,
    required this.client,
  });

  final Client client;

  String _toUiType(String type) {
    final value = type.trim().toLowerCase();
    if (value == 'insurance' || value == 'شركة تأمين' || value == 'تأمين') {
      return 'شركة تأمين';
    }
    return 'أفراد';
  }

  @override
  Widget build(BuildContext context) {
    final typeAr = _toUiType(client.type);
    final isInsurance = typeAr == 'شركة تأمين';

    Widget infoRow(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: AdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label: $value',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AdaptiveAlertDialog(
        title: AdaptiveRow(
          children: [
            Icon(
              isInsurance ? Icons.business : Icons.person,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                client.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'النوع: $typeAr',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                infoRow(Icons.phone, 'الهاتف', client.phone),
                infoRow(Icons.email, 'البريد', client.email),
                infoRow(Icons.location_on, 'العنوان', client.address),
                if (client.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ملاحظات: ${client.notes}',
                    textAlign: TextAlign.right,
                  ),
                ],
                if (client.id != null) ...[
                  const Divider(height: 28),
                  FutureBuilder<ClientProfileSnapshot>(
                    future: ClientService.getProfileSnapshot(client.id!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Text(
                          'تعذر تحميل سجل العميل',
                          textAlign: TextAlign.center,
                        );
                      }

                      final profile = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AdaptiveRow(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  label: 'المركبات',
                                  value: profile.vehicleCount.toString(),
                                  icon: Icons.directions_car,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _StatTile(
                                  label: 'ملفات الإصلاح',
                                  value: profile.repairCount.toString(),
                                  icon: Icons.build_circle_outlined,
                                ),
                              ),
                            ],
                          ),
                          if (profile.vehicleNumbers.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text(
                              'المركبات المرتبطة',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: profile.vehicleNumbers
                                  .map(
                                    (number) => Chip(
                                      avatar: const Icon(
                                        Icons.directions_car,
                                        size: 16,
                                      ),
                                      label: Text(number),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          if (profile.recentRepairs.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            const Text(
                              'آخر ملفات الإصلاح',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            ...profile.recentRepairs.map((repair) {
                              final type =
                                  repair['vehicleType']?.toString() ?? '';
                              final number =
                                  repair['vehicleNumber']?.toString() ?? '';
                              final date =
                                  repair['receivedDate']?.toString() ?? '';
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.history, size: 20),
                                title: Text(
                                  '$type • $number',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(date),
                              );
                            }),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text(
              'حذف',
              style: TextStyle(color: Colors.red),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('تعديل'),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
