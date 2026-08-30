// 📁 lib/features/insurance_agent/policies/widgets/steps/step_vehicle_info.dart
//
// Step 1 — بيانات المركبة (FINAL + FIXED)
// ✅ Form حقيقي + Validation + onSaved
// ✅ RTL + TextAlign Right
// ✅ FIX: يمنع NoSuchMethodError عند غياب carPrice/vehiclePrice
// ✅ NEW: حقل "سعر المركبة" مع توافق كامل (carPrice أو vehiclePrice) + محاولة ضبط النوع (double/String)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yalla_accounts/core/constants/colors.dart';

import '../../models/policy_draft.dart';

class StepVehicleInfo extends StatelessWidget {
  final PolicyDraft draft;
  final GlobalKey<FormState> formKey;

  const StepVehicleInfo({
    super.key,
    required this.draft,
    required this.formKey,
  });

  // ----------------------------
  // Safe read helpers
  // ----------------------------
  dynamic _tryReadCarPrice() {
    try {
      return (draft as dynamic).carPrice;
    } catch (_) {
      return null;
    }
  }

  dynamic _tryReadVehiclePrice() {
    try {
      return (draft as dynamic).vehiclePrice;
    } catch (_) {
      return null;
    }
  }

  String _priceInitial() {
    // مهم جدًا: لا تستخدم carPrice ?? vehiclePrice مباشرة
    // لأن محاولة قراءة carPrice قد ترمي NoSuchMethodError قبل الوصول للـ ??
    final v1 = _tryReadCarPrice();
    if (v1 != null) return v1.toString().trim();

    final v2 = _tryReadVehiclePrice();
    if (v2 != null) return v2.toString().trim();

    return '';
  }

  // ----------------------------
  // Safe write helpers
  // ----------------------------
  void _tryWriteCarPrice(dynamic value) {
    try {
      (draft as dynamic).carPrice = value;
    } catch (_) {
      // ignore
    }
  }

  void _tryWriteVehiclePrice(dynamic value) {
    try {
      (draft as dynamic).vehiclePrice = value;
    } catch (_) {
      // ignore
    }
  }

  void _savePrice(String raw) {
    final t = raw.trim();

    // نحاول نحوله لرقم (الأفضل)
    final asDouble = double.tryParse(t);

    // 1) اكتب كـ double لو ممكن
    if (asDouble != null) {
      // جرّب carPrice double
      _tryWriteCarPrice(asDouble);
      // جرّب vehiclePrice double
      _tryWriteVehiclePrice(asDouble);

      // بعض نسخك القديمة ممكن تكون String، لو تعذّر التعيين كـ double
      // نجرّب كـ String كذلك (بدون ما نعمل تعارض)
      _tryWriteCarPrice(t);
      _tryWriteVehiclePrice(t);
      return;
    }

    // 2) لو مش رقم، نخليها String (بس غالبًا لن تمر الفاليديشن)
    _tryWriteCarPrice(t);
    _tryWriteVehiclePrice(t);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Form(
                key: formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'بيانات المركبة',
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),

                    _tf(
                      label: 'رقم المركبة',
                      hint: 'مثال: 7-123-45',
                      initialValue:
                          draft.vehiclePlate ?? draft.vehicleNumber ?? '',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      onSaved: (v) {
                        draft.vehiclePlate = (v ?? '').trim();
                        // legacy sync
                        draft.vehicleNumber = draft.vehiclePlate;
                      },
                    ),

                    const SizedBox(height: 10),
                    _tf(
                      label: 'نوع المركبة',
                      hint: 'مثال: KIA / Hyundai / BMW',
                      initialValue:
                          draft.vehicleMake ?? draft.vehicleType ?? '',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      onSaved: (v) {
                        draft.vehicleMake = (v ?? '').trim();
                        // legacy sync
                        draft.vehicleType = draft.vehicleMake;
                      },
                    ),

                    const SizedBox(height: 10),
                    _tf(
                      label: 'موديل السنة',
                      hint: 'مثال: 2021',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      initialValue: draft.vehicleModelYear ?? '',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      onSaved: (v) {
                        draft.vehicleModelYear = (v ?? '').trim();
                      },
                    ),

                    const SizedBox(height: 10),
                    _tf(
                      label: 'حجم المحرك (CC)',
                      hint: 'مثال: 1600',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      initialValue: draft.engineCc ?? draft.engineSize ?? '',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                      onSaved: (v) {
                        draft.engineCc = (v ?? '').trim();
                        // legacy sync
                        draft.engineSize = draft.engineCc;
                      },
                    ),

                    // ✅ NEW: سعر المركبة
                    const SizedBox(height: 10),
                    _tf(
                      label: 'سعر المركبة',
                      hint: 'مثال: 65000',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      initialValue: _priceInitial(),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'مطلوب';
                        final n = double.tryParse(t);
                        if (n == null) return 'رقم غير صحيح';
                        if (n <= 0) return 'يجب أن يكون أكبر من صفر';
                        return null;
                      },
                      onSaved: (v) {
                        _savePrice(v ?? '');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tf({
    required String label,
    required String hint,
    required String initialValue,
    required String? Function(String?) validator,
    required void Function(String?) onSaved,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      onSaved: onSaved,
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
