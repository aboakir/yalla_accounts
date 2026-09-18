// 📁 lib/features/repairs/screens/debts_screen.dart
//
// DebtsScreen — ذمم المركبات مبنية على قيود اليومية (بدون بيانات وهمية)
// - يقرأ من journal_entries: credit على حساب العملاء مجمّعة لكل relatedRepairId
// - يضمّن معلومات الملف من جدول repairs لحساب المتبقي
// - BottomSheet لعرض تفاصيل الدفعات لكل ملف

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  final _df = DateFormat('yyyy-MM-dd');
  final _currency = NumberFormat('#,##0.00', 'ar');

  Future<Database> _db() async => DBService.database;

  Future<bool> _tableExists(Database db, String table) async {
    final r = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [table],
    );
    return r.isNotEmpty;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = await _db();
      if (!await _tableExists(db, 'journal_entries')) {
        _rows = [];
      } else {
        const accs = [
          'العملاء',
          'عملاء',
          'Customers',
          'Accounts Receivable',
          'AR'
        ];
        final placeholders = List.filled(accs.length, '?').join(',');

        // نقرأ المدفوع لكل ملف + نضمّن معلومات من جدول repairs
        final data = await db.rawQuery(
          '''
          SELECT 
            je.relatedRepairId AS rid,
            IFNULL(SUM(je.credit),0) AS paid,
            MAX(je.date) AS lastPaidDate,
            -- معلومات من repairs
            COALESCE(r.totalFileValue, 0) AS fileTotal,
            COALESCE(r.beneficiaryName, '') AS beneficiaryName,
            COALESCE(r.vehicleNumber, '') AS vehicleNumber,
            COALESCE(r.receivedDate, '') AS receivedDate
          FROM journal_entries je
          LEFT JOIN repairs r ON r.id = je.relatedRepairId
          WHERE je.accountName IN ($placeholders)
          GROUP BY je.relatedRepairId
          HAVING rid IS NOT NULL AND rid <> ''
          ORDER BY lastPaidDate DESC
          ''',
          accs,
        );

        _rows = data.map((m) {
          final paid = (m['paid'] as num?)?.toDouble() ?? 0.0;
          final fileTotal = (m['fileTotal'] as num?)?.toDouble() ?? 0.0;
          final remain = (fileTotal - paid);
          return {
            'rid': (m['rid'] ?? '').toString(),
            'paid': paid,
            'fileTotal': fileTotal,
            'remain': remain,
            'beneficiaryName': (m['beneficiaryName'] ?? '').toString(),
            'vehicleNumber': (m['vehicleNumber'] ?? '').toString(),
            'receivedDate': (m['receivedDate'] ?? '').toString(),
            'lastPaidDate': (m['lastPaidDate'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _showPayments(String rid) async {
    try {
      final db = await _db();
      const accs = [
        'العملاء',
        'عملاء',
        'Customers',
        'Accounts Receivable',
        'AR'
      ];
      final placeholders = List.filled(accs.length, '?').join(',');
      final rows = await db.rawQuery(
        '''
        SELECT date, description, credit
        FROM journal_entries
        WHERE relatedRepairId = ?
          AND accountName IN ($placeholders)
          AND credit > 0
        ORDER BY date ASC, id ASC
        ''',
        [rid, ...accs],
      );

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تفاصيل الدفعات — ملف: $rid',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              rows.isEmpty
                  ? const Text('لا يوجد دفعات مسجلة لهذا الملف')
                  : SizedBox(
                      height: 300,
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 8),
                        itemBuilder: (_, i) {
                          final m = rows[i];
                          final dt =
                              DateTime.tryParse((m['date'] ?? '').toString()) ??
                                  DateTime(1970);
                          final desc = (m['description'] ?? 'دفعة').toString();
                          final val = (m['credit'] as num?)?.toDouble() ?? 0.0;
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.payments),
                            title: Text(desc),
                            subtitle: Text(_df.format(dt)),
                            trailing: Text(_currency.format(val),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
                    ),
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AdaptiveRow(
        children: [
          const YallaSidebar(currentRoute: '/repairs/debts'),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('ذمم المركبات (من اليومية)'),
                actions: [
                  IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                ],
              ),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text('خطأ في التحميل:\n$_error',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red)),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: _rows.isEmpty
                              ? const Center(
                                  child: Text('لا توجد ملفات عليها ذمم'))
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemCount: _rows.length,
                                  itemBuilder: (_, i) {
                                    final m = _rows[i];
                                    final rid = m['rid'] as String;
                                    final paid = m['paid'] as double;
                                    final total = m['fileTotal'] as double;
                                    final remain = m['remain'] as double;
                                    final bn =
                                        (m['beneficiaryName'] as String?) ?? '';
                                    final vn =
                                        (m['vehicleNumber'] as String?) ?? '';
                                    final rec =
                                        (m['receivedDate'] as String?) ?? '';

                                    return Card(
                                      child: ListTile(
                                        leading: Icon(
                                          remain <= 0
                                              ? Icons.check_circle
                                              : Icons.warning_amber,
                                          color: remain <= 0
                                              ? AppColors.primary
                                              : Colors.orange,
                                        ),
                                        title: Text('ملف: $rid'),
                                        subtitle: Text(
                                          'المستفيد: $bn • المركبة: $vn • الاستلام: ${rec.isEmpty ? '—' : rec}',
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                                'قيمة الملف: ${_currency.format(total)}'),
                                            Text(
                                                'المدفوع: ${_currency.format(paid)}'),
                                            Text(
                                              'المتبقي: ${_currency.format(remain)}',
                                              style: TextStyle(
                                                color: remain <= 0
                                                    ? AppColors.primary
                                                    : Colors.red,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextButton.icon(
                                              onPressed: () =>
                                                  _showPayments(rid),
                                              icon: const Icon(Icons.list),
                                              label: const Text('تفاصيل'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}
