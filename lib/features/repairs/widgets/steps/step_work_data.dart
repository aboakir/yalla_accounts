// 📁 lib/features/repairs/widgets/steps/step_work_data.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/features/repairs/providers/repair_form_provider.dart';
import 'package:yalla_accounts/features/repairs/widgets/view_image_screen.dart';

// ✅ استيراد القوائم الموحّدة + دوال التطبيع
import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';

class StepWorkData extends ConsumerStatefulWidget {
  final GlobalKey<FormState> formKey;
  const StepWorkData({super.key, required this.formKey});

  static bool validateStep(WidgetRef ref, GlobalKey<FormState> formKey) {
    final ok = formKey.currentState?.validate() ?? false;
    if (!ok) return false;

    final f = ref.read(repairFormProvider);

    if (f.repairType.isEmpty || f.vehicleStatus.isEmpty) return false;

    final hasParts = f.parts.isNotEmpty;
    final hasWorks = f.works.isNotEmpty;

    switch (f.repairType) {
      case 'توريد قطع':
        return hasParts;
      case 'بودي ودهان':
        return hasWorks;
      case 'دهان وتوريد قطع':
        return hasParts && hasWorks;
      default:
        return false;
    }
  }

  @override
  ConsumerState<StepWorkData> createState() => _StepWorkDataState();
}

class _StepWorkDataState extends ConsumerState<StepWorkData> {
  final _imagePicker = ImagePicker();

  Future<void> _pickImage({required bool fromCamera}) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 70,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final fileName = '${const Uuid().v4()}${p.extension(picked.path)}';
      final savePath = p.join(dir.path, 'repairs_images', fileName);

      final saveDir = Directory(p.dirname(savePath));
      if (!saveDir.existsSync()) {
        await saveDir.create(recursive: true);
      }

      final saved = await File(picked.path).copy(savePath);
      ref.read(repairFormProvider.notifier).addImage(saved.path);
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء إضافة الصورة: $e')),
      );
    }
  }

  Future<bool> _confirmDeletion({String title = 'تأكيد الحذف'}) async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: const Text('هل تريد حذف هذا العنصر؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('حذف'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _addItemDialog({required bool isPart}) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String? priceSanitizer(String? s) {
      final raw = (s ?? '').trim();
      if (raw.isEmpty) return null;
      final sanitized = raw.replaceAll(',', '');
      final dotCount = '.'.allMatches(sanitized).length;
      if (dotCount > 1) return null;
      return sanitized;
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isPart ? 'إضافة قطعة' : 'إضافة عمل'),
        content: Form(
          key: formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                textAlign: TextAlign.right,
                decoration: _dec('الاسم'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceCtrl,
                textAlign: TextAlign.right,
                decoration: _dec('السعر (${MoneyFormatter.symbol})'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(12),
                ],
                validator: (v) {
                  final raw = (v ?? '').trim();

                  // السماح بقيمة فارغة (اختياري)
                  if (raw.isEmpty) return null;

                  // محاولة قراءة الرقم
                  final sanitized = raw.replaceAll(',', '');
                  final p = double.tryParse(sanitized);

                  if (p == null) return 'قيمة غير صالحة';

                  // نوع المستفيد
                  final beneficiary =
                      ref.read(repairFormProvider).beneficiaryType;
                  final isInsurance = beneficiary == 'شركة تأمين';

                  // التأمين → يسمح بالصفر
                  if (isInsurance) {
                    if (p < 0) return 'غير صالح';
                    return null;
                  }

                  // أفراد → لازم > 0
                  if (p <= 0) return 'أدخل رقمًا أكبر من 0';

                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final name = nameCtrl.text.trim();
              final raw = priceCtrl.text.trim();
              final price =
                  raw.isEmpty ? null : double.parse(raw.replaceAll(',', ''));

              final notifier = ref.read(repairFormProvider.notifier);
              if (isPart) {
                notifier.addPart({'name': name, 'price': price});
              } else {
                notifier.addWork({'name': name, 'price': price});
              }
              Navigator.pop(context);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(repairFormProvider);
    final notifier = ref.read(repairFormProvider.notifier);

    final partsTotal = form.parts.fold<double>(
        0, (sum, it) => sum + ((it['price'] as num?)?.toDouble() ?? 0));
    final worksTotal = form.works.fold<double>(
        0, (sum, it) => sum + ((it['price'] as num?)?.toDouble() ?? 0));
    final fileTotal = partsTotal + worksTotal;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Form(
        key: widget.formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'بيانات العمل',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),

            // نوع العمل
            DropdownButtonFormField<String>(
              value: normalizeOrNull(form.repairType, kRepairTypes),
              decoration: _dec('نوع العمل'),
              hint: const Text('اختر نوع العمل'),
              items: kRepairTypes
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                notifier.updateRepairType(v);
                setState(() {});
              },
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // حالة المركبة
            DropdownButtonFormField<String>(
              value: normalizeValue(
                form.vehicleStatus,
                kVehicleStatuses,
                aliases: kVehicleStatusAliases,
              ),
              decoration: _dec('حالة المركبة'),
              hint: const Text('اختر حالة المركبة'),
              items: kVehicleStatuses
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                notifier.updateVehicleStatus(v);
                setState(() {});
              },
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
            const SizedBox(height: 24),

            // كشف القطع
            _buildSection(
              title: 'كشف القطع',
              total: partsTotal,
              onAdd: () => _addItemDialog(isPart: true),
              emptyHint: 'لا توجد قطع بعد',
              children: form.parts.asMap().entries.map((e) {
                return _buildItemTile(
                  e.value,
                  onDelete: () async {
                    if (await _confirmDeletion()) notifier.removePart(e.key);
                    setState(() {});
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // كشف الأعمال
            _buildSection(
              title: 'كشف الأعمال',
              total: worksTotal,
              onAdd: () => _addItemDialog(isPart: false),
              emptyHint: 'لا توجد أعمال بعد',
              children: form.works.asMap().entries.map((e) {
                return _buildItemTile(
                  e.value,
                  onDelete: () async {
                    if (await _confirmDeletion()) notifier.removeWork(e.key);
                    setState(() {});
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // المجموع الكلي
            Row(
              children: [
                const Text(
                  'المجموع الكلي:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${MoneyFormatter.format(fileTotal)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // صور المركبة
            const Text(
              'صور المركبة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final path in form.imagePaths)
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push<List<String>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ViewImageScreen(
                            imagePaths: form.imagePaths,
                            canEdit: true,
                          ),
                        ),
                      );
                      if (result != null) {
                        ref
                            .read(repairFormProvider.notifier)
                            .updateImages(result);
                        setState(() {});
                      }
                    },
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: File(path).existsSync()
                              ? Image.file(
                                  File(path),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.broken_image),
                                ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () async {
                              if (await _confirmDeletion(title: 'حذف الصورة')) {
                                ref
                                    .read(repairFormProvider.notifier)
                                    .removeImage(path);
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                              child: const Icon(Icons.close,
                                  size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                _buildImageButton(
                  icon: Icons.camera_alt,
                  tooltip: 'التقط صورة',
                  onTap: () => _pickImage(fromCamera: true),
                ),
                _buildImageButton(
                  icon: Icons.photo,
                  tooltip: 'اختر من المعرض',
                  onTap: () => _pickImage(fromCamera: false),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTile(
    Map<String, dynamic> item, {
    required Future<void> Function() onDelete,
  }) {
    final name = (item['name'] ?? '').toString();
    final price =
        MoneyFormatter.number((item['price'] as num?)?.toDouble() ?? 0);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('السعر: $price ${MoneyFormatter.symbol}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: onDelete,
          tooltip: 'حذف',
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required double total,
    required VoidCallback onAdd,
    required List<Widget> children,
    String emptyHint = 'لا توجد عناصر بعد',
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary),
                  onPressed: onAdd,
                  tooltip: 'إضافة',
                ),
              ],
            ),
            if (children.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child:
                    Text(emptyHint, style: const TextStyle(color: Colors.grey)),
              )
            else
              ...children,
            if (children.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'المجموع: ${MoneyFormatter.format(total)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AppColors.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: IconButton(
        icon: Icon(icon, size: 32, color: Colors.grey[700]),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
