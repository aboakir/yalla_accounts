// 📁 lib/features/insurance_agent/policies/widgets/steps/step_insured_info.dart
//
// Step 2 — بيانات المؤمن له + شركة التأمين (Dropdown من DB)
// ✅ RTL
// ✅ تحميل شركات التأمين من جدول insurance_companies
// ✅ Validation كامل
// ✅ بدون Controllers داخل build
// ✅ NEW: نوع الوثيقة Dropdown (طرف ثالث / شامل)

import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepInsuredInfo extends StatefulWidget {
  final PolicyDraft draft;
  final GlobalKey<FormState> formKey;

  const StepInsuredInfo({
    super.key,
    required this.draft,
    required this.formKey,
  });

  @override
  State<StepInsuredInfo> createState() => _StepInsuredInfoState();
}

class _StepInsuredInfoState extends State<StepInsuredInfo> {
  late final TextEditingController _insuredNameCtrl;
  late final TextEditingController _insuredPhoneCtrl;

  List<String> _insurers = [];
  bool _loadingInsurers = true;

  // ✅ NEW: نوع الوثيقة
  static const List<String> _docTypes = ['طرف ثالث', 'شامل'];
  String? _docType;

  @override
  void initState() {
    super.initState();

    _insuredNameCtrl =
        TextEditingController(text: widget.draft.insuredName ?? '');
    _insuredPhoneCtrl =
        TextEditingController(text: widget.draft.insuredPhone ?? '');

    _docType = _readDraftDocType();
    if (_docType == null) {
      // افتراضي: طرف ثالث
      _docType = _docTypes.first;
      _writeDraftDocType(_docType);
    }

    _loadInsurers();
  }

  @override
  void dispose() {
    _insuredNameCtrl.dispose();
    _insuredPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInsurers() async {
    try {
      final db = await DBService.database;

      final rows = await db.query(
        'insurance_companies',
        orderBy: 'name ASC',
      );

      final names = rows
          .map((e) => (e['name'] ?? '').toString().trim())
          .where((n) => n.isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() {
        _insurers = names;
        _loadingInsurers = false;
      });

      // تثبيت قيمة افتراضية إذا لا يوجد اختيار سابق
      final current = (widget.draft.companyName ?? '').trim();
      if (current.isEmpty && names.isNotEmpty) {
        widget.draft.companyName = names.first;
      } else if (current.isNotEmpty && !names.contains(current)) {
        // إذا كانت القيمة القديمة غير موجودة بالقائمة، نخليها null فعليًا
        widget.draft.companyName = null;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInsurers = false);
    }
  }

  // ---------------------------------------------------------------------------
  // NEW: Draft helpers (safe read/write without compile errors)
  // ---------------------------------------------------------------------------
  String? _readDraftDocType() {
    try {
      final d = widget.draft as dynamic;

      // جرّب عدة أسماء حقول محتملة
      final v = d.documentType ??
          d.policyDocumentType ??
          d.coverageType ??
          d.policyType ??
          d.insuranceType;

      if (v == null) return null;

      final t = v.toString().trim();
      if (t.isEmpty) return null;

      // طَبِّع القيم لو كانت إنجليزية/اختصارات
      if (t.toLowerCase() == 'third' || t == 'tp' || t == 'third_party') {
        return 'طرف ثالث';
      }
      if (t.toLowerCase() == 'comprehensive' || t == 'full') {
        return 'شامل';
      }

      // إذا القيمة موجودة ضمن قائمتنا
      if (_docTypes.contains(t)) return t;

      return t;
    } catch (_) {
      return null;
    }
  }

  void _writeDraftDocType(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return;

    try {
      final d = widget.draft as dynamic;

      // حاول تكتبها على أكثر من اسم حقل محتمل
      try {
        d.documentType = v;
      } catch (_) {}
      try {
        d.policyDocumentType = v;
      } catch (_) {}
      try {
        d.coverageType = v;
      } catch (_) {}
      try {
        d.policyType = v;
      } catch (_) {}
      try {
        d.insuranceType = v;
      } catch (_) {}
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  String? _validateName(String? v) {
    final t = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return 'أدخل اسم المؤمن له';
    return null;
  }

  String? _validatePhone(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'أدخل رقم الهاتف';
    if (t.length < 7) return 'رقم الهاتف غير صحيح';
    return null;
  }

  String? _validateCompany(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'اختر شركة التأمين';
    return null;
  }

  String? _validateDocType(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'اختر نوع الوثيقة';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;

    return Form(
      key: widget.formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بيانات المؤمن له + شركة التأمين',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 16),

          // اسم المؤمن له
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _insuredNameCtrl,
            textAlign: TextAlign.right,
            decoration: const InputDecoration(
              labelText: 'اسم المؤمن له',
              border: OutlineInputBorder(),
            ),
            validator: _validateName,
            onChanged: (v) => d.insuredName = v.trim(),
          ),

          const SizedBox(height: 12),

          // رقم الهاتف
          TextFormField(
            inputFormatters: const [YallaDigitNormalizer()],
            controller: _insuredPhoneCtrl,
            textAlign: TextAlign.right,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              border: OutlineInputBorder(),
            ),
            validator: _validatePhone,
            onChanged: (v) => d.insuredPhone = v.trim(),
          ),

          const SizedBox(height: 12),

          // شركة التأمين (Dropdown)
          _loadingInsurers
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              : DropdownButtonFormField<String>(
                  value: (_insurers.contains((d.companyName ?? '').trim()))
                      ? (d.companyName ?? '').trim()
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'شركة التأمين',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('اختر شركة التأمين'),
                  items: _insurers
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c, textAlign: TextAlign.right),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    d.companyName = v;
                    widget.formKey.currentState?.validate();
                    setState(() {});
                  },
                  validator: _validateCompany,
                ),

          const SizedBox(height: 12),

          // ✅ NEW: نوع الوثيقة (Dropdown)
          DropdownButtonFormField<String>(
            value: (_docTypes.contains((_docType ?? '').trim()))
                ? (_docType ?? '').trim()
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'نوع الوثيقة',
              border: OutlineInputBorder(),
            ),
            hint: const Text('اختر نوع الوثيقة'),
            items: _docTypes
                .map(
                  (t) => DropdownMenuItem<String>(
                    value: t,
                    child: Text(t, textAlign: TextAlign.right),
                  ),
                )
                .toList(),
            onChanged: (v) {
              setState(() => _docType = v);
              _writeDraftDocType(v);
              widget.formKey.currentState?.validate();
            },
            validator: _validateDocType,
          ),

          const SizedBox(height: 16),

          // VIP
          SwitchListTile(
            value: d.isVip,
            onChanged: (v) => setState(() => d.isVip = v),
            title: const Text('VIP', textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
