// 📁 lib/features/clients/widgets/add_client_dialog.dart
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/constants/insurance_companies.dart';
import 'package:yalla_accounts/features/clients/models/client.dart';
import 'package:yalla_accounts/features/clients/services/client_service.dart';

class AddClientDialog extends StatefulWidget {
  const AddClientDialog({super.key});

  @override
  State<AddClientDialog> createState() => _AddClientDialogState();
}

class _AddClientDialogState extends State<AddClientDialog> {
  final _formKey = GlobalKey<FormState>();

  // مدخلات اختيارية
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController(); // 🆕 ملاحظات
  final _manualNameController = TextEditingController();

  String _clientType = 'أفراد'; // القيم المعتمدة: 'أفراد' | 'شركة تأمين'
  String? _selectedInsuranceCompany;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose(); // 🆕
    _manualNameController.dispose();
    super.dispose();
  }

  Future<void> _saveClient() async {
    if (!_formKey.currentState!.validate()) return;

    // تحديد الاسم حسب النوع
    final String name = _clientType == 'شركة تأمين'
        ? (_selectedInsuranceCompany ?? '')
        : _manualNameController.text.trim();

    // فحص التكرار — نعتمد خدمة موحّدة (تدعم العربي/الإنجليزي داخليًا)
    final exists = await ClientService.clientExists(name, type: _clientType);
    if (exists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❗ هذا العميل موجود مسبقًا')),
      );
      return;
    }

    final newClient = Client(
      name: name,
      type: _clientType, // بالعربي كما هو معتمد في مشروعك
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      address: _addressController.text.trim(),
      notes: _notesController.text.trim(), // 🆕
    );

    await ClientService.insertClient(newClient);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _onTypeChanged(String? val) {
    if (val == null) return;
    setState(() {
      _clientType = val;
      // إعادة تهيئة مدخلات الاسم حسب النوع
      _selectedInsuranceCompany = null;
      _manualNameController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة عميل جديد'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // نوع العميل
                DropdownButtonFormField<String>(
                  value: _clientType,
                  decoration: _inputDecoration('نوع العميل'),
                  items: const [
                    DropdownMenuItem(value: 'أفراد', child: Text('أفراد')),
                    DropdownMenuItem(
                      value: 'شركة تأمين',
                      child: Text('شركة تأمين'),
                    ),
                  ],
                  onChanged: _onTypeChanged,
                ),
                const SizedBox(height: 12),

                // اسم العميل — حسب النوع
                if (_clientType == 'شركة تأمين') ...[
                  DropdownButtonFormField<String>(
                    value: _selectedInsuranceCompany,
                    decoration: _inputDecoration('اسم شركة التأمين'),
                    items: insuranceCompanies
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    validator: (val) =>
                        val == null ? 'يرجى اختيار اسم الشركة' : null,
                    onChanged: (val) => setState(() {
                      _selectedInsuranceCompany = val;
                    }),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _manualNameController,
                    decoration: _inputDecoration('اسم العميل'),
                    textAlign: TextAlign.right,
                    validator: (val) => (val == null || val.trim().isEmpty)
                        ? 'الاسم مطلوب'
                        : null,
                  ),
                ],

                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: _inputDecoration('رقم الهاتف (اختياري)'),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: _inputDecoration('البريد الإلكتروني (اختياري)'),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: _inputDecoration('العنوان (اختياري)'),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 12),

                // 🆕 حقل الملاحظات
                TextFormField(
                  controller: _notesController,
                  decoration: _inputDecoration('ملاحظات (اختياري)'),
                  textAlign: TextAlign.right,
                  minLines: 2,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _saveClient,
          child: const Text('حفظ'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}
