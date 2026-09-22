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
  late final TextEditingController _policyNumberCtrl;

  @override
  void initState() {
    super.initState();
    _companyCtrl = TextEditingController(text: widget.draft.companyName ?? '');
    _policyNumberCtrl = TextEditingController(
      text: widget.draft.policyNumber ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant StepCompanyDates oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ لو الشركة تغيّرت من خطوة سابقة (رجع/قدّم)، حدّث العرض
    final newName = widget.draft.companyName ?? '';
    if (_companyCtrl.text != newName) {
      _companyCtrl.text = newName;
    }
    final policyNumber = widget.draft.policyNumber ?? '';
    if (_policyNumberCtrl.text != policyNumber) {
      _policyNumberCtrl.text = policyNumber;
    }
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _policyNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final earliest = isStart
        ? DateTime(now.year - 2)
        : (widget.draft.startDate?.add(const Duration(days: 1)) ??
            DateTime(now.year - 2));
    var initial =
        (isStart ? widget.draft.startDate : widget.draft.endDate) ?? now;
    if (initial.isBefore(earliest)) initial = earliest;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: DateTime(now.year + 10),
      locale: const Locale('ar'),
    );

    if (picked == null) return;

    setState(() {
      if (isStart) {
        widget.draft.startDate = picked;

        // لو النهاية أقل من البداية أو فاضية -> خلّيها نفس البداية مؤقتاً
        if (widget.draft.endDate == null ||
            !widget.draft.endDate!.isAfter(picked)) {
          widget.draft.endDate = picked.add(const Duration(days: 365));
        }
      } else {
        widget.draft.endDate = picked;
      }
    });
    widget.formKey.currentState?.validate();
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
          TextFormField(
            controller: _policyNumberCtrl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'رقم بوليصة شركة التأمين',
              hintText: 'أدخل الرقم الصادر عن شركة التأمين',
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? 'رقم بوليصة شركة التأمين مطلوب'
                : null,
            onChanged: (value) {
              final clean = value.trim();
              widget.draft.policyNumber = clean.isEmpty ? null : clean;
            },
            onSaved: (value) {
              final clean = (value ?? '').trim();
              widget.draft.policyNumber = clean.isEmpty ? null : clean;
            },
          ),

          const SizedBox(height: 12),

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

          // Validator مرئي للتواريخ، ولا يسمح بوثيقة مدتها صفر يوم.
          FormField<DateTime>(
            validator: (_) {
              if (widget.draft.startDate == null) {
                return 'اختر تاريخ بداية التأمين';
              }
              if (widget.draft.endDate == null) {
                return 'اختر تاريخ انتهاء التأمين';
              }
              if (!widget.draft.endDate!.isAfter(widget.draft.startDate!)) {
                return 'تاريخ الانتهاء يجب أن يكون بعد تاريخ البداية بيوم واحد على الأقل';
              }
              return null;
            },
            builder: (field) => field.hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      field.errorText!,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
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
