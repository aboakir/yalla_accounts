// -----------------------------------------------------------------------------
// 📁 lib/features/cheques/screens/cheque_details_screen.dart
//
// ChequeDetailsScreen — نسخة نهائية متوافقة 100% مع نظام التظهير الجديد
// -----------------------------------------------------------------------------
// • عرض كل تفاصيل الشيك
// • زر تظهير مرتبط بالـ chequeService.endorseCheque()
// • يدعم اختيار المورد + تاريخ التظهير
// • تحديث فوري بعد نجاح العملية
// • بدون أي تعديل على التصميم العام
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import '../models/cheque.dart';
import '../providers/cheque_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class ChequeDetailsScreen extends ConsumerWidget {
  final Cheque cheque;

  const ChequeDetailsScreen({super.key, required this.cheque});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final df = DateFormat('yyyy-MM-dd');
    final dfDT = DateFormat('yyyy-MM-dd HH:mm');
    final dfAmount = NumberFormat('#,##0.00', 'ar');
    final isDesktop = Responsive.isDesktop(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: const YallaAppBar(
        workshopName: 'Yallah Accounts',
        showThemeToggle: false,
        showSearch: false,
      ),
      drawer:
          isDesktop ? null : const YallaSidebar(currentRoute: '/cheques/list'),
      body: AdaptiveRow(
        children: [
          if (isDesktop) const YallaSidebar(currentRoute: '/cheques/list'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 750),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _buildDetails(
                    context: context,
                    ref: ref,
                    df: df,
                    dfDT: dfDT,
                    dfAmount: dfAmount,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // تفاصيل الشيك
  // ---------------------------------------------------------------------------
  Widget _buildDetails({
    required BuildContext context,
    required WidgetRef ref,
    required DateFormat df,
    required DateFormat dfDT,
    required NumberFormat dfAmount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "تفاصيل الشيك",
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 20),
        _section("معلومات عامة"),
        _row("رقم الشيك", cheque.chequeNo),
        _row("القيمة", "${dfAmount.format(cheque.amount)} ${cheque.currency}"),
        _row("UUID", cheque.uuid),
        const SizedBox(height: 16),
        _section("النوع والحالة"),
        _row("نوع الشيك", _typeLabel(cheque.chequeType)),
        _row("الحالة", _statusLabel(cheque.status)),
        const SizedBox(height: 16),
        _section("التظهير"),
        _row("مُظهّر؟", cheque.isEndorsed == 1 ? "نعم" : "لا"),
        if (cheque.endorsedAt != null)
          _row("تاريخ التظهير", cheque.endorsedAt!),
        if (cheque.supplierPid != null) _row("المستفيد", cheque.supplierPid!),
        const SizedBox(height: 16),
        _section("الطرف المصدر"),
        _row("المحرر", cheque.drawerName),
        const SizedBox(height: 12),
        _section("البنك"),
        _row("البنك", cheque.bankName),
        _row("الفرع", cheque.bankBranch),
        const SizedBox(height: 16),
        _section("التواريخ"),
        _row("الإصدار", df.format(cheque.issueDate)),
        _row("الاستحقاق", df.format(cheque.dueDate)),
        _row("تاريخ الإنشاء", dfDT.format(cheque.createdAt)),
        _row("آخر تعديل", dfDT.format(cheque.updatedAt)),
        if ((cheque.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          _section("ملاحظات"),
          Text(
            cheque.notes!,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 15),
          )
        ],
        const SizedBox(height: 30),
        _buttons(context, ref),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // الأزرار
  // ---------------------------------------------------------------------------
  Widget _buttons(BuildContext context, WidgetRef ref) {
    final linked = cheque.glEntryId != null ||
        (cheque.sourceType ?? '').trim().isNotEmpty ||
        (cheque.sourceId ?? '').trim().isNotEmpty;

    final canEdit = !linked || cheque.isLegacyIncomplete == 1;
    final canDelete = !linked;
    final canLifecycle = cheque.isLegacyIncomplete != 1;

    final actions = <Widget>[];

    if (canLifecycle && cheque.chequeType == ChequeType.incoming) {
      if (cheque.status == ChequeStatus.pending) {
        actions.add(
          _actionButton(
            "إيداع بالبنك",
            Icons.account_balance,
            () => _transition(context, ref, ChequeStatus.deposited),
          ),
        );
      }

      if (cheque.status == ChequeStatus.pending ||
          cheque.status == ChequeStatus.deposited) {
        actions.add(
          _actionButton(
            "تم التحصيل",
            Icons.check_circle,
            () => _transition(context, ref, ChequeStatus.collected),
          ),
        );
        actions.add(
          _actionButton(
            "مرتجع",
            Icons.undo,
            () => _transition(
              context,
              ref,
              ChequeStatus.returned,
              reason: "Returned cheque",
            ),
          ),
        );
        actions.add(
          _actionButton(
            "إلغاء",
            Icons.cancel,
            () => _transition(
              context,
              ref,
              ChequeStatus.cancelled,
              reason: "Cancelled cheque",
            ),
          ),
        );
      }
    }

    if (canLifecycle && cheque.chequeType == ChequeType.outgoing) {
      if (cheque.status == ChequeStatus.pending) {
        actions.add(
          _actionButton(
            "تم التسليم",
            Icons.outbox,
            () => _transition(context, ref, ChequeStatus.delivered),
          ),
        );
      }

      if (cheque.status == ChequeStatus.pending ||
          cheque.status == ChequeStatus.delivered) {
        actions.add(
          _actionButton(
            "تم الصرف من البنك",
            Icons.account_balance,
            () => _transition(context, ref, ChequeStatus.collected),
          ),
        );
        actions.add(
          _actionButton(
            "مرتجع",
            Icons.undo,
            () => _transition(
              context,
              ref,
              ChequeStatus.returned,
              reason: "Returned outgoing cheque",
            ),
          ),
        );
        if (cheque.isEndorsed != 1) {
          actions.add(
            _actionButton(
              "إلغاء",
              Icons.cancel,
              () => _transition(
                context,
                ref,
                ChequeStatus.cancelled,
                reason: "Cancelled outgoing cheque",
              ),
            ),
          );
        }
      }
    }

    return Column(
      children: [
        if (cheque.isLegacyIncomplete == 1)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              border: Border.all(color: Colors.amber.shade700),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              "هذا شيك تاريخي مستعاد. أكمل رقم الشيك والبنك والساحب "
              "وتاريخ الاستحقاق قبل تسجيل أي حركة عليه.",
              textAlign: TextAlign.center,
            ),
          ),
        AdaptiveRow(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.edit),
              label: Text(
                cheque.isLegacyIncomplete == 1
                    ? "استكمال بيانات الشيك"
                    : "تعديل",
              ),
              onPressed: canEdit
                  ? () async {
                      final updated = await Navigator.pushNamed(
                        context,
                        AppRoutes.chequesEdit,
                        arguments: cheque,
                      );
                      if (updated == true && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    }
                  : null,
            ),
            const SizedBox(width: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.delete),
              label: const Text("حذف"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: canDelete ? () => _delete(context, ref) : null,
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: actions,
          ),
        ],
        const SizedBox(height: 20),
        if (cheque.chequeType == ChequeType.incoming &&
            cheque.status == ChequeStatus.pending &&
            cheque.isEndorsed != 1 &&
            cheque.isLegacyIncomplete != 1)
          ElevatedButton.icon(
            icon: const Icon(Icons.call_made),
            label: const Text("تظهير الشيك لمورد"),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _endorseDialog(context, ref),
          ),
      ],
    );
  }

  Widget _actionButton(
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return ElevatedButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
    );
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    ChequeStatus status, {
    String? reason,
  }) async {
    final id = cheque.id;
    if (id == null) return;

    try {
      await ref.read(chequeServiceProvider).transitionStatus(
            chequeId: id,
            status: status,
            reason: reason,
            eventDate: DateTime.now(),
          );

      await ref.read(chequeProvider.notifier).loadFiltered(
            ref.read(chequeFilterProvider),
          );

      if (!context.mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("تعذر تحديث حالة الشيك: $e")),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // نافذة اختيار المورّد + التاريخ
  // ---------------------------------------------------------------------------
  Future<void> _endorseDialog(BuildContext context, WidgetRef ref) async {
    String? supplierPid;
    DateTime date = DateTime.now();

    final db = await DBService.database;
    final suppliers = await db.query("suppliers");
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AdaptiveAlertDialog(
          title: const Text("تظهير الشيك"),
          content: StatefulBuilder(
            builder: (ctx, setSt) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "اختر المورد"),
                    value: supplierPid,
                    items: suppliers.map((s) {
                      final pid = (s['pid'] ?? "").toString();
                      final name = (s['name'] ?? pid).toString();

                      return DropdownMenuItem<String>(
                        value: pid,
                        child: Text(
                          name,
                          textAlign: TextAlign.right,
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => setSt(() => supplierPid = v),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setSt(() => date = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration:
                          const InputDecoration(labelText: "تاريخ التظهير"),
                      child: Text(DateFormat("yyyy-MM-dd").format(date)),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.pop(ctx),
            ),
            ElevatedButton(
              child: const Text("تظهير"),
              onPressed: () async {
                if (supplierPid == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("يجب اختيار المورد"),
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                await _endorse(context, ref, supplierPid!, date);
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // تنفيذ التظهير بالحقيقي
  // ---------------------------------------------------------------------------
  Future<void> _endorse(
    BuildContext context,
    WidgetRef ref,
    String supplierPid,
    DateTime endorseDate,
  ) async {
    try {
      await ref.read(chequeServiceProvider).endorseCheque(
            chequeId: cheque.id!,
            supplierPid: supplierPid,
            endorsementDate: endorseDate,
          );

      ref.invalidate(chequeProvider);
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("تم تظهير الشيك بنجاح"),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("خطأ أثناء التظهير: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // حذف الشيك
  // ---------------------------------------------------------------------------
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text("حذف الشيك"),
        content: const Text("هل أنت متأكد من الحذف؟"),
        actions: [
          TextButton(
            child: const Text("إلغاء"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text("حذف"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(chequeProvider.notifier).deleteCheque(cheque.id!);

      if (context.mounted) Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  String _typeLabel(ChequeType t) {
    switch (t) {
      case ChequeType.incoming:
        return "وارد";
      case ChequeType.outgoing:
        return "صادر";
      case ChequeType.collection:
        return "قيد التحصيل";
    }
  }

  String _statusLabel(ChequeStatus s) {
    switch (s) {
      case ChequeStatus.pending:
        return "معلّق";
      case ChequeStatus.collected:
        return "مُحصّل";
      case ChequeStatus.returned:
        return "راجع";
      case ChequeStatus.cancelled:
        return "ملغى";
      case ChequeStatus.delivered:
        return "مُسلّم";
      case ChequeStatus.deposited:
        return "مودع";
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.textDark,
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AdaptiveRow(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
