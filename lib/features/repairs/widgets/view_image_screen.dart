// 📁 lib/features/repairs/widgets/view_image_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

/// شاشة عرض وتحرير صور المركبة.
/// - تدعم تكبير وتصغير كل صورة (InteractiveViewer).
/// - عرض الشريحة الحالية من الصور وعددها.
/// - إضافة صورة من المعرض.
/// - حذف صورة مع تأكيد وعرض إمكانية التراجع (Undo).
/// - حفظ التعديلات أو الإلغاء.
class ViewImageScreen extends StatefulWidget {
  final List<String> imagePaths;
  final bool canEdit;

  const ViewImageScreen({
    super.key,
    required this.imagePaths,
    this.canEdit = false,
  });

  @override
  State<ViewImageScreen> createState() => _ViewImageScreenState();
}

class _ViewImageScreenState extends State<ViewImageScreen> {
  late List<String> _images;
  late List<String> _originalImages;
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  String? _lastRemovedPath;
  int? _lastRemovedIndex;

  @override
  void initState() {
    super.initState();
    _images = List.from(widget.imagePaths);
    _originalImages = List.from(widget.imagePaths);
  }

  /// يختار صورة من المعرض ويحفظها في مجلد داخلي، ثم يضيفها للقائمة.
  Future<void> _addImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (picked != null) {
        final dir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory(p.join(dir.path, 'vehicle_images'));
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        final newName = const Uuid().v4() + p.extension(picked.path);
        final newPath = p.join(imagesDir.path, newName);
        final savedFile = await File(picked.path).copy(newPath);
        if (!mounted) return;
        setState(() {
          _images.add(savedFile.path);
          _currentIndex = _images.length - 1;
          _pageController.animateToPage(
            _currentIndex,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ حدث خطأ أثناء إضافة الصورة: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  /// يحذف صورة بعد تأكيد المستخدم، ويعرض Snackbar مع زر التراجع (Undo).
  void _deleteImage(int index) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (_) => AdaptiveAlertDialog(
            title: const Text('تأكيد الحذف'),
            content: const Text('هل تريد حذف هذه الصورة؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('حذف'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted || !confirmed) return;

    setState(() {
      _lastRemovedPath = _images.removeAt(index);
      _lastRemovedIndex = index;
      if (_images.isEmpty) {
        _currentIndex = 0;
      } else if (_currentIndex >= _images.length) {
        _currentIndex = _images.length - 1;
      }
      _pageController.jumpToPage(_currentIndex);
    });

    // إظهار Snackbar مع خيار التراجع
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم حذف الصورة'),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AppColors.primary,
          onPressed: () {
            if (_lastRemovedPath != null && _lastRemovedIndex != null) {
              setState(() {
                _images.insert(_lastRemovedIndex!, _lastRemovedPath!);
                _currentIndex = _lastRemovedIndex!;
                _pageController.jumpToPage(_currentIndex);
              });
            }
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// يتحقق مما إذا تم التغيير في القائمة مقارنة بالأصلية.
  bool get _hasChanges =>
      _images.length != _originalImages.length ||
      !_images.every((path) => _originalImages.contains(path));

  /// يستدعي عند محاولة العودة؛ إذا هناك تغييرات وعند القدرة على التحرير، يعرض تأكيدًا.
  Future<bool> _onWillPop() async {
    if (!widget.canEdit || !_hasChanges) return true;
    final discard = await showDialog<bool>(
          context: context,
          builder: (_) => AdaptiveAlertDialog(
            title: const Text('إلغاء التعديلات؟'),
            content: const Text('هل تريد الخروج دون حفظ الصور؟'),
            actions: [
              TextButton(
                child: const Text('نعم'),
                onPressed: () => Navigator.pop(context, true),
              ),
              ElevatedButton(
                child: const Text('لا'),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
        ) ??
        false;
    return discard;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text('صور المركبة'),
            backgroundColor: AppColors.primary,
            actions: [
              if (widget.canEdit)
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate),
                  onPressed: _addImage,
                  tooltip: 'إضافة صورة جديدة',
                ),
            ],
          ),
          body: _images.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد صور لعرضها',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : Column(
                  children: [
                    // عرض رقم الشريحة الحالية / الإجمالي
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      child: AdaptiveRow(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_currentIndex + 1} / ${_images.length}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                          if (widget.canEdit)
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.redAccent),
                              onPressed: () => _deleteImage(_currentIndex),
                              tooltip: 'حذف الصورة الحالية',
                            ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _images.length,
                        onPageChanged: (index) =>
                            setState(() => _currentIndex = index),
                        itemBuilder: (context, index) {
                          final file = File(_images[index]);
                          return Stack(
                            children: [
                              Center(
                                child: Hero(
                                  tag: _images[index],
                                  child: InteractiveViewer(
                                    panEnabled: true,
                                    boundaryMargin: const EdgeInsets.all(20),
                                    minScale: 0.7,
                                    maxScale: 4.0,
                                    child: file.existsSync()
                                        ? Image.file(
                                            file,
                                            fit: BoxFit.contain,
                                            width: double.infinity,
                                            cacheWidth:
                                                (MediaQuery.sizeOf(context)
                                                            .width *
                                                        MediaQuery
                                                            .devicePixelRatioOf(
                                                                context) *
                                                        1.5)
                                                    .round()
                                                    .clamp(1024, 2048)
                                                    .toInt(),
                                          )
                                        : Container(
                                            color: Colors.grey.shade200,
                                            child: const Center(
                                              child: Icon(
                                                Icons.broken_image,
                                                size: 60,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              // مؤشر تصوير (Optional) عند لمس الصورة
                            ],
                          );
                        },
                      ),
                    ),

                    // نقاط التنقل (Page Indicator)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      child: AdaptiveRow(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _images.length,
                          (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: _currentIndex == i ? 12 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _currentIndex == i
                                  ? AppColors.primary
                                  : Colors.grey[400],
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
          bottomNavigationBar: widget.canEdit
              ? SafeArea(
                  minimum:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: AdaptiveRow(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            // إلغاء بدون حفظ: إعادة التعديلات
                            Navigator.pop(context, widget.imagePaths);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'إلغاء',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // حفظ التعديلات وإرجاع القائمة المحدثة
                            Navigator.pop(context, _images);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'حفظ التعديلات',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
