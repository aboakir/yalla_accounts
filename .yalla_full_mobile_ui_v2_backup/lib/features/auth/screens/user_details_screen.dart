// lib/features/auth/screens/user_details_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/features/auth/models/app_user.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/auth/services/user_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class UserDetailsScreen extends ConsumerStatefulWidget {
  final AppUser user;
  final AppUser currentUser;

  const UserDetailsScreen({
    super.key,
    required this.user,
    required this.currentUser,
  });

  @override
  ConsumerState<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends ConsumerState<UserDetailsScreen> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController subscriptionAmountController;
  late TextEditingController paymentStatusController;
  late TextEditingController paymentMethodController;
  late TextEditingController workshopAddressController;

  List<String> phoneNumbers = [];
  DateTime? subscriptionDate;
  DateTime? subscriptionEndDate;
  DateTime? freeTrialStart;
  DateTime? freeTrialEnd;
  String? workshopLogoPath;
  String? paymentReceiptPath;

  bool isLoading = false;

  final DateFormat dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    final user = widget.user;

    nameController = TextEditingController(text: user.name);
    emailController = TextEditingController(text: user.email);
    subscriptionAmountController = TextEditingController(
        text: user.subscriptionAmount?.toStringAsFixed(2) ?? '');
    paymentStatusController =
        TextEditingController(text: user.paymentStatus ?? '');
    paymentMethodController =
        TextEditingController(text: user.paymentMethod ?? '');
    workshopAddressController =
        TextEditingController(text: user.workshopAddress ?? '');

    phoneNumbers = List<String>.from(user.phoneNumbers ?? []);
    subscriptionDate = user.subscriptionDate;
    subscriptionEndDate = user.subscriptionEndDate;
    freeTrialStart = user.freeTrialStart;
    freeTrialEnd = user.freeTrialEnd;
    workshopLogoPath = user.workshopLogoPath;
    paymentReceiptPath = user.paymentReceiptPath;
  }

  bool get isAdmin =>
      widget.currentUser.role == 'admin' ||
      widget.currentUser.role == 'manager';

  Future<void> _pickPaymentReceipt() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        paymentReceiptPath = pickedFile.path;
      });
    }
  }

  void _addPhoneNumber() {
    setState(() {
      phoneNumbers.add('');
    });
  }

  void _removePhoneNumber(int index) {
    setState(() {
      phoneNumbers.removeAt(index);
    });
  }

  void _onPhoneNumberChanged(int index, String value) {
    phoneNumbers[index] = value;
  }

  Future<void> _saveChanges() async {
    setState(() {
      isLoading = true;
    });

    final updatedUser = widget.user.copyWith(
      name: nameController.text.trim(),
      email: emailController.text.trim(),
      subscriptionAmount:
          double.tryParse(subscriptionAmountController.text.trim()),
      paymentStatus: paymentStatusController.text.trim(),
      paymentMethod: paymentMethodController.text.trim(),
      workshopAddress: workshopAddressController.text.trim(),
      subscriptionDate: subscriptionDate,
      subscriptionEndDate: subscriptionEndDate,
      freeTrialStart: freeTrialStart,
      freeTrialEnd: freeTrialEnd,
      phoneNumbers: phoneNumbers.where((e) => e.trim().isNotEmpty).toList(),
      workshopLogoPath: workshopLogoPath,
      paymentReceiptPath: paymentReceiptPath,
    );

    await ref.read(userServiceProvider).updateUser(updatedUser);

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ التغييرات بنجاح')),
    );
  }

  Widget _buildPhoneNumberField(int index) {
    return AdaptiveRow(
      children: [
        Expanded(
          child: TextFormField(
            initialValue: phoneNumbers[index],
            enabled: isAdmin,
            decoration: const InputDecoration(
              labelText: 'رقم تواصل',
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => _onPhoneNumberChanged(index, val),
            keyboardType: TextInputType.phone,
          ),
        ),
        if (isAdmin)
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _removePhoneNumber(index),
          ),
      ],
    );
  }

  Widget _buildEditableDateField({
    required String label,
    DateTime? date,
    required Function(DateTime) onDateSelected,
  }) {
    return InkWell(
      onTap: isAdmin
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) onDateSelected(picked);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(
          date != null ? dateFormat.format(date) : 'غير محدد',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AdaptiveRow(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageRow(String label, String? imagePath) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (imagePath != null && imagePath.isNotEmpty)
            Image.file(
              File(imagePath),
              height: 120,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  const Text('خطأ في تحميل الصورة'),
            )
          else
            const Text('لا توجد صورة'),
        ],
      ),
    );
  }

  String _translateRole(String role) {
    switch (role) {
      case 'admin':
        return 'مدير';
      case 'manager':
        return 'مشرف';
      default:
        return 'مستخدم';
    }
  }

  String _translateStatus(String status) {
    switch (status) {
      case 'active':
        return 'نشط';
      case 'frozen':
        return 'مجمد';
      case 'inactive':
        return 'غير مفعل';
      case 'pending':
        return 'في انتظار الموافقة';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المستخدم'),
        backgroundColor: AppColors.primary,
        centerTitle: true,
        actions: [
          if (isAdmin)
            IconButton(
              icon: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.save),
              onPressed: isLoading ? null : _saveChanges,
              tooltip: 'حفظ التغييرات',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: AdaptiveRow(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameController,
                      enabled: isAdmin,
                      decoration: const InputDecoration(
                          labelText: 'الاسم الكامل',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: emailController,
                      enabled: isAdmin,
                      decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          border: OutlineInputBorder()),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('الدور', _translateRole(widget.user.role)),
                    const Divider(),
                    _buildInfoRow(
                        'الحالة', _translateStatus(widget.user.status)),
                    const Divider(),
                    if (widget.user.role == 'user') ...[
                      _buildEditableDateField(
                        label: 'بداية الفترة المجانية',
                        date: freeTrialStart ?? widget.user.createdAt,
                        onDateSelected: (d) =>
                            setState(() => freeTrialStart = d),
                      ),
                      const SizedBox(height: 12),
                      _buildEditableDateField(
                        label: 'نهاية الفترة المجانية',
                        date: freeTrialEnd ??
                            (freeTrialStart ?? widget.user.createdAt)
                                .add(const Duration(days: 10)),
                        onDateSelected: (d) => setState(() => freeTrialEnd = d),
                      ),
                      const Divider(),
                    ],
                    _buildEditableDateField(
                      label: 'تاريخ الاشتراك',
                      date: subscriptionDate,
                      onDateSelected: (d) =>
                          setState(() => subscriptionDate = d),
                    ),
                    const SizedBox(height: 12),
                    _buildEditableDateField(
                      label: 'تاريخ انتهاء الاشتراك',
                      date: subscriptionEndDate,
                      onDateSelected: (d) =>
                          setState(() => subscriptionEndDate = d),
                    ),
                    const Divider(),
                    TextFormField(
                      controller: subscriptionAmountController,
                      enabled: isAdmin,
                      decoration: const InputDecoration(
                          labelText: 'المبلغ المدفوع',
                          border: OutlineInputBorder()),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: paymentStatusController,
                      enabled: isAdmin,
                      decoration: const InputDecoration(
                          labelText: 'حالة الدفع',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: paymentMethodController,
                      enabled: isAdmin,
                      decoration: const InputDecoration(
                          labelText: 'طريقة الدفع',
                          border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: workshopAddressController,
                      enabled: false,
                      decoration: const InputDecoration(
                          labelText: 'عنوان الورشة',
                          border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    AdaptiveRow(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'أرقام التواصل',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (isAdmin)
                          TextButton.icon(
                            onPressed: _addPhoneNumber,
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة رقم'),
                          )
                      ],
                    ),
                    ...phoneNumbers.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: _buildPhoneNumberField(e.key),
                        )),
                    const Divider(),
                    _buildImageRow('شعار الورشة', workshopLogoPath),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'وصل الدفع',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          if (paymentReceiptPath != null &&
                              paymentReceiptPath!.isNotEmpty)
                            Image.file(
                              File(paymentReceiptPath!),
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.contain,
                            )
                          else
                            const Text('لا توجد صورة'),
                          if (isAdmin)
                            TextButton.icon(
                              onPressed: _pickPaymentReceipt,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('رفع/تغيير وصل الدفع'),
                            ),
                        ],
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
