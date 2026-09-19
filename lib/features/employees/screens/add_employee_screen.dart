import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// 📁 lib/features/employees/screens/add_employee_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/yalla_appbar.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/responsive.dart';

import 'package:yalla_accounts/features/employees/providers/employee_form_provider.dart';
import 'package:yalla_accounts/features/employees/providers/employee_provider.dart';

import 'package:yalla_accounts/features/employees/widgets/steps/step_employee_basic_data.dart';
import 'package:yalla_accounts/features/employees/widgets/steps/step_employee_salary_data.dart';
import 'package:yalla_accounts/features/employees/widgets/steps/step_employee_notes_photo.dart';
import 'package:yalla_accounts/features/employees/models/employee.dart'
    show EmployeeContractType;
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class AddEmployeeScreen extends ConsumerStatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  ConsumerState<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends ConsumerState<AddEmployeeScreen> {
  final _pageController = PageController();
  final _formKeys = List.generate(3, (_) => GlobalKey<FormState>());
  int _currentStep = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      final newPage = _pageController.page?.round() ?? 0;
      if (newPage != _currentStep) {
        setState(() => _currentStep = newPage);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    final form = _formKeys[_currentStep].currentState!;
    if (!form.validate()) return;

    // تحقق إضافي خاص بالراتب والأنواع عند مغادرة الخطوة 2 (index 1)
    if (_currentStep == 1) {
      final isValid = ref.read(employeeFormValidatorProvider);
      if (!isValid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ بيانات الأجر/النوع غير مكتملة')),
        );
        return;
      }
    }

    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _saveFinal() async {
    if (_isSaving) return;
    final lastForm = _formKeys.last.currentState!;
    if (!lastForm.validate()) return;

    // تحقّق أخير حسب النوع
    final isValid = ref.read(employeeFormValidatorProvider);
    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ أكمل الحقول المطلوبة حسب نوع التعاقد')),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    String? errorMsg;

    try {
      final ok = await ref.read(employeeFormProvider.notifier).saveEmployee();
      if (!ok) {
        errorMsg = 'فشل الحفظ. تأكد من البيانات ثم حاول مجددًا.';
      } else {
        await ref.read(employeeProvider.notifier).loadEmployees();
      }
    } catch (e) {
      errorMsg = UserFacingError.message(e);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        if (errorMsg != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ $errorMsg')),
          );
        } else {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ تم إضافة الموظف بنجاح')),
          );
        }
      }
    }
  }

  String _typeLabel(EmployeeContractType t) {
    switch (t) {
      case EmployeeContractType.monthly:
        return 'مثبّت شهري';
      case EmployeeContractType.weekly:
        return 'مثبّت أسبوعي';
      case EmployeeContractType.daily:
        return 'مياومة (أجر يومي)';
      case EmployeeContractType.contract:
        return 'مقاولة (مبلغ مقطوع)';
    }
  }

  @override
  Widget build(BuildContext context) {
    const currentRoute = '/employees/add';
    final isDesktop = Responsive.isDesktop(context);

    final canPrev = _currentStep > 0;
    final canNext = _currentStep < 2;
    final isLast = _currentStep == 2;

    // مراقبة حالة النموذج لعرض الشارة والمعاينة
    final formState = ref.watch(employeeFormProvider);
    final previewNet = ref.watch(employeeNetSalaryProvider);
    final isFormValid = ref.watch(employeeFormValidatorProvider);

    return Scaffold(
      appBar: const YallaAppBar(
        workshopName: 'شؤون الموظفين',
        showThemeToggle: true,
        showUserAvatar: false,
        showSearch: false,
        showNotifications: false,
      ),
      drawer: isDesktop
          ? null
          : const Drawer(child: YallaSidebar(currentRoute: currentRoute)),
      body: AdaptiveRow(
        children: [
          if (isDesktop)
            const SizedBox(
              width: 260,
              child: YallaSidebar(currentRoute: currentRoute),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(height: 1),
                // شريط علوي صغير: نوع التعاقد + معاينة الصافي
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(_typeLabel(formState.contractType)),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      Chip(
                        label: Text(
                            'الصافي التقديري: ${previewNet.toStringAsFixed(2)}'),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      if (!isFormValid && _currentStep >= 1)
                        const Chip(
                          label: Text('البيانات غير مكتملة'),
                          backgroundColor: Color(0xFFFFE0E0),
                        ),
                    ],
                  ),
                ),
                SmoothPageIndicator(
                  controller: _pageController,
                  count: 3,
                  effect: const WormEffect(
                    activeDotColor: AppColors.primary,
                    dotHeight: 8,
                    dotWidth: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      Form(
                        key: _formKeys[0],
                        child: const StepEmployeeBasicData(),
                      ),
                      Form(
                        key: _formKeys[1],
                        child: const StepEmployeeSalaryData(),
                      ),
                      Form(
                        key: _formKeys[2],
                        child: const StepEmployeeNotesPhoto(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Container(
                  color: Colors.grey.shade100,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: AdaptiveRow(
                    children: [
                      if (canPrev)
                        ElevatedButton.icon(
                          onPressed: _previousStep,
                          icon: const Icon(Icons.arrow_back_ios),
                          label: const Text('السابق'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      const Spacer(),
                      if (canNext)
                        ElevatedButton.icon(
                          onPressed: _nextStep,
                          icon: const Icon(Icons.arrow_forward_ios),
                          label: const Text('التالي'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                      if (isLast)
                        ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveFinal,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: const Text('حفظ نهائي'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
