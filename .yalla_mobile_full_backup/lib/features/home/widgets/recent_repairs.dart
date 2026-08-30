import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/widgets/y_glass.dart';

class RecentRepairs extends StatelessWidget {
  const RecentRepairs({super.key});

  Future<List<Map<String, Object?>>> _load() async {
    final db = await DBService.database;
    return db.rawQuery("""
      SELECT id, invoiceNumber, vehicleModel, beneficiaryName, receivedDate, status
      FROM repairs
      ORDER BY datetime(receivedDate) DESC
      LIMIT 5
    """);
  }

  @override
  Widget build(BuildContext context) {
    return YGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const YSectionTitle('أحدث الإصلاحات', icon: Icons.handyman),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, Object?>>>(
            future: _load(),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(height: 80);
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const Text('لا توجد بيانات');
              }
              return Column(
                children: rows.map((r) {
                  return ListTile(
                    leading: const Icon(Icons.build),
                    title: Text(r['vehicleModel']?.toString() ?? 'مركبة'),
                    subtitle: Text(
                        '${r['beneficiaryName'] ?? ''} • ${r['receivedDate'] ?? ''} • ${r['status'] ?? ''}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () =>
                        Navigator.pushNamed(context, '/repairs/${r['id']}'),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
