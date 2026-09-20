// 📁 lib/features/repairs/widgets/steps/step_vehicle_data.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepVehicleData extends ConsumerStatefulWidget {
  /// مفتاح الـForm القادم من الشاشة الأب
  final GlobalKey<FormState> formKey;
  const StepVehicleData({super.key, required this.formKey});

  /// استدعِها من زر "التالي" في الشاشة الأب
  static bool validateStep(WidgetRef ref, GlobalKey<FormState> formKey) {
    // 1) تشغيل Validators المرئية
    final ok = formKey.currentState?.validate() ?? false;
    if (!ok) return false;

    // 2) تحقّق منطقي إضافي
    final f = ref.read(repairFormProvider);
    final now = DateTime.now();
    final max = now.add(const Duration(days: 365));
    if (f.vehicleType.trim().length < 3) return false;
    if (f.vehicleModel.trim().isEmpty) return false;
    if (f.vehicleNumber.trim().length < 4) return false;
    if (f.receivedDate.isAfter(max)) return false;

    return true;
  }

  @override
  ConsumerState<StepVehicleData> createState() => _StepVehicleDataState();
}

class _StepVehicleDataState extends ConsumerState<StepVehicleData> {
  late final TextEditingController _typeCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _numberCtrl;

  final _dateFmt = DateFormat('yyyy-MM-dd', 'ar');

  @override
  void initState() {
    super.initState();
    final f = ref.read(repairFormProvider);
    _typeCtrl = TextEditingController(text: f.vehicleType);
    _modelCtrl = TextEditingController(text: f.vehicleModel);
    _numberCtrl = TextEditingController(text: f.vehicleNumber);
  }

  @override
  void dispose() {
    _typeCtrl.dispose();
    _modelCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(repairFormProvider);
    final notifier = ref.read(repairFormProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Form(
        key: widget.formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            const Text(
              'بيانات المركبة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // نوع المركبة
            TextFormField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _typeCtrl,
              textAlign: TextAlign.right,
              decoration:
                  _dec(label: 'نوع المركبة', hint: 'مثال: تويوتا كورولا'),
              onChanged: (v) => notifier.updateVehicleType(v.trim()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'أدخل نوع المركبة';
                if (t.length < 3) return 'الحد الأدنى 3 أحرف';
                return null;
              },
            ),
            const SizedBox(height: 20),

            // موديل المركبة (سنة)
            TextFormField(
              controller: _modelCtrl,
              textAlign: TextAlign.right,
              decoration: _dec(label: 'موديل المركبة', hint: 'مثال: 2020'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                const YallaDigitNormalizer(),
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onChanged: (v) => notifier.updateVehicleModel(v.trim()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'أدخل موديل المركبة';
                final year = int.tryParse(t);
                final nowY = DateTime.now().year;
                if (year == null) return 'أدخل أرقامًا فقط (سنة)';
                if (year < 1980 || year > nowY + 1) {
                  return 'السنة يجب أن تكون بين 1980 و ${nowY + 1}';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),

            // رقم المركبة
            TextFormField(
              controller: _numberCtrl,
              textAlign: TextAlign.right,
              decoration: _dec(label: 'رقم المركبة', hint: 'مثال: 1234-XYZ'),
              inputFormatters: [
                const YallaDigitNormalizer(),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
                LengthLimitingTextInputFormatter(20),
              ],
              onChanged: (v) => notifier.updateVehicleNumber(v.trim()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'أدخل رقم المركبة';
                if (t.length < 4) return 'رقم المركبة قصير جدًا';
                return null;
              },
            ),
            const SizedBox(height: 24),

            // تاريخ الاستلام
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'تاريخ استلام المركبة:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: form.receivedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    locale: const Locale('ar'),
                  );
                  if (!context.mounted) return;
                  if (picked != null) {
                    // منع تاريخ مستقبلي مبالغ فيه (سنة واحدة للأمام كحد أعلى)
                    final max = DateTime.now().add(const Duration(days: 365));
                    if (picked.isAfter(max)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'تاريخ الاستلام لا يمكن أن يتجاوز سنة من اليوم'),
                      ));
                      return;
                    }
                    ref
                        .read(repairFormProvider.notifier)
                        .updateReceivedDate(picked);
                    setState(() {});
                  }
                },
                icon:
                    const Icon(Icons.calendar_month, color: AppColors.primary),
                label: Text(
                  _dateFmt.format(form.receivedDate),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: const BorderSide(color: AppColors.primary, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // تحقّق بصري سريع على التاريخ
            Builder(
              builder: (_) {
                final tooFuture = form.receivedDate
                    .isAfter(DateTime.now().add(const Duration(days: 365)));
                return Visibility(
                  visible: tooFuture,
                  child: const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'تحقق من صحة تاريخ الاستلام (أقصى حد +365 يومًا)',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: AppColors.primary, width: 2),
      ),
    );
  }
}
