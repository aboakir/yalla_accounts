import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/settings/services/data_health_service.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class DataHealthScreen extends StatefulWidget {
  const DataHealthScreen({super.key});

  @override
  State<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends State<DataHealthScreen> {
  DataHealthReport? _report;
  bool _loading = false;
  bool _repairing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final report = await DataHealthService.instance.runHealthCheck();

      if (!mounted) return;

      setState(() {
        _report = report;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;

    try {
      final path = await DataHealthService.instance.export(report);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ التقرير في Downloads:\n$path'),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تصدير التقرير: $error'),
        ),
      );
    }
  }

  Future<void> _repair() async {
    final report = _report;

    if (report == null || report.repairableCount == 0 || _repairing) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AdaptiveAlertDialog(
        title: const Text('إصلاحات آمنة'),
        content: const Text(
          'سيتم إنشاء نسخة احتياطية أولًا، ثم تنفيذ الإصلاحات '
          'الحتمية فقط مثل مزامنة حقول Cache والروابط المشتقة. '
          'لن يتم تعديل مبالغ الفواتير المرحّلة أو حذف قيود GL.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إنشاء نسخة وإصلاح'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _repairing = true;
      _error = null;
    });

    try {
      final result = await DataHealthService.instance.repairSafeIssues();

      if (!mounted) return;

      setState(() {
        _report = result.report;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اكتمل الإصلاح الآمن.\n'
            'Backup: ${result.backupPath}\n'
            'Repair Log #${result.logId}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل الإصلاح ولم يعتمد: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _repairing = false;
        });
      }
    }
  }

  Color _statusColor(
    BuildContext context,
    DataHealthStatus status,
  ) {
    switch (status) {
      case DataHealthStatus.pass:
        return Colors.green;
      case DataHealthStatus.warning:
        return Colors.orange;
      case DataHealthStatus.error:
        return Colors.red;
      case DataHealthStatus.repairable:
        return Colors.blue;
    }
  }

  IconData _statusIcon(DataHealthStatus status) {
    switch (status) {
      case DataHealthStatus.pass:
        return Icons.check_circle_outline;
      case DataHealthStatus.warning:
        return Icons.warning_amber_rounded;
      case DataHealthStatus.error:
        return Icons.error_outline;
      case DataHealthStatus.repairable:
        return Icons.build_circle_outlined;
    }
  }

  String _statusLabel(DataHealthStatus status) {
    switch (status) {
      case DataHealthStatus.pass:
        return 'PASS';
      case DataHealthStatus.warning:
        return 'WARNING';
      case DataHealthStatus.error:
        return 'ERROR';
      case DataHealthStatus.repairable:
        return 'REPAIRABLE';
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('صحة البيانات والمحاسبة'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _run,
              tooltip: 'إعادة الفحص',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading && report == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _run,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null) _errorCard(_error!),
                    if (report != null) ...[
                      _summaryCard(report),
                      const SizedBox(height: 12),
                      _actionsCard(report),
                      const SizedBox(height: 12),
                      ...report.items.map(_healthItemCard),
                    ],
                    if (report == null && _error == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('لا يوجد تقرير بعد.'),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _summaryCard(DataHealthReport report) {
    final overallColor = report.errorCount > 0
        ? Colors.red
        : report.repairableCount > 0
            ? Colors.blue
            : report.warningCount > 0
                ? Colors.orange
                : Colors.green;

    final overallLabel = report.errorCount > 0
        ? 'توجد أخطاء تتطلب المعالجة'
        : report.repairableCount > 0
            ? 'توجد إصلاحات آمنة متاحة'
            : report.warningCount > 0
                ? 'سليم محاسبيًا مع ملاحظات للمراجعة'
                : 'سليم';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AdaptiveRow(
              children: [
                Icon(Icons.health_and_safety, color: overallColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    overallLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: overallColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _counterChip(
                  'PASS',
                  report.passCount,
                  Colors.green,
                ),
                _counterChip(
                  'WARNING',
                  report.warningCount,
                  Colors.orange,
                ),
                _counterChip(
                  'ERROR',
                  report.errorCount,
                  Colors.red,
                ),
                _counterChip(
                  'REPAIRABLE',
                  report.repairableCount,
                  Colors.blue,
                ),
                Chip(
                  avatar: const Icon(Icons.storage, size: 18),
                  label: Text('DB v${report.dbVersion}'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'آخر فحص: ${report.generatedAt.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsCard(DataHealthReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _loading ? null : _run,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('فحص الآن'),
            ),
            OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.download_outlined),
              label: const Text('تصدير JSON'),
            ),
            FilledButton.tonalIcon(
              onPressed:
                  report.repairableCount > 0 && !_repairing ? _repair : null,
              icon: _repairing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.build_outlined),
              label: Text(
                _repairing
                    ? 'جارٍ الإصلاح...'
                    : 'إصلاح الآمن (${report.repairableCount})',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counterChip(
    String label,
    int count,
    Color color,
  ) {
    return Chip(
      side: BorderSide(color: color.withOpacity(0.5)),
      avatar: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Text(
          count.toString(),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      label: Text(label),
    );
  }

  Widget _healthItemCard(DataHealthItem item) {
    final color = _statusColor(context, item.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          _statusIcon(item.status),
          color: color,
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.message),
              if (item.affected > 0 || item.amount != null) ...[
                const SizedBox(height: 5),
                Text(
                  [
                    if (item.affected > 0) 'الحالات: ${item.affected}',
                    if (item.amount != null)
                      'القيمة: ${MoneyFormatter.format(item.amount!)}',
                  ].join(' • '),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _statusLabel(item.status),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: Colors.red.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AdaptiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
