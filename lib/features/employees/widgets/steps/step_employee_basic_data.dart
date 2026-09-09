// ✅ نسخة منسقة ومحسّنة من شاشة البيانات الأساسية للموظف الجديد
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/features/employees/providers/employee_form_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class StepEmployeeBasicData extends ConsumerStatefulWidget {
  final void Function()? onNext;
  const StepEmployeeBasicData({super.key, this.onNext});

  @override
  ConsumerState<StepEmployeeBasicData> createState() =>
      _StepEmployeeBasicDataState();
}

class _StepEmployeeBasicDataState extends ConsumerState<StepEmployeeBasicData> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController fullNameController;
  late TextEditingController idNumberController;
  late TextEditingController jobTitleController;
  late TextEditingController phoneController;
  late TextEditingController emailController;

  final _focusFullName = FocusNode();
  final _focusIdNumber = FocusNode();
  final _focusJobTitle = FocusNode();
  final _focusPhone = FocusNode();
  final _focusEmail = FocusNode();

  @override
  void initState() {
    super.initState();
    final form = ref.read(employeeFormProvider);
    fullNameController = TextEditingController(text: form.fullName);
    idNumberController = TextEditingController(text: form.idNumber);
    jobTitleController = TextEditingController(text: form.jobTitle);
    phoneController = TextEditingController(text: form.phone);
    emailController = TextEditingController(text: form.email);

    fullNameController.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateFullName(fullNameController.text));
    idNumberController.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateIdNumber(idNumberController.text));
    jobTitleController.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateJobTitle(jobTitleController.text));
    phoneController.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updatePhone(phoneController.text));
    emailController.addListener(() => ref
        .read(employeeFormProvider.notifier)
        .updateEmail(emailController.text));
  }

  @override
  void dispose() {
    fullNameController.dispose();
    idNumberController.dispose();
    jobTitleController.dispose();
    phoneController.dispose();
    emailController.dispose();

    _focusFullName.dispose();
    _focusIdNumber.dispose();
    _focusJobTitle.dispose();
    _focusPhone.dispose();
    _focusEmail.dispose();

    super.dispose();
  }

  void _handleSubmit() {
    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      widget.onNext?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(employeeFormProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  controller: fullNameController,
                  label: 'الاسم الكامل',
                  focusNode: _focusFullName,
                  nextFocus: _focusIdNumber,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: idNumberController,
                  label: 'الرقم الوظيفي',
                  focusNode: _focusIdNumber,
                  nextFocus: _focusJobTitle,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'الرقم الوظيفي مطلوب' : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: jobTitleController,
                  label: 'المسمى الوظيفي',
                  focusNode: _focusJobTitle,
                  nextFocus: _focusPhone,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'المسمى الوظيفي مطلوب' : null,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: AdaptiveRow(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: form.hireDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                            builder: (context, child) => Directionality(
                              textDirection: TextDirection.rtl,
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            ref
                                .read(employeeFormProvider.notifier)
                                .updateHireDate(picked);
                          }
                        },
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('تاريخ التعيين'),
                          Text('${form.hireDate.toLocal()}'.split(' ')[0]),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: phoneController,
                  label: 'رقم الهاتف',
                  focusNode: _focusPhone,
                  nextFocus: _focusEmail,
                  keyboardType: TextInputType.phone,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'رقم الهاتف مطلوب' : null,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: emailController,
                  label: 'البريد الإلكتروني (اختياري)',
                  focusNode: _focusEmail,
                  keyboardType: TextInputType.emailAddress,
                  onFieldSubmitted: (_) => _handleSubmit(),
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                      if (!emailRegex.hasMatch(v)) {
                        return 'صيغة البريد الإلكتروني غير صحيحة';
                      }
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    ValueChanged<String>? onFieldSubmitted,
  }) {
    return TextFormField(
      inputFormatters: const [YallaDigitNormalizer()],
      controller: controller,
      focusNode: focusNode,
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.right,
      keyboardType: keyboardType,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      textInputAction:
          nextFocus != null ? TextInputAction.next : TextInputAction.done,
      onFieldSubmitted: (value) {
        if (onFieldSubmitted != null) {
          onFieldSubmitted(value);
        } else if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        } else {
          _handleSubmit();
        }
      },
    );
  }
}
