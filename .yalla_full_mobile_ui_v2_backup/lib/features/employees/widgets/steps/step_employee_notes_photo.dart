import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/features/employees/providers/employee_form_provider.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class StepEmployeeNotesPhoto extends ConsumerStatefulWidget {
  final VoidCallback? onSave;
  const StepEmployeeNotesPhoto({super.key, this.onSave});

  @override
  ConsumerState<StepEmployeeNotesPhoto> createState() =>
      _StepEmployeeNotesPhotoState();
}

class _StepEmployeeNotesPhotoState
    extends ConsumerState<StepEmployeeNotesPhoto> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController notesController;
  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final form = ref.read(employeeFormProvider);
    notesController = TextEditingController(text: form.notes);
    notesController.addListener(() {
      ref.read(employeeFormProvider.notifier).updateNotes(notesController.text);
    });
  }

  @override
  void dispose() {
    notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      ref.read(employeeFormProvider.notifier).updateImage(picked.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(employeeFormProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: notesController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات إضافية',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => widget.onSave?.call(),
                ),
                const SizedBox(height: 20),
                if (form.imagePath != null && form.imagePath!.isNotEmpty)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(form.imagePath!),
                          width: double.infinity,
                          height: 250,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          backgroundColor: Colors.black54,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'حذف الصورة',
                            onPressed: () => ref
                                .read(employeeFormProvider.notifier)
                                .removeImage(),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                AdaptiveRow(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo),
                        label: const Text('اختر من المعرض'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _pickImage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('التقاط صورة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
