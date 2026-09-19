import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/repairs/widgets/repair_export_buttons.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_provider.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';
import 'package:yalla_accounts/shared/utils/pdf_file_saver.dart';
import 'package:yalla_accounts/shared/utils/repair_excel_export.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// زرّرات تصدير ملفات الإصلاح (PDF و Excel) مع عرض تقدم واحترافية أعلى.
class RepairExportButtons extends ConsumerStatefulWidget {
  const RepairExportButtons({super.key});

  @override
  ConsumerState<RepairExportButtons> createState() =>
      _RepairExportButtonsState();
}

class _RepairExportButtonsState extends ConsumerState<RepairExportButtons> {
  bool _isExportingPdf = false;
  bool _isExportingExcel = false;
  int _exportProgress = 0;
  int _exportTotal = 0;

  /// يعرض حوار تقدم التصدير مع شريط تقدّم (Progress Indicator).
  Future<void> _showProgressDialog(String title) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AdaptiveAlertDialog(
          title: Text(title, textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: _exportTotal > 0 ? _exportProgress / _exportTotal : null,
                minHeight: 6,
                backgroundColor: Colors.grey[200],
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text('جاري التصدير... ($_exportProgress / $_exportTotal)'),
            ],
          ),
        );
      },
    );
  }

  /// دالة تصدير جميع الملفات PDF واحدة تلو الأخرى مع تحديث شريط التقدم.
  Future<void> _exportAllPdf(List<Repair> repairs) async {
    setState(() {
      _isExportingPdf = true;
      _exportProgress = 0;
      _exportTotal = repairs.length;
    });

    // عرض حوار التقدم
    unawaited(_showProgressDialog('تصدير ملفات PDF'));

    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      for (var i = 0; i < repairs.length; i++) {
        final repair = repairs[i];

        // توليد PDF
        final pdfBytes = await RepairPdfGenerator.generate(repair);

        // اسم الملف يتضمن رقم المركبة والطابع الزمني للتمييز
        final fileName = 'كشف_${repair.vehicleNumber}_$timestamp';

        await PdfFileSaver.saveToDownloads(pdfBytes, fileName);
        if (!mounted) return;

        setState(() {
          _exportProgress = i + 1;
        });
      }

      // إغلاق حوار التقدم بعد الانتهاء
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      // إشعار بنجاح العملية
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تصدير كافة ملفات PDF بنجاح'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // إغلاق حوار التقدم في حال الخطأ
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '❌ حدث خطأ أثناء تصدير PDF: ${UserFacingError.message(e)}'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPdf = false;
          _exportProgress = 0;
          _exportTotal = 0;
        });
      }
    }
  }

  /// دالة تصدير ملف Excel واحد يحتوي كل البيانات دفعة واحدة.
  Future<void> _exportExcel(List<Repair> repairs) async {
    setState(() {
      _isExportingExcel = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء Excel...')),
    );

    try {
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'تقارير_الإصلاح_$timestamp';
      await RepairExcelExport.exportToExcel(repairs, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ ملف Excel بنجاح'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '❌ حدث خطأ أثناء تصدير Excel: ${UserFacingError.message(e)}'),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingExcel = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repairs = ref.watch(repairListProvider);

    return AdaptiveRow(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // زر تصدير PDF
        ElevatedButton.icon(
          onPressed: (repairs.isEmpty || _isExportingPdf || _isExportingExcel)
              ? null
              : () => _exportAllPdf(repairs),
          icon: const Icon(Icons.picture_as_pdf, size: 20),
          label: Text(
            _isExportingPdf ? 'جاري التصدير...' : 'تصدير PDF',
            style: const TextStyle(fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isExportingPdf ? Colors.grey[400] : AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 16),

        // زر تصدير Excel
        ElevatedButton.icon(
          onPressed: (repairs.isEmpty || _isExportingPdf || _isExportingExcel)
              ? null
              : () => _exportExcel(repairs),
          icon: const Icon(Icons.table_chart, size: 20),
          label: Text(
            _isExportingExcel ? 'جاري الإنشاء...' : 'تصدير Excel',
            style: const TextStyle(fontSize: 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isExportingExcel ? Colors.grey[400] : AppColors.secondary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
