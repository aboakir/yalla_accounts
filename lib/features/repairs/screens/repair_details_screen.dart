import 'dart:ui' as ui;
// 📁 lib/features/repairs/screens/repair_details_screen.dart
// - حالة التأمين + حالة المركبة جنب بعض داخل البطاقة اليسرى.
// - تحديث ذكي لأسماء الأعمدة (يكتشف العمود الصحيح قبل UPDATE).
// - دفعات، اعتماد نهائي، صور، PDF، GL.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/features/repairs/services/repair_payer_bridge.dart';
import 'package:yalla_accounts/features/repairs/services/repair_line_bridge.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';
import 'package:yalla_accounts/features/repairs/services/repair_finance_service.dart';

import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/features/finance/payments/services/payment_service.dart';
import 'package:yalla_accounts/features/finance/payments/models/payment.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_thumb.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class RepairDetailsScreen extends StatefulWidget {
  final Repair repair;
  const RepairDetailsScreen({super.key, required this.repair});

  @override
  State<RepairDetailsScreen> createState() => _RepairDetailsScreenState();
}

class _RepairDetailsScreenState extends State<RepairDetailsScreen> {
  // P07_PAYER_DETAILS_STATE
  bool _hideP07InsuranceStatus = false;
  late Repair _repair;
  bool _loading = true;
  bool _approving = false;

  List<Map<String, dynamic>> _repairWorks = [];
  List<Map<String, dynamic>> _repairParts = [];

  final _currency = NumberFormat('#,##0.00', 'ar');
  final _df = DateFormat('yyyy-MM-dd');

  int? _invoiceGlEntryId;

  final ScrollController _imagesScrollCtrl = ScrollController();

  static const List<_PayMethod> _methods = [
    _PayMethod('cash', 'الصندوق (1000)'),
    _PayMethod('bank', 'البنك (1010)'),
  ];

  // خيارات القوائم
  static const List<String> _insuranceOptions = [
    'تم تسليم الفاتورة',
    'تم التسديد في التعويضات',
    'تم التسديد في المالية',
    'تم الصرف',
  ];

  static const List<String> _vehicleOptions = [
    'تم الاستلام',
    'قيد الإصلاح',
    'جاهزة للتسليم',
    'تم التسليم',
  ];

  @override
  void initState() {
    super.initState();
    // P07_PAYER_DETAILS_INIT
    _loadP07PayerVisibility();
    // P07_LINE_READBACK_INIT
    _repair = widget.repair;
    _loadRepairDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _reloadRepair();
    });
  }

  @override
  void dispose() {
    _imagesScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRepairDetails() async {
    final svc = await RepairsService.instance();
    final loaded = await svc.getById(widget.repair.id);
    if (!mounted) return;
    final r = loaded ?? widget.repair;
    setState(() {
      _repair = r;
      _repairWorks = List<Map<String, dynamic>>.from(r.works);
      _repairParts = List<Map<String, dynamic>>.from(r.parts);
      _loading = false;
    });
    // P07_LINE_READBACK_SERIALIZED
    await _loadPersistedRepairLines();
    await _refreshInvoiceGl();
  }

  Future<void> _reloadRepair() async {
    final svc = await RepairsService.instance();
    final r = await svc.getById(_repair.id);
    if (!mounted) return;
    if (r != null) {
      setState(() => _repair = r);
      await _refreshInvoiceGl();
    }
  }

  // ===== كشف اسم العمود الحقيقي وتحديثه بشكل آمن =====
  Future<String?> _findExistingColumn(List<String> candidates) async {
    final db = await DBService.database;
    final rows = await db.rawQuery('PRAGMA table_info(repairs)');
    final cols = rows.map((r) => (r['name'] ?? '').toString()).toSet();
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  Future<void> _updateColumnSmart({
    required List<String> candidates,
    required String value,
    required String successMsg,
  }) async {
    try {
      final col = await _findExistingColumn(candidates);
      if (col == null) {
        throw 'لم يُعثر على عمود مناسب (${candidates.join(", ")}) في جدول repairs';
      }
      final db = await DBService.database;
      await db.update('repairs', {col: value},
          where: 'id = ?', whereArgs: [_repair.id]);
      await _reloadRepair();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('فشل تحديث الحالة: $e')));
    }
  }

  // تحديث الحالات باستخدام الكشف الذكي
  Future<void> _updateInsuranceStatus(String value) async {
    await _updateColumnSmart(
      candidates: [
        'insurance_followup',
        'insurance_status',
        'insuranceStatus',
        'insurance_followup_status',
      ],
      value: value,
      successMsg: 'تم تحديث حالة التأمين',
    );
  }

  Future<void> _updateVehicleStatus(String value) async {
    await _updateColumnSmart(
      candidates: [
        'vehicle_status',
        'vehicleStatus',
        'car_status',
        'status_vehicle',
      ],
      value: value,
      successMsg: 'تم تحديث حالة المركبة',
    );
  }

  // ===== GL helpers =====
  Future<void> _refreshInvoiceGl() async {
    final invId = _repair.invoiceId;
    if (invId == null || invId.isEmpty) {
      setState(() => _invoiceGlEntryId = null);
      return;
    }
    try {
      final db = await DBService.database;
      final row = await db.rawQuery(
        '''
        SELECT id FROM gl_entries
        WHERE source = 'INVOICE' AND source_id = ?
        ORDER BY id DESC
        LIMIT 1
        ''',
        [invId],
      );
      setState(() {
        _invoiceGlEntryId =
            row.isNotEmpty ? int.tryParse('${row.first['id']}') : null;
      });
    } catch (_) {
      setState(() => _invoiceGlEntryId = null);
    }
  }

  Future<void> _postInvoiceGLIfMissing() async {
    final invId = _repair.invoiceId;
    if (invId == null || invId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد فاتورة لهذا الملف.')),
      );
      return;
    }
    if (_invoiceGlEntryId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('قيد GL موجود بالفعل (#$_invoiceGlEntryId).')),
      );
      return;
    }
    try {
      final id = await DBService.postInvoiceGLFromId(invId);
      await _refreshInvoiceGl();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم ترحيل قيد الفاتورة GL (#$id)')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل ترحيل GL: $e')),
      );
    }
  }

  // ===== اعتماد نهائي =====
  Future<void> _confirmFinalApproval() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('اعتماد السعر النهائي'),
        content:
            const Text('هل تريد اعتماد السعر النهائي وتسجيل القيد المحاسبي؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _approving = true);
    try {
      await RepairFinanceService.approveFinalAmount(_repair);
      await _reloadRepair();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم الاعتماد وإنشاء القيد والفاتورة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الاعتماد: $e')),
      );
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  // ===== الدفعات =====
  Future<void> _addPayment() async {
    if (_repair.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('لا يمكن إضافة دفعة قبل حفظ ملف الإصلاح.')),
      );
      return;
    }

    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController(text: 'دفعة على ملف إصلاح');
    DateTime payDate = DateTime.now();
    _PayMethod method = _methods.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => AdaptiveAlertDialog(
          title: const Text('إضافة دفعة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: 'المبلغ', hintText: '0.00'),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<_PayMethod>(
                  value: method,
                  items: _methods
                      .map((m) =>
                          DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) => setM(() => method = v ?? _methods.first),
                  decoration: InputDecoration(labelText: 'طريقة الدفع'),
                ),
                const SizedBox(height: 10),
                AdaptiveRow(
                  children: [
                    const Text('التاريخ: '),
                    TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(DateTime.now().year - 3, 1, 1),
                          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                          initialDate: payDate,
                        );
                        if (d != null) setM(() => payDate = d);
                      },
                      child: Text(_df.format(payDate)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  inputFormatters: const [YallaDigitNormalizer()],
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'ملاحظات (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ط­ظپط¸')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final raw = amountCtrl.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صالحًا')));
      return;
    }

    final remaining = (_repair.totalFileValue) - (_repair.totalPaidAmount);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('الملف مسدد بالكامل')));
      return;
    }
    if (amount > remaining + 0.0001) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('المبلغ يتجاوز المتبقي (${_currency.format(remaining)})')),
      );
      return;
    }

    final payment = Payment(
      id: '',
      clientId: _repair.clientId,
      invoiceId: _repair.invoiceId,
      repairId: _repair.id,
      relatedRepairId: _repair.id,
      amount: double.parse(amount.toStringAsFixed(2)),
      date: payDate,
      method: method.key,
      accountName: method.key,
      status: "confirmed", // ← String بدل Enum
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      attachments: null,
      glEntryId: null,

      // REQUIRED — لازم موجود حسب الموديل
      isIncome: true, // ← لأنها دفعة قبض للعميل
    );

    try {
      await PaymentService.insertAndPostReceipt(
        payment: payment,
        customerName: _repair.beneficiaryName,
        method: method.key,
        descriptionOverride:
            notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      );
// تحديث إجمالي المدفوعات داخل repairs بعد إضافة الدفعة
      final repSvc = await RepairsService.instance();
      await repSvc.updateTotalsFromPayments(_repair.id);

      await _reloadRepair(); // إعادة تحميل بعد تحديث totals

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('✅ تم تسجيل الدفعة: ${_currency.format(amount)}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ فشل الحفظ: $e')));
    }
  }

  // ===== الصور =====
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    try {
      final svc = await RepairsService.instance();

      // لإظهار أن النظام يعمل ولا يعلق
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⏳ جاري معالجة الصور...')),
      );

      for (final raw in picked) {
        // 1) ضغط الصورة
        final compressed =
            await ImageStorageService.compressImage(XFile(raw.path));

        // 2) حفظ الصورة
        final savedPath = await ImageStorageService.saveImage(
          image: compressed,
          vehicleType: _repair.vehicleType,
          vehicleNumber: _repair.vehicleNumber,
          beneficiaryName: _repair.beneficiaryName,
          receivedDate: _repair.receivedDate,
        );

        // 3) إضافة المسار إلى DB
        await svc.addImagePath(repairId: _repair.id, path: savedPath);

        // 4) إنشاء Thumbnail إذا ليس موجودًا
        if ((_repair.thumbnailPath ?? '').isEmpty) {
          final thumbPath =
              await ImageStorageService.generateThumbnail(savedPath);
          await svc.updateThumbnail(
            repairId: _repair.id,
            thumbPath: thumbPath,
          );
        }
      }

      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ تم حفظ الصور')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ فشل إضافة الصور: $e')));
    }
  }

  Future<void> _deleteImage(String path) async {
    try {
      final svc = await RepairsService.instance();

      // 1) حذف من القرص
      await ImageStorageService.deleteImage(path);

      // 2) حذف من DB
      await svc.removeImagePath(path: path);

      // 3) إزالة الغلاف إن كان هو نفسه
      if (_repair.thumbnailPath == path) {
        await svc.updateThumbnail(
          repairId: _repair.id,
          thumbPath: null,
        );
      }

      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🗑️ تم حذف الصورة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ فشل حذف الصورة: $e')));
    }
  }

// ===============================
// 🔍 عارض الصور مع دعم الأسهم + Delete + ESC
// ===============================
  void _openPreview(List<String> images, int start) {
    int current = start;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dlgCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Shortcuts(
            shortcuts: <LogicalKeySet, Intent>{
              LogicalKeySet(LogicalKeyboardKey.arrowLeft):
                  const MoveSelectionLeftIntent(),
              LogicalKeySet(LogicalKeyboardKey.arrowRight):
                  const MoveSelectionRightIntent(),
              LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
              LogicalKeySet(LogicalKeyboardKey.delete):
                  const DeleteImageIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                MoveSelectionLeftIntent:
                    CallbackAction<MoveSelectionLeftIntent>(
                  onInvoke: (intent) {
                    setState(() {
                      current = (current - 1 + images.length) % images.length;
                    });
                    return null;
                  },
                ),
                MoveSelectionRightIntent:
                    CallbackAction<MoveSelectionRightIntent>(
                  onInvoke: (intent) {
                    setState(() {
                      current = (current + 1) % images.length;
                    });
                    return null;
                  },
                ),
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (intent) {
                    Navigator.pop(dlgCtx);
                    return null;
                  },
                ),
                DeleteImageIntent: CallbackAction<DeleteImageIntent>(
                  onInvoke: (intent) async {
                    final ok = await showDialog<bool>(
                      context: dlgCtx,
                      builder: (_) => AdaptiveAlertDialog(
                        title: const Text('حذف الصورة'),
                        content: const Text('هل تريد حذف هذه الصورة نهائيًا؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(_, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(_, true),
                            child: const Text('ط­ط°ظپ'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _deleteImage(images[current]);
                      Navigator.pop(dlgCtx);
                    }
                    return null;
                  },
                ),
              },
              child: StatefulBuilder(
                builder: (ctx, setDlg) {
                  final viewport = MediaQuery.sizeOf(ctx);
                  final phone = viewport.width < 600;
                  return SizedBox(
                    width: phone ? viewport.width - 24 : 900,
                    height: phone
                        ? (viewport.height * 0.72)
                            .clamp(320.0, 720.0)
                            .toDouble()
                        : 720,
                    child: Stack(
                      children: [
                        Center(
                          child: InteractiveViewer(
                            minScale: 0.5,
                            maxScale: 5,
                            child: Image.file(
                              File(images[current]),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // زر إغلاق
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(dlgCtx),
                          ),
                        ),

                        // سهم يسار
                        if (images.length > 1)
                          Positioned(
                            left: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_back_ios,
                                  color: Colors.white),
                              onPressed: () {
                                setDlg(() {
                                  current = (current - 1 + images.length) %
                                      images.length;
                                });
                              },
                            ),
                          ),

                        // سهم يمين
                        if (images.length > 1)
                          Positioned(
                            right: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_forward_ios,
                                  color: Colors.white),
                              onPressed: () {
                                setDlg(() {
                                  current = (current + 1) % images.length;
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ===== PDF =====
  Future<void> _sharePdf() async {
    try {
      final bytes = await RepairPdfGenerator.generate(_repair);
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/repair_${_repair.id}.pdf';
      final file = File(path);
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(path)], text: 'كشف إصلاح المركبة');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ فشل المشاركة: $e')));
    }
  }

  Future<void> _printPdf() async {
    try {
      final bytes = await RepairPdfGenerator.generate(_repair);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('❌ فشل الطباعة: $e')));
    }
  }

  Map<String, dynamic> _normalizeRow(Map<String, dynamic> row) {
    final desc = row['name'] ?? row['description'] ?? row['desc'] ?? '';
    final priceRaw = row['price'] ?? row['amount'] ?? row['cost'] ?? 0;
    final price = (priceRaw is num)
        ? priceRaw.toDouble()
        : double.tryParse(priceRaw.toString()) ?? 0.0;
    return {'name': '$desc', 'price': price};
  }

  Future<void> _loadPersistedRepairLines() async {
    try {
      final snapshot = await RepairLineBridge.load(widget.repair.id);
      if (!mounted || snapshot.count == 0) return;
      setState(() {
        _repairWorks
          ..clear()
          ..addAll(snapshot.works);
        _repairParts
          ..clear()
          ..addAll(snapshot.parts);
      });
    } catch (_) {
      // Backward compatibility: keep any lines already carried by older Repair objects.
    }
  }

  Future<void> _loadP07PayerVisibility() async {
    try {
      final payer = await RepairPayerBridge.load(widget.repair.id);
      if (!mounted) return;
      setState(() {
        _hideP07InsuranceStatus = payer == RepairPayerKind.customer;
      });
    } catch (_) {
      // Legacy-safe fallback: keep the existing insurance UI unchanged.
    }
  }

  Widget _buildDataTable(String title, List<Map<String, dynamic>> data) {
    final normalized = data.map(_normalizeRow).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FlexColumnWidth(2)
              },
              border: TableBorder.all(color: Colors.grey),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  children: const [
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('الوصف',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text('السعر',
                            style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
                ...normalized.map((row) => TableRow(children: [
                      Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(row['name'] ?? '')),
                      Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                              MoneyFormatter.format(row['price'] as double))),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // شريط الصور
  Widget _buildImagesStrip() {
    if (_repair.imagePaths.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AdaptiveRow(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📷 صور المركبة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_a_photo),
                onPressed: _pickImages,
                tooltip: 'إضافة صور',
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('📷 صور المركبة',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_a_photo),
                  onPressed: _pickImages,
                  tooltip: 'إضافة صور',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 130,
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(overscroll: false),
                child: Scrollbar(
                  controller: _imagesScrollCtrl,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _imagesScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _repair.imagePaths.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, idx) {
                      final path = _repair.imagePaths[idx];
                      return GestureDetector(
                        onTap: () => _openPreview(_repair.imagePaths, idx),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                File(
                                    path), // ← الصورة الصحيحة وليس الـ thumbnail
                                key: ValueKey(path),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AdaptiveAlertDialog(
                                      title: const Text('حذف الصورة'),
                                      content:
                                          const Text('تأكيد حذف هذه الصورة؟'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(_, false),
                                            child: const Text('إلغاء')),
                                        ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(_, true),
                                            child: const Text('ط­ط°ظپ')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await _deleteImage(path);
                                  }
                                },
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close,
                                      color: Colors.white, size: 16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== لوحة الحالة — نصف المساحة لكل قائمة، جنب بعض =====
  Widget _buildStatusPanel() {
    final currentInsurance =
        normalizeOrNull(_repair.insuranceStatus, _insuranceOptions) ??
            _repair.insuranceStatus;
    final currentVehicle =
        normalizeOrNull(_repair.vehicleStatus, _vehicleOptions) ??
            _repair.vehicleStatus;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AdaptiveRow(
          children: [
            // حالة التأمين
            if (!_hideP07InsuranceStatus) /* P07_PAYER_STATUS_COLLECTION_GUARD */
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('حالة التأمين',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _insuranceOptions.contains(currentInsurance)
                          ? currentInsurance
                          : null,
                      items: _insuranceOptions
                          .map(
                              (v) => DropdownMenuItem(value: v, child: Text(v)))
                          .toList(),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (v) {
                        if (v != null) _updateInsuranceStatus(v);
                      },
                    ),
                  ],
                ),
              ),

            const SizedBox(width: 16),

            // حالة المركبة
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('حالة المركبة',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _vehicleOptions.contains(currentVehicle)
                        ? currentVehicle
                        : null,
                    items: _vehicleOptions
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) {
                      if (v != null) _updateVehicleStatus(v);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // شريط الإجراءات
  Widget _buildActionsBar() {
    final remaining = (_repair.totalFileValue) - (_repair.totalPaidAmount);
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'المتبقي: ${MoneyFormatter.format(remaining)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsetsDirectional.only(start: 8),
              child: Text('✅ تم الاعتماد المحاسبي',
                  style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneDetails({
    required String repairType,
    required String vehicleStatus,
    required String insuranceStatus,
    required bool hasInvoice,
    required String? thumb,
  }) {
    final remaining = _repair.remainingAmount;

    Widget metric(String label, String value, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.lightGrey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(icon, color: AppColors.primary, size: 21),
              const SizedBox(height: 10),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: ui.TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
    }

    Widget infoRow(String label, String value, IconData icon) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(label, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          _repair.vehicleNumber.isEmpty
              ? 'تفاصيل ملف الإصلاح'
              : _repair.vehicleNumber,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'share') {
                await _sharePdf();
              } else if (value == 'print') {
                await _printPdf();
              } else if (value == 'save') {
                try {
                  final file =
                      await RepairPdfGenerator.saveToFileAndOpen(_repair);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم إنشاء PDF: ${file.path}')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('فشل إنشاء PDF: $e')),
                  );
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.ios_share_rounded),
                  title: Text('مشاركة PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('معاينة / حفظ PDF'),
                ),
              ),
              PopupMenuItem(
                value: 'print',
                child: ListTile(
                  leading: Icon(Icons.print_outlined),
                  title: Text('طباعة'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _reloadRepair,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            if (thumb != null && File(thumb).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  File(thumb),
                  height: 185,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (thumb != null) const SizedBox(height: 12),
            Row(
              children: [
                metric(
                  'قيمة الملف',
                  MoneyFormatter.format(_repair.totalFileValue),
                  Icons.receipt_long_outlined,
                ),
                const SizedBox(width: 10),
                metric(
                  'المدفوع',
                  MoneyFormatter.format(_repair.totalPaidAmount),
                  Icons.payments_outlined,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                metric(
                  'المتبقي',
                  MoneyFormatter.format(remaining),
                  Icons.account_balance_wallet_outlined,
                ),
                const SizedBox(width: 10),
                metric(
                  'الحالة',
                  vehicleStatus,
                  Icons.car_repair_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: AppColors.lightGrey),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    infoRow(
                        'المركبة',
                        '${_repair.vehicleType} ${_repair.vehicleModel}',
                        Icons.directions_car_outlined),
                    const Divider(height: 1),
                    infoRow('المستفيد', _repair.beneficiaryName,
                        Icons.person_outline_rounded),
                    const Divider(height: 1),
                    infoRow('نوع الإصلاح', repairType, Icons.build_outlined),
                    const Divider(height: 1),
                    infoRow('تاريخ الاستلام', _df.format(_repair.receivedDate),
                        Icons.calendar_today_outlined),
                    if (_repair.beneficiaryType == 'شركة تأمين') ...[
                      const Divider(height: 1),
                      infoRow(
                          'التأمين', insuranceStatus, Icons.shield_outlined),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildStatusPanel(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _addPayment,
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('إضافة دفعة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    onPressed: _pickImages,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('إضافة صور'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildImagesStrip(),
            const SizedBox(height: 14),
            _buildDataTable('أعمال الإصلاح', _repairWorks),
            const SizedBox(height: 12),
            _buildDataTable('القطع المطلوبة', _repairParts),
            const SizedBox(height: 14),
            _buildActionsBar(),
            if (hasInvoice) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(
                  AppRoutes.invoiceView,
                  arguments: _repair.invoiceId!,
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('عرض الفاتورة'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;
    final f = DateFormat('yyyy-MM-dd');
    final String? firstImg =
        _repair.imagePaths.isNotEmpty ? _repair.imagePaths.first : null;

// إذا كان للملف صورة غلاف موجودة في قاعدة البيانات → استخدمها
    final String? thumb = _repair.thumbnailPath?.isNotEmpty == true
        ? _repair.thumbnailPath
        : firstImg;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final repairType =
        normalizeOrNull(_repair.repairType, kRepairTypes) ?? _repair.repairType;
    final vehicleStatus = normalizeValue(
            _repair.vehicleStatus, kVehicleStatuses,
            aliases: kVehicleStatusAliases) ??
        _repair.vehicleStatus;
    final insuranceStatus =
        normalizeOrNull(_repair.insuranceStatus, _insuranceOptions) ??
            _repair.insuranceStatus;

    final hasInvoice =
        (_repair.invoiceId != null && _repair.invoiceId!.trim().isNotEmpty);

    if (MediaQuery.sizeOf(context).width < 600) {
      return _buildPhoneDetails(
        repairType: repairType,
        vehicleStatus: vehicleStatus,
        insuranceStatus: insuranceStatus,
        hasInvoice: hasInvoice,
        thumb: thumb,
      );
    }

    return Scaffold(
      body: AdaptiveRow(
        children: [
          const YallaSidebar(currentRoute: AppRoutes.repairDetail),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('تفاصيل إصلاح المركبة'),
                actions: [
                  IconButton(
                    tooltip: 'حفظ ملف PDF وفتحه',
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      try {
                        final file =
                            await RepairPdfGenerator.saveToFileAndOpen(_repair);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('✅ تم الحفظ والفتح:\n${file.path}')));
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('❌ فشل إنشاء PDF: $e')));
                      }
                    },
                  ),
                  IconButton(
                      tooltip: 'مشاركة PDF',
                      icon: const Icon(Icons.share),
                      onPressed: _sharePdf),
                  IconButton(
                      tooltip: 'طباعة',
                      icon: const Icon(Icons.print),
                      onPressed: _printPdf),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: isWide
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // الصف العلوي
                          AdaptiveRow(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // العمود الأيسر: المالية + لوحة الحالة
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Card(
                                      child: ListTile(
                                        leading: RepairThumb(
                                          repairId: _repair.id,
                                          fallbackFirstPath:
                                              thumb, // ← استبدلنا firstImg بالـ thumbnail
                                          size: 56,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        title:
                                            const Text('البيانات المالية 💰'),
                                        subtitle: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                                'حالة السداد: ${_repair.displayPaymentStatus}'),
                                            Text(
                                                'قيمة الملف: ${MoneyFormatter.format(_repair.totalFileValue)}'),
                                            Text(
                                                'المدفوع: ${MoneyFormatter.format(_repair.totalPaidAmount)}'),
                                            Text(
                                                'المتبقي: ${MoneyFormatter.format(_repair.remainingAmount)}'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildStatusPanel(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              // العمود الأيمن: بيانات المركبة والمستفيد + الفاتورة/GL
                              Expanded(
                                flex: 4,
                                child: Card(
                                  child: ListTile(
                                    title:
                                        const Text('بيانات المركبة والمستفيد'),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('نوع: ${_repair.vehicleType}'),
                                        Text(
                                            'الموديل: ${_repair.vehicleModel}'),
                                        Text('رقم: ${_repair.vehicleNumber}'),
                                        Text(
                                            'تاريخ الاستلام: ${f.format(_repair.receivedDate)}'),
                                        Text('نوع العمل: $repairType'),
                                        Text('حالة المركبة: $vehicleStatus'),
                                        const SizedBox(height: 8),
                                        Text(
                                            'نوع المستفيد: ${_repair.beneficiaryType}'),
                                        Text(
                                            'الاسم: ${_repair.beneficiaryName}'),
                                        if (_repair.beneficiaryType ==
                                            'شركة تأمين')
                                          Text(
                                              'متابعة التأمين: $insuranceStatus'),
                                        const SizedBox(height: 12),
                                        if (hasInvoice)
                                          if (!hasInvoice)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 12),
                                              child: OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.playlist_add),
                                                label: const Text(
                                                    'إنشاء فاتورة وترحيل GL'),
                                                onPressed: () async {
                                                  try {
                                                    final db = await DBService
                                                        .database;

                                                    // 1) إنشاء فاتورة جديدة
                                                    final invoiceId =
                                                        await DBService
                                                            .createInvoiceForRepair(
                                                      repairId: _repair.id,
                                                      clientId:
                                                          _repair.clientId,
                                                      total: _repair
                                                          .totalFileValue,
                                                    );

                                                    // 2) تحديث repair → invoiceId
                                                    await db.update(
                                                      'repairs',
                                                      {
                                                        'invoice_id': invoiceId,
                                                        'invoiceId': invoiceId
                                                      },
                                                      where: 'id = ?',
                                                      whereArgs: [_repair.id],
                                                    );

                                                    // 3) ترحيل قيد GL
                                                    final glId = await DBService
                                                        .postInvoiceGLFromId(
                                                            invoiceId);

                                                    // 4) إعادة تحميل البيانات
                                                    await _reloadRepair();

                                                    if (!mounted) return;

                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                            'تم إنشاء الفاتورة وترحيل GL (#$glId)'),
                                                      ),
                                                    );
                                                  } catch (e) {
                                                    if (!mounted) return;
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                          content: Text(
                                                              'فشل العملية: $e')),
                                                    );
                                                  }
                                                },
                                              ),
                                            ),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            ElevatedButton.icon(
                                              icon: const Icon(
                                                  Icons.receipt_long),
                                              label: const Text('عرض الفاتورة'),
                                              onPressed: () {
                                                Navigator.of(context).pushNamed(
                                                  AppRoutes.invoiceView,
                                                  arguments: _repair.invoiceId!,
                                                );
                                              },
                                            ),
                                            if (_invoiceGlEntryId == null)
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.playlist_add),
                                                label: const Text(
                                                    'ترحيل GL للفاتورة'),
                                                onPressed:
                                                    _postInvoiceGLIfMissing,
                                              )
                                            else ...[
                                              ElevatedButton.icon(
                                                icon: const Icon(
                                                    Icons.account_balance),
                                                label: Text(
                                                    'عرض قيد GL #$_invoiceGlEntryId'),
                                                onPressed: () {
                                                  Navigator.of(context)
                                                      .pushNamed(
                                                    AppRoutes.financeGL,
                                                    arguments: {
                                                      'entryId':
                                                          _invoiceGlEntryId
                                                    },
                                                  );
                                                },
                                              ),
                                              OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.travel_explore),
                                                label: const Text(
                                                    'ظپطھط­ GL Browser'),
                                                onPressed: () {
                                                  Navigator.of(context)
                                                      .pushNamed(
                                                    AppRoutes.financeGL,
                                                    arguments: {
                                                      'source': 'INVOICE',
                                                      'source_id':
                                                          _repair.invoiceId
                                                    },
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // شريط الإجراءات
                          _buildActionsBar(),

                          const SizedBox(height: 16),

                          // شريط الصور
                          _buildImagesStrip(),

                          const SizedBox(height: 16),

                          // الجداول
                          _buildDataTable('أعمال الإصلاح', _repairWorks),
                          const SizedBox(height: 16),
                          _buildDataTable('القطع المطلوبة', _repairParts),
                        ],
                      )
                    : const Center(child: Text('الشاشة صغيرة جدًا')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PayMethod {
  final String key; // 'cash' | 'bank'
  final String label;
  const _PayMethod(this.key, this.label);
}
// ===============================
// 🔑 Intents (Top-Level)
// ===============================

class MoveSelectionLeftIntent extends Intent {
  const MoveSelectionLeftIntent();
}

class MoveSelectionRightIntent extends Intent {
  const MoveSelectionRightIntent();
}

class DismissIntent extends Intent {
  const DismissIntent();
}

class DeleteImageIntent extends Intent {
  const DeleteImageIntent();
}
