import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';

// خدمات DB + الفواتير
import 'package:sqflite/sqflite.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/finance/invoices/services/invoice_service.dart';
import 'package:yalla_accounts/features/finance/invoices/screens/invoice_view_screen.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class RepairCard extends StatelessWidget {
  final Repair repair;
  final VoidCallback? onTap;
  final VoidCallback? onView;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onApproveFinalAmount;

  const RepairCard({
    super.key,
    required this.repair,
    this.onTap,
    this.onView,
    this.onEdit,
    this.onDelete,
    this.onApproveFinalAmount,
  });

  Color _paymentColor(String? status) {
    switch (status?.trim()) {
      case 'مسدد':
        return AppColors.success;
      case 'مسدد جزئي':
        return AppColors.warning;
      case 'غير مسدد':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  Color _insuranceColor(String? status) {
    switch (status?.trim()) {
      case 'بانتظار تسليم الفاتورة':
        return Colors.indigo;
      case 'بانتظار تسديد التعويضات':
        return Colors.purple;
      case 'بانتظار تسديد المالية':
        return Colors.teal;
      case 'بانتظار الصرف':
        return Colors.amber;
      case 'تم الصرف':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 480;
    final paid = (repair.totalPaidAmount ?? repair.paidAmount ?? 0).toDouble();
    final total = (repair.totalFileValue ?? repair.fileValue ?? 0).toDouble();
    final remaining = total - paid;
    final theme = Theme.of(context).textTheme;
    final dateText = DateFormat('yyyy-MM-dd').format(repair.receivedDate);
    final paymentColor = _paymentColor(repair.paymentStatus);
    final insuranceColor = _insuranceColor(repair.insuranceStatus);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: paymentColor, width: 2),
      ),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap ?? onView,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AdaptiveRow(
            children: [
              _RepairThumb(
                repairId: repair.id,
                fallbackFirstPath: repair.imagePaths.isNotEmpty
                    ? repair.imagePaths.first
                    : null,
                size: isNarrow ? 56 : 64,
                radius: isNarrow ? 28 : 32,
              ),
              const SizedBox(width: 12),

              // البيانات
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${repair.vehicleType} • ${repair.vehicleNumber}',
                      style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: isNarrow ? 14 : 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${repair.beneficiaryName} · $dateText',
                      style: theme.bodySmall?.copyWith(color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    AdaptiveRow(
                      children: [
                        Text(
                          'المدفوع: ${MoneyFormatter.format(paid)}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'المتبقي: ${MoneyFormatter.format(remaining)}',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (repair.beneficiaryType == 'شركة تأمين' &&
                        repair.finalApprovedAmount != null)
                      Text(
                        '💰 السعر المعتمد: ${MoneyFormatter.format(repair.finalApprovedAmount!)}',
                        style: theme.bodySmall?.copyWith(
                          color: Colors.green[900],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    AdaptiveRow(
                      children: [
                        Icon(Icons.verified,
                            color: insuranceColor, size: isNarrow ? 14 : 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            repair.insuranceStatus,
                            style: theme.bodySmall?.copyWith(
                              color: insuranceColor,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // الأزرار والحالة
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (repair.finalApprovedAmount != null)
                    Chip(
                      label: Text(
                        'معتمد ✅',
                        style: TextStyle(
                          color: Colors.green[800],
                          fontWeight: FontWeight.bold,
                          fontSize: isNarrow ? 10 : 12,
                        ),
                      ),
                      backgroundColor: Colors.green[50],
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.green[200]!),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _InvoiceButton(repair: repair),
                  const SizedBox(height: 8),
                  if (_actionIcons(isNarrow).isNotEmpty)
                    isNarrow
                        ? Column(children: _actionIcons(isNarrow))
                        : AdaptiveRow(children: _actionIcons(isNarrow)),
                  if (repair.finalApprovedAmount == null &&
                      !repair.isLedgerSynced &&
                      onApproveFinalAmount != null)
                    TextButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('اعتماد السعر'),
                      onPressed: onApproveFinalAmount,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green[700],
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actionIcons(bool compact) {
    final icons = <Widget>[];
    if (onView != null) {
      icons.add(_icon(
          icon: Icons.visibility_outlined,
          tooltip: 'عرض',
          action: onView!,
          compact: compact));
    }
    if (onEdit != null) {
      icons.add(_icon(
          icon: Icons.edit_outlined,
          tooltip: 'تعديل',
          action: onEdit!,
          compact: compact));
    }
    if (onDelete != null) {
      icons.add(_icon(
          icon: Icons.delete_outline,
          tooltip: 'حذف',
          action: onDelete!,
          compact: compact,
          color: AppColors.danger));
    }
    return icons;
  }

  Widget _icon({
    required IconData icon,
    required String tooltip,
    required VoidCallback action,
    bool compact = false,
    Color? color,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 4),
      child: IconButton(
        icon: Icon(icon,
            size: compact ? 20 : 24, color: color ?? AppColors.primary),
        onPressed: action,
        tooltip: tooltip,
        splashRadius: 20,
        constraints: BoxConstraints.tightFor(
            width: compact ? 32 : 40, height: compact ? 32 : 40),
      ),
    );
  }
}

/// مصغّر صورة الغلاف: يحاول أولًا thumbnail_path ثم يسقط على أول صورة فعلية.
class _RepairThumb extends StatelessWidget {
  final String repairId;
  final String? fallbackFirstPath;
  final double size;
  final double radius;

  const _RepairThumb({
    required this.repairId,
    required this.fallbackFirstPath,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: DBService.getRepairThumbnailPath(repairId),
      builder: (context, snap) {
        String? path = snap.data;
        File? file;

        try {
          if (path != null && path.isNotEmpty) {
            final f = File(path);
            if (f.existsSync()) file = f;
          }
          if (file == null && fallbackFirstPath != null) {
            final f = File(fallbackFirstPath!);
            if (f.existsSync()) file = f;
          }
        } catch (_) {}

        if (file != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }

        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.lightGrey,
          child: Icon(Icons.directions_car,
              size: radius, color: AppColors.primary),
        );
      },
    );
  }
}

class _InvoiceButton extends StatelessWidget {
  final Repair repair;
  const _InvoiceButton({required this.repair});

  double _num(Object? v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final hasInv = (repair.invoiceId ?? '').trim().isNotEmpty;
    final label = hasInv ? 'عرض الفاتورة' : 'إنشاء فاتورة';
    final icon = hasInv ? Icons.receipt_long : Icons.request_quote;

    return ElevatedButton.icon(
      onPressed: () => _handle(context, hasInv),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Future<void> _handle(BuildContext context, bool hasInv) async {
    try {
      String? invoiceId = repair.invoiceId;

      if (!hasInv) {
        final db = await DBService.database;

        // إجمالي من سطور الإصلاح أو أكبر قيمة من الحقول المالية
        final fallback = [
          _num(repair.incomeAmount),
          _num(repair.finalApprovedAmount),
          _num(repair.workCost),
          _num(repair.fileValue),
        ].fold<double>(0, (m, v) => v > m ? v : m);

        final total = await _computeTotal(db, repair.id, fallback: fallback);

        if (total <= 0) {
          _snack(context, 'الإجمالي صفر. أضف بنودًا أو قيمة قبل الفوترة',
              err: true);
          return;
        }

        invoiceId = await InvoiceService.I.createInvoice(
          repairId: repair.id,
          date: DateTime.now(),
          total: double.parse(total.toStringAsFixed(2)),
          status: 'unpaid',
          notes: 'فاتورة إصلاح ${repair.id}',
          clientId: repair.clientId,
          postToGL: true,
        );

        // تحديث كلا الحقلين حفاظًا على التوافق
        await db.update(
          'repairs',
          {'invoice_id': invoiceId, 'invoiceId': invoiceId},
          where: 'id = ?',
          whereArgs: [repair.id],
        );

        _snack(context, 'تم إنشاء الفاتورة: $invoiceId');
      }

      await InvoiceViewScreen.open(context, invoiceId!);
    } catch (e) {
      _snack(context, 'فشل: $e', err: true);
    }
  }

  Future<double> _computeTotal(Database db, String repairId,
      {required double fallback}) async {
    final r = await db.rawQuery(
      'SELECT IFNULL(SUM(total),0) s FROM repair_lines WHERE repair_id=?',
      [repairId],
    );
    final s = r.first['s'];
    final lines = s is num ? s.toDouble() : (double.tryParse('$s') ?? 0);
    return lines > 0 ? lines : fallback;
  }

  void _snack(BuildContext ctx, String msg, {bool err = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: err ? Colors.red : null,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
