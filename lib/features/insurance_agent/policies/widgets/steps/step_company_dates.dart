// 📁 lib/features/insurance_agent/policies/widgets/steps/step_company_dates.dart
//
// Step 3 — الشركة والتواريخ
// ✅ عرض اسم شركة التأمين تلقائياً من الخطوة السابقة (Read-only)
// ✅ اختيار تواريخ البداية والنهاية
// ✅ VIP
// ✅ Validation للتواريخ (بدون تكرار إدخال الشركة)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepCompanyDates extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final PolicyDraft draft;

  const StepCompanyDates({
    super.key,
    required this.formKey,
    required this.draft,
  });

  @override
  State<StepCompanyDates> createState() => _StepCompanyDatesState();
}

class _StepCompanyDatesState extends State<StepCompanyDates> {
  late final TextEditingController _companyCtrl;

  @override
  void initState() {
    super.initState();
    _companyCtrl = TextEditingController(text: widget.draft.companyName ?? '');
  }

  @override
  void didUpdateWidget(covariant StepCompanyDates oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ لو الشركة تغيّرت من خطوة سابقة (رجع/قدّم)، حدّث العرض
    final newName = widget.draft.companyName ?? '';
    if (_companyCtrl.text != newName) {
      _companyCtrl.text = newName;
    }
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial =
        (isStart ? widget.draft.startDate : widget.draft.endDate) ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      locale: const Locale('ar'),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        widget.draft.startDate = picked;

        // لو النهاية أقل من البداية أو فاضية -> خلّيها نفس البداية مؤقتاً
        if (widget.draft.endDate == null ||
            widget.draft.endDate!.isBefore(picked)) {
          widget.draft.endDate = picked;
        }
      } else {
        widget.draft.endDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd');

    final startText = widget.draft.startDate == null
        ? 'اختر تاريخ البداية'
        : df.format(widget.draft.startDate!);

    final endText = widget.draft.endDate == null
        ? 'اختر تاريخ النهاية'
        : df.format(widget.draft.endDate!);

    return Form(
      key: widget.formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ الشركة تُعرض فقط (بدون تعديل)
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _companyCtrl,
            readOnly: true,
            enableInteractiveSelection: false,
            decoration: const InputDecoration(
              labelText: 'شركة التأمين',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 12),

          AdaptiveRow(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(startText, overflow: TextOverflow.ellipsis),
                  onPressed: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: Text(endText, overflow: TextOverflow.ellipsis),
                  onPressed: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ✅ Validator للتواريخ (بدون حقل شركة)
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            enabled: false,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            validator: (_) {
              if (widget.draft.startDate == null) {
                return 'اختر تاريخ بداية التأمين';
              }
              if (widget.draft.endDate == null) {
                return 'اختر تاريخ انتهاء التأمين';
              }
              if (widget.draft.endDate!.isBefore(widget.draft.startDate!)) {
                return 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية';
              }
              return null;
            },
          ),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('VIP'),
            value: widget.draft.isVip,
            onChanged: (v) => setState(() => widget.draft.isVip = v),
          ),
        ],
      ),
    );
  }
}
