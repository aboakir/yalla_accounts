// 📁 lib/features/employees/screens/payroll_periods_screen.dart
//
// PayrollPeriodsScreen — إدارة أشهر الرواتب: عرض، قفل، فتح، ملاحظات.
// يعتمد PayrollPeriodsService كمصدر وحيد للقفل.
// تحسينات:
//  - تهيئة تلقائية لآخر 12 شهر إذا الجدول فارغ.
//  - تنسيق locked_at لقراءة أوضح.
//  - تعديل الملاحظة لشهر مقفول بدون فك القفل.
//  - تحقّق Limit ومنع القيم غير المنطقية.
//  - RefreshIndicator + Snackbar بعد كل إجراء.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

import 'package:yalla_accounts/features/employees/services/payroll_periods_service.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PayrollPeriodsScreen extends StatefulWidget {
  const PayrollPeriodsScreen({super.key});

  @override
  State<PayrollPeriodsScreen> createState() => _PayrollPeriodsScreenState();
}

class _PayrollPeriodsScreenState extends State<PayrollPeriodsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _rows = [];
  final _limitCtrl = TextEditingController(text: '24');

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _safeLimit() {
    final n = int.tryParse(_limitCtrl.text.trim());
    if (n == null || n <= 0) return 24;
    if (n > 120) return 120;
    return n;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lim = _safeLimit();

      // اقرأ الفترات
      var list = await PayrollPeriodsService.listPeriods(limit: lim);

      // إذا الجدول فارغ تماماً → أنشئ آخر 12 شهر
      if (list.isEmpty) {
        final now = DateTime.now();
        for (int i = 0; i < 12; i++) {
          final d = DateTime(now.year, now.month - i, 1);
          await PayrollPeriodsService.ensurePeriodRow(d.year, d.month);
        }
        list = await PayrollPeriodsService.listPeriods(limit: lim);
      }

      setState(() => _rows = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureCurrentMonth() async {
    final now = DateTime.now();
    await PayrollPeriodsService.ensurePeriodRow(now.year, now.month);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم تجهيز شهر الحالي')));
  }

  Future<void> _lockWithNote(int year, int month) async {
    String? note;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: Text('قفل $year-${month.toString().padLeft(2, '0')}'),
        content: TextField(
          inputFormatters: const [YallaDigitNormalizer()],
          decoration: const InputDecoration(
            labelText: 'ملاحظة (اختياري)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => note = v.trim().isEmpty ? null : v.trim(),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('قفل')),
        ],
      ),
    );
    if (ok == true) {
      await PayrollPeriodsService.lockPeriod(year, month, note: note);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم القفل')));
    }
  }

  Future<void> _editNote(int year, int month, String current) async {
    String note = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تعديل الملاحظة'),
        content: TextField(
          inputFormatters: const [YallaDigitNormalizer()],
          controller: TextEditingController(text: current),
          decoration: const InputDecoration(
            labelText: 'ملاحظة',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => note = v.trim(),
          minLines: 1,
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true) {
      // إعادة قفل بنفس الشهر مع الملاحظة الجديدة لتحديث note
      await PayrollPeriodsService.lockPeriod(year, month,
          note: note.isEmpty ? null : note);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث الملاحظة')));
    }
  }

  Future<void> _unlock(int year, int month) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('فتح الفترة'),
        content: Text('فتح $year-${month.toString().padLeft(2, '0')}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('فتح')),
        ],
      ),
    );
    if (ok == true) {
      await PayrollPeriodsService.unlockPeriod(year, month);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم الفتح')));
    }
  }

  @override
  void dispose() {
    _limitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: YallaSidebar(currentRoute: '/employees/payroll-periods')),
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: YallaAppBar(
          workshopName: 'فترات الرواتب',
          actions: [],
        ),
      ),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: '/employees/payroll-periods'),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AdaptiveRow(
                    children: [
                      SizedBox(
                        width: 140,
                        child: TextField(
                          inputFormatters: const [YallaDigitNormalizer()],
                          controller: _limitCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Limit',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تحديث'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _ensureCurrentMonth,
                        icon: const Icon(Icons.add),
                        label: const Text('Ensure شهر الحالي'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Text('خطأ: $_error',
                        style: const TextStyle(color: Colors.red))
                  else if (_rows.isEmpty)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('لا توجد فترات'),
                    ))
                  else
                    _buildTable(df),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(DateFormat df) {
    final rows = _rows.map((m) {
      final year = (m['year'] as int?) ?? 0;
      final month = (m['month'] as int?) ?? 0;
      final status = (m['status'] ?? '').toString();
      final lockedAtRaw = (m['locked_at'] ?? '').toString();
      final note = (m['note'] ?? '').toString();

      final isLocked = status == 'LOCKED';

      String lockedAtPretty = '—';
      if (lockedAtRaw.isNotEmpty) {
        final dt = DateTime.tryParse(lockedAtRaw);
        lockedAtPretty = dt == null ? lockedAtRaw : df.format(dt);
      }

      return DataRow(
        cells: [
          DataCell(Text(year.toString())),
          DataCell(Text(month.toString().padLeft(2, '0'))),
          DataCell(Chip(
            label: Text(isLocked ? 'LOCKED' : 'OPEN',
                style: TextStyle(
                  color: isLocked ? Colors.red : Colors.green,
                  fontWeight: FontWeight.w600,
                )),
            backgroundColor:
                (isLocked ? Colors.red : Colors.green).withOpacity(0.08),
            side: BorderSide(
                color: (isLocked ? Colors.red : Colors.green).withOpacity(0.3)),
          )),
          DataCell(Text(
            lockedAtPretty,
            overflow: TextOverflow.ellipsis,
          )),
          DataCell(SizedBox(
            width: 260,
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: Text(note.isEmpty ? '—' : note,
                      overflow: TextOverflow.ellipsis),
                ),
                if (isLocked)
                  IconButton(
                    tooltip: 'تعديل الملاحظة',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editNote(year, month, note),
                  ),
              ],
            ),
          )),
          DataCell(AdaptiveRow(
            children: [
              if (!isLocked)
                ElevatedButton.icon(
                  onPressed: () => _lockWithNote(year, month),
                  icon: const Icon(Icons.lock),
                  label: const Text('قفل'),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _unlock(year, month),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('فتح'),
                ),
            ],
          )),
        ],
      );
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: AdaptiveDataTable(
        columns: const [
          DataColumn(label: Text('السنة')),
          DataColumn(label: Text('الشهر')),
          DataColumn(label: Text('الحالة')),
          DataColumn(label: Text('وقت القفل')),
          DataColumn(label: Text('ملاحظة')),
          DataColumn(label: Text('إجراء')),
        ],
        rows: rows,
      ),
    );
  }
}
