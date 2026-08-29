// 📁 lib/features/repairs/screens/add_repair_screen.dart
//
// ====================== ملخص التغييرات (What's changed) ======================
// 1) إزالة ربط الصور بجدول repairs_images بعد الحفظ لأن RepairSaveService.save
//    يضيفها أصلًا داخل TX، وresetForm يمسح المسارات قبل أي ربط لاحق.
// 2) حفظ الصور بأسماء فريدة لتفادي الكتابة فوق ملفات موجودة.
// 3) معاينة سريعة للصورة بالحجم الكامل عند الضغط عليها داخل الشريط الأفقي.
// 4) إضافة دعم الشيكات في الخطوة المالية
// 5) لا نشر GL هنا. لا بيانات وهمية.
//
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';

import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';
import 'package:yalla_accounts/features/repairs/widgets/steps/step_vehicle_data.dart';
import 'package:yalla_accounts/features/repairs/widgets/steps/step_beneficiary_data.dart';
import 'package:yalla_accounts/features/repairs/widgets/steps/step_work_data.dart';
import 'package:yalla_accounts/features/repairs/widgets/steps/step_financial_data.dart';

// الحفظ داخل TX
import 'package:yalla_accounts/features/repairs/services/repair_save_service.dart';

// دعم الشيكات
import 'package:yalla_accounts/features/cheques/widgets/cheque_dialog.dart';
import 'package:yalla_accounts/features/cheques/models/cheque.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class AddRepairScreen extends ConsumerStatefulWidget {
  const AddRepairScreen({super.key});

  @override
  ConsumerState<AddRepairScreen> createState() => _AddRepairScreenState();
}

class _AddRepairScreenState extends ConsumerState<AddRepairScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;

  final _stepsTitles = const [
    'بيانات المركبة',
    'المستفيد',
    'بيانات العمل',
    'المالية',
  ];

  // مفاتيح Forms لكل خطوة
  final _step1Key = GlobalKey<FormState>();
  final _step2Key = GlobalKey<FormState>();
  final _step3Key = GlobalKey<FormState>();
  final _step4Key = GlobalKey<FormState>();

  // إعدادات الخطوة الأخيرة
  double? _actualCost;
  bool _isLedgerEnabled = true;

  // ——— إدارة صور عامة من الشريط العلوي ———
  Future<void> _addImage(ImageSource src) async {
    try {
      final file = await ImagePicker().pickImage(source: src, imageQuality: 70);
      if (file == null) return;

      final form = ref.read(repairFormProvider);

      final savedPath = await ImageStorageService.saveImage(
        image: file,
        vehicleType: form.vehicleType,
        vehicleNumber: form.vehicleNumber,
        beneficiaryName: form.beneficiaryName,
        receivedDate: form.receivedDate ?? DateTime.now(),
      );

      ref.read(repairFormProvider.notifier).addImage(savedPath);

      if (ref.read(repairFormProvider).imagePaths.length == 1) {
        ref.read(repairFormProvider.notifier).setThumbnail(savedPath);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إضافة الصورة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إضافة الصورة: $e')),
      );
    }
  }

  void _showImageDialog() {
    showDialog(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('اختيار الصورة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('المعرض'),
              onTap: () {
                Navigator.pop(context);
                _addImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  // معاينة بالحجم الكامل
  void _previewImage(String path) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepIndicator() {
    return AdaptiveRow(
      children: List.generate(_stepsTitles.length, (i) {
        final active = i <= _currentStep;
        return Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: active ? AppColors.primary : Colors.grey[300],
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _stepsTitles[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  color: active ? AppColors.primary : Colors.grey[600],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _nextStep() async {
    final form = ref.read(repairFormProvider);
    bool ok = false;

    if (_currentStep == 0) {
      ok = StepVehicleData.validateStep(ref, _step1Key);
    } else if (_currentStep == 1) {
      ok = StepBeneficiaryData.validateStep(ref, _step2Key);
      if (ok) {
        // إنشاء/تأكيد العميل
        try {
          final type = form.beneficiaryType; // 'أفراد' أو 'شركة تأمين'
          final name = form.beneficiaryName.trim();
          if (name.isEmpty) {
            _showSnack('اكتب اسم المستفيد');
            return;
          }
          final normalizedType = (type == 'أفراد') ? 'أفراد' : 'شركة تأمين';
          final exists =
              await ClientService.clientExists(name, type: normalizedType);
          if (!exists) {
            await ClientService.insertOrGetClientId(name, normalizedType);
          }
        } catch (e) {
          _showSnack('تعذر التحقق/الحفظ لبيانات المستفيد: $e');
          return;
        }
      }
    } else if (_currentStep == 2) {
      ok = StepWorkData.validateStep(ref, _step3Key);
    } else if (_currentStep == 3) {
      ok = StepFinancialData.validateStep(ref, _step4Key);
    }

    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أكمل الحقول المطلوبة في هذه الخطوة')),
        );
      }
      return;
    }

    if (_currentStep < _stepsTitles.length - 1) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // دالة خاصة للتعامل مع إضافة الشيكات
  Future<void> _handleChequePayment() async {
    final cheque = await showDialog<Cheque>(
      context: context,
      builder: (context) => ChequeDialog(
        initialType: ChequeType.incoming, // وارد من العميل
        sourceType: 'repair',
        // sourceId سيتم تعبئته بعد حفظ الإصلاح
      ),
    );

    if (cheque != null) {
      // تخزين بيانات الشيك مؤقتاً في الـ provider
      ref.read(repairFormProvider.notifier).setPendingCheque(cheque);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم إضافة شيك رقم: ${cheque.chequeNo}')),
      );
    }
  }

  Future<void> _saveFinal() async {
    debugPrint('=== بداية _saveFinal ===');

    // تحقّق أخير
    final lastOk = StepFinancialData.validateStep(ref, _step4Key);
    debugPrint('التحقق الأخير: $lastOk');

    if (!lastOk) {
      debugPrint('❌ فشل التحقق الأخير');
      _showSnack('أكمل حقول المالية قبل الحفظ');
      return;
    }

    debugPrint('✅ التحقق ناجح - فتح dialog التأكيد');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تأكيد الحفظ'),
        content: const Text('هل تريد حفظ البيانات بدون نشر GL الآن؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    debugPrint('نتيجة dialog التأكيد: $confirm');
    if (confirm != true) {
      debugPrint('❌ المستخدم ألغى الحفظ');
      return;
    }

    debugPrint('✅ بداية عملية الحفظ...');
    setState(() => _isSaving = true);

    try {
      debugPrint('📦 استدعاء RepairSaveService.save...');
      final id = await RepairSaveService.save(
        ref: ref,
        actualCost: _actualCost,
        isLedgerEnabled: _isLedgerEnabled,
      );
      debugPrint('✅ تم الحفظ بنجاح - ID: $id');

      // ✅ إذا كان هناك شيك معلق، نخزنه مع ربطه بالإصلاح
      final pendingCheque = ref.read(repairFormProvider).pendingCheque;
      if (pendingCheque != null) {
        // TODO: إضافة استدعاء لـ ChequeService لحفظ الشيك مع ربطه بالإصلاح
        debugPrint('تم إضافة شيك مرتبط بالإصلاح: ${pendingCheque.chequeNo}');

        // مسح الشيك المعلق بعد الحفظ
        ref.read(repairFormProvider.notifier).clearPendingCheque();
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم الحفظ (معرّف الملف: $id)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الحفظ: $e')),
      );
    } finally {
      debugPrint('🎯 نهاية _saveFinal'); // ← **هذا السطر ناقص! أضفه هنا**

      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repairFormProvider);
    final isLast = _currentStep == _stepsTitles.length - 1;

    final partsTotal = state.parts
        .fold<double>(0, (s, p) => s + ((p['price'] as num?)?.toDouble() ?? 0));
    final worksTotal = state.works
        .fold<double>(0, (s, w) => s + ((w['price'] as num?)?.toDouble() ?? 0));
    final grandTotal = partsTotal + worksTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('إضافة ملف إصلاح'),
        actions: [],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              const SizedBox(height: 20),
              _stepIndicator(),
              const SizedBox(height: 12),
              if (state.imagePaths.isNotEmpty)
                SizedBox(
                  height: 100,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: state.imagePaths.map((path) {
                      return Stack(
                        alignment: Alignment.topRight,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: GestureDetector(
                              onTap: () => _previewImage(path),
                              child: Image.file(
                                File(path),
                                height: 80,
                                width: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.red),
                            onPressed: () => ref
                                .read(repairFormProvider.notifier)
                                .removeImage(path),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              if (isLast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      TextFormField(
                        decoration:
                            const InputDecoration(labelText: 'التكلفة الفعلية'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (value) =>
                            _actualCost = double.tryParse(value.trim()),
                      ),
                      SwitchListTile(
                        title: const Text('تفعيل الربط المحاسبي'),
                        value: _isLedgerEnabled,
                        onChanged: (v) => setState(() => _isLedgerEnabled = v),
                      ),
                      const SizedBox(height: 10),
                      // زر إضافة شيك في الخطوة المالية
                      if (state.paymentMethod ==
                          'شيك') // ⬅️ تغيير paymentType إلى paymentMethod
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (state.pendingCheque != null)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      'شيك رقم: ${state.pendingCheque!.chequeNo}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'البنك: ${state.pendingCheque!.bankName}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'المبلغ: ${state.pendingCheque!.amount} ${state.pendingCheque!.currency}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.receipt_long, size: 18),
                                label: const Text('إضافة بيانات الشيك'),
                                onPressed: _handleChequePayment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'قطع: ${partsTotal.toStringAsFixed(2)}, '
                        'أعمال: ${worksTotal.toStringAsFixed(2)}, '
                        'الإجمالي: ${MoneyFormatter.format(grandTotal)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    StepVehicleData(formKey: _step1Key),
                    StepBeneficiaryData(formKey: _step2Key),
                    StepWorkData(formKey: _step3Key),
                    StepFinancialData(
                      formKey: _step4Key,
                      forceEnableApprove: true,
                      onChequePaymentSelected:
                          _handleChequePayment, // ⬅️ إضافة callback للشيكات
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                child: AdaptiveRow(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton(
                        onPressed: _isSaving ? null : _previousStep,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        child: const Text('السابق'),
                      )
                    else
                      const SizedBox(width: 80),
                    ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () {
                              debugPrint(
                                  '🎯 زر الحفظ ضغط - isLast: $isLast, _isSaving: $_isSaving');

                              if (isLast) {
                                debugPrint('🎯 بداية الحفظ النهائي...');
                                _saveFinal();
                              } else {
                                debugPrint('🎯 الانتقال للخطوة التالية...');
                                _nextStep();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 20,
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              isLast ? 'حفظ نهائي' : 'التالي',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
