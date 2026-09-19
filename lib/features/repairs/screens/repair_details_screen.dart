import 'package:yalla_accounts/core/utils/user_facing_error.dart';
import 'package:yalla_accounts/core/services/sync/sync_foundation_service.dart';
// 📁 lib/features/repairs/screens/repair_details_screen.dart
// - حالة التأمين + حالة المركبة جنب بعض داخل البطاقة اليسرى.
// - تحديث ذكي لأسماء الأعمدة (يكتشف العمود الصحيح قبل UPDATE).
// - دفعات، صور، PDF، GL؛ الحفظ المحاسبي تلقائي.

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
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';

import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db_service.dart';

import 'package:yalla_accounts/features/repairs/models/repair.dart';
import 'package:yalla_accounts/features/repairs/services/repairs_service.dart';
import 'package:yalla_accounts/features/repairs/services/repair_pdf_generator.dart';

import 'package:yalla_accounts/features/repairs/constants/repair_status.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_thumb.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_workflow_card.dart';
import 'package:yalla_accounts/features/repairs/widgets/repair_profitability_card.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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

  List<Map<String, dynamic>> _repairWorks = [];
  List<Map<String, dynamic>> _repairParts = [];
  List<Map<String, Object?>> _changeHistory = [];

  final _df = DateFormat('yyyy-MM-dd');
  final _historyDf = DateFormat('yyyy-MM-dd HH:mm');

  int? _invoiceGlEntryId;

  final ScrollController _imagesScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // P07_PAYER_DETAILS_INIT
    _loadP07PayerVisibility();
    // P07_LINE_READBACK_INIT
    _repair = widget.repair;
    _loadRepairDetails();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _reloadRepair();
      if (!mounted) return;
      final svc = await RepairsService.instance();
      await svc.autoSelectCoverAndSave(repairId: _repair.id);
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
    await _loadChangeHistory();
  }

  Future<void> _reloadRepair() async {
    final svc = await RepairsService.instance();
    final r = await svc.getById(_repair.id);
    if (!mounted) return;
    if (r != null) {
      setState(() => _repair = r);
      await _refreshInvoiceGl();
      await _loadChangeHistory();
    }
  }

  Future<void> _loadChangeHistory() async {
    if (_repair.id.isEmpty) {
      if (mounted) setState(() => _changeHistory = []);
      return;
    }

    try {
      final db = await DBService.database;
      final table = await db.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = 'repair_edit_history' LIMIT 1",
      );
      if (!mounted) return;
      if (table.isEmpty) {
        setState(() => _changeHistory = []);
        return;
      }

      final rows = await db.query(
        'repair_edit_history',
        where: 'repair_id = ?',
        whereArgs: [_repair.id],
        orderBy: 'created_at DESC',
        limit: 20,
      );
      if (!mounted) return;
      setState(() => _changeHistory = List<Map<String, Object?>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _changeHistory = []);
    }
  }

  String get _visibleNotes {
    final raw = _repair.notes?.trim() ?? '';
    if (raw.isEmpty) return '';

    return raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('[YALLA_'))
        .join('\n');
  }

  String _formatHistoryDate(Object? value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return _historyDf.format(parsed.toLocal());
  }

  double _historyNumber(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
      await SyncFoundationService.writeOn(
          db,
          (txn) => txn.update('repairs', {col: value},
              where: 'id = ?', whereArgs: [_repair.id]));
      await _reloadRepair();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل تحديث الحالة: ${UserFacingError.message(e)}')));
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
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _invoiceGlEntryId =
            row.isNotEmpty ? int.tryParse('${row.first['id']}') : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _invoiceGlEntryId = null);
    }
  }

  // ===== الدفعات =====
  Future<void> _addPayment() async {
    if (_repair.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن إضافة دفعة قبل حفظ ملف الإصلاح.'),
        ),
      );
      return;
    }

    if (_repair.remainingAmount <= 0.005) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الملف مسدد بالكامل')),
      );
      return;
    }

    final updated = await Navigator.of(context).pushNamed(
      AppRoutes.receiptVoucher,
      arguments: <String, Object?>{
        'repairId': _repair.id,
        'clientId': _repair.clientId,
        'clientType': _repair.beneficiaryType,
      },
    );

    if (updated == true) {
      await _reloadRepair();
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

        // 3) إضافة المسار إلى DB. RepairsService scores the available
        // vehicle photos and maintains one canonical profile thumbnail.
        await svc.addImagePath(repairId: _repair.id, path: savedPath);
      }

      // Final pass after the whole batch: insertion order never decides which
      // photo becomes the vehicle profile.
      await svc.autoSelectCoverAndSave(repairId: _repair.id);
      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('✅ تم حفظ الصور')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ فشل إضافة الصور: ${UserFacingError.message(e)}')));
    }
  }

  Future<void> _deleteImage(String path) async {
    try {
      final svc = await RepairsService.instance();

      // 1) حذف من القرص
      await ImageStorageService.deleteImage(path);

      // 2) حذف من DB
      await svc.removeImagePath(path: path);

      // removeImagePath re-scores the remaining photos automatically.
      await _reloadRepair();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('🗑️ تم حذف الصورة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ فشل حذف الصورة: ${UserFacingError.message(e)}')));
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
                      builder: (dialogContext) => AdaptiveAlertDialog(
                        title: const Text('حذف الصورة'),
                        content: const Text('هل تريد حذف هذه الصورة نهائيًا؟'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('ط­ط°ظپ'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _deleteImage(images[current]);
                      if (!dlgCtx.mounted) return null;
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
                            child: FutureBuilder<String?>(
                              future: YallaStorageService.resolveExistingPath(
                                images[current],
                              ),
                              builder: (context, snapshot) {
                                final resolved = snapshot.data;
                                if (resolved == null) {
                                  return const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white70,
                                      size: 42,
                                    ),
                                  );
                                }
                                final decodeWidth = (viewport.width *
                                        MediaQuery.devicePixelRatioOf(context) *
                                        1.5)
                                    .round()
                                    .clamp(1024, 2048)
                                    .toInt();
                                return Image.file(
                                  File(resolved),
                                  fit: BoxFit.contain,
                                  cacheWidth: decodeWidth,
                                );
                              },
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
      if (!mounted) return;
      final screenSize = MediaQuery.sizeOf(context);
      final shareOrigin = Rect.fromLTWH(
        screenSize.width / 2,
        screenSize.height / 2,
        1,
        1,
      );
      await Share.shareXFiles(
        [XFile(path)],
        text: 'كشف إصلاح المركبة',
        sharePositionOrigin: shareOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ فشل المشاركة: ${UserFacingError.message(e)}')));
    }
  }

  Future<void> _printPdf() async {
    try {
      final bytes = await RepairPdfGenerator.generate(_repair);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('❌ فشل الطباعة: ${UserFacingError.message(e)}')));
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
                              child: YallaStoredImage(
                                storedPath: path,
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
                                    builder: (dialogContext) =>
                                        AdaptiveAlertDialog(
                                      title: const Text('حذف الصورة'),
                                      content:
                                          const Text('تأكيد حذف هذه الصورة؟'),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(
                                                dialogContext, false),
                                            child: const Text('إلغاء')),
                                        ElevatedButton(
                                            onPressed: () => Navigator.pop(
                                                dialogContext, true),
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

  Widget _buildWorkflowCard() {
    return RepairWorkflowCard(
      repair: _repair,
      onChanged: _reloadRepair,
      onShareEstimate: _sharePdf,
    );
  }

  Widget _buildStatusPanel() {
    final currentInsurance =
        normalizeOrNull(_repair.insuranceStatus, kInsuranceFollowups) ??
            _repair.insuranceStatus;
    final currentVehicle = normalizeValue(
            _repair.vehicleStatus, kVehicleStatuses,
            aliases: kVehicleStatusAliases) ??
        _repair.vehicleStatus;

    final insuranceOptions = <String>[...kInsuranceFollowups];
    if (currentInsurance.trim().isNotEmpty &&
        !insuranceOptions.contains(currentInsurance)) {
      insuranceOptions.insert(0, currentInsurance);
    }

    final workflowOwnsVehicleStatus =
        kWorkflowVehicleStatuses.contains(currentVehicle);
    final vehicleOptions = workflowOwnsVehicleStatus
        ? <String>[currentVehicle]
        : <String>[...kManualVehicleStatuses];
    if (currentVehicle.trim().isNotEmpty &&
        !vehicleOptions.contains(currentVehicle)) {
      vehicleOptions.insert(0, currentVehicle);
    }

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
                      value: insuranceOptions.contains(currentInsurance)
                          ? currentInsurance
                          : null,
                      items: insuranceOptions
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
                    value: vehicleOptions.contains(currentVehicle)
                        ? currentVehicle
                        : null,
                    items: vehicleOptions
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: workflowOwnsVehicleStatus
                        ? null
                        : (v) {
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

  Widget _buildNotesCard() {
    final notes = _visibleNotes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الملاحظات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              notes.isEmpty ? 'لا توجد ملاحظات مسجلة.' : notes,
              style: TextStyle(
                color: notes.isEmpty ? Colors.black54 : Colors.black87,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChangeHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'سجل التغييرات',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'يعرض التغييرات المالية المسجلة حاليًا على الملف.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (_changeHistory.isEmpty)
              const Text(
                'لا توجد تغييرات مالية مسجلة لهذا الملف.',
                style: TextStyle(color: Colors.black54),
              )
            else
              ..._changeHistory.map((row) {
                final oldValue = _historyNumber(row['old_value']);
                final newValue = _historyNumber(row['new_value']);
                final difference = _historyNumber(row['difference']);
                final editedBy = (row['edited_by'] ?? '').toString().trim();
                final notes = (row['notes'] ?? '').toString().trim();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.lightGrey),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${MoneyFormatter.format(oldValue)} → ${MoneyFormatter.format(newValue)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الفرق: ${MoneyFormatter.format(difference)}',
                          style: const TextStyle(color: Colors.black87),
                        ),
                        Text(
                          'التاريخ: ${_formatHistoryDate(row['created_at'])}',
                          style: const TextStyle(color: Colors.black54),
                        ),
                        if (editedBy.isNotEmpty)
                          Text(
                            'بواسطة: $editedBy',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(notes),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentButton({bool filled = false}) {
    final canAddPayment = _repair.remainingAmount > 0.005;
    if (!canAddPayment) return const SizedBox.shrink();

    if (filled) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          minimumSize: const Size.fromHeight(50),
        ),
        onPressed: _addPayment,
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('إضافة دفعة'),
      );
    }

    return ElevatedButton.icon(
      onPressed: _addPayment,
      icon: const Icon(Icons.add_card_rounded),
      label: const Text('إضافة دفعة'),
    );
  }

  // شريط الإجراءات
  Widget _buildActionsBar({bool showPaymentAction = true}) {
    final remaining = _repair.remainingAmount;
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            Text(
              'المتبقي: ${MoneyFormatter.format(remaining)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const Text(
              '✅ محفوظ محاسبيًا تلقائيًا',
              style: TextStyle(color: AppColors.primary),
            ),
            if (showPaymentAction && remaining > 0.005) _buildPaymentButton(),
          ],
        ),
      ),
    );
  }

  // STAGE1_P0_01_FINAL_FIX4C_PHONE_PARITY
  // Mobile Repair Details keeps the desktop screen as the functional source
  // of truth while using a single-column phone layout. All actions below reuse
  // the existing services/routes/widgets; no business data is reimplemented.
  Widget _buildPhoneDetailsParity({
    required String repairType,
    required String vehicleStatus,
    required String insuranceStatus,
    required bool hasInvoice,
    required String? thumb,
  }) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'تفاصيل إصلاح المركبة',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _reloadRepair,
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) async {
              if (value == 'share') {
                await _sharePdf();
              } else if (value == 'print') {
                await _printPdf();
              } else if (value == 'save') {
                try {
                  await RepairPdfGenerator.saveToFileAndOpen(_repair);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم إنشاء ملف PDF بنجاح.')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(
                            'فشل إنشاء PDF: ${UserFacingError.message(e)}')),
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            Card(
              child: ListTile(
                leading: RepairThumb(
                  repairId: _repair.id,
                  fallbackFirstPath: thumb,
                  size: 64,
                  borderRadius: BorderRadius.circular(10),
                ),
                title: const Text('البيانات المالية 💰'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('حالة السداد: ${_repair.displayPaymentStatus}'),
                    Text(
                      'قيمة الملف: ${MoneyFormatter.format(_repair.totalFileValue)}',
                    ),
                    Text(
                      'المدفوع: ${MoneyFormatter.format(_repair.totalPaidAmount)}',
                    ),
                    Text(
                      'المتبقي: ${MoneyFormatter.format(_repair.remainingAmount)}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: const Text('بيانات المركبة والمستفيد'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نوع: ${_repair.vehicleType}'),
                    Text('الموديل: ${_repair.vehicleModel}'),
                    Text('رقم: ${_repair.vehicleNumber}'),
                    Text('تاريخ الاستلام: ${_df.format(_repair.receivedDate)}'),
                    Text('نوع العمل: $repairType'),
                    Text('حالة المركبة: $vehicleStatus'),
                    const SizedBox(height: 8),
                    Text('نوع المستفيد: ${_repair.beneficiaryType}'),
                    Text('الاسم: ${_repair.beneficiaryName}'),
                    if (_repair.beneficiaryType == 'شركة تأمين')
                      Text('متابعة التأمين: $insuranceStatus'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).pushNamed(
                            AppRoutes.financeGL,
                          ),
                          icon: const Icon(Icons.account_balance_outlined),
                          label: const Text('فتح GL Browser'),
                        ),
                        if (hasInvoice)
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pushNamed(
                              AppRoutes.invoiceView,
                              arguments: _repair.invoiceId!,
                            ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('عرض الفاتورة'),
                          ),
                        if (_invoiceGlEntryId != null)
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pushNamed(
                              AppRoutes.financeGLEntry,
                              arguments: _invoiceGlEntryId!,
                            ),
                            icon: const Icon(Icons.account_balance),
                            label: Text('عرض قيد GL #$_invoiceGlEntryId'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildWorkflowCard(),
            const SizedBox(height: 12),
            _buildStatusPanel(),
            const SizedBox(height: 12),
            RepairProfitabilityCard(
              repairId: _repair.id,
              isClosed: _repair.isClosed,
            ),
            _buildActionsBar(),
            const SizedBox(height: 16),
            _buildImagesStrip(),
            const SizedBox(height: 16),
            _buildDataTable('أعمال الإصلاح', _repairWorks),
            const SizedBox(height: 16),
            _buildDataTable('القطع المطلوبة', _repairParts),
            const SizedBox(height: 16),
            _buildNotesCard(),
            const SizedBox(height: 16),
            _buildChangeHistoryCard(),
          ],
        ),
      ),
    );
  }

  // STAGE1_RUNTIME_FIX3B_REPAIR_PHONE_SAFE_BODY
  // Runtime evidence showed that the previous phone body could still collapse
  // to Flutter's grey ErrorWidget. Keep the iPhone acceptance path deliberately
  // small and self-contained: core Repair fields plus persisted works/parts,
  // using only stock Material widgets and existing data already loaded by this
  // screen. Desktop/tablet behavior remains unchanged.
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= YallaBreakpoints.desktop;
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
        normalizeOrNull(_repair.insuranceStatus, kInsuranceFollowups) ??
            _repair.insuranceStatus;

    final hasInvoice =
        (_repair.invoiceId != null && _repair.invoiceId!.trim().isNotEmpty);

    if (width < YallaBreakpoints.phone) {
      return _buildPhoneDetailsParity(
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
          if (isDesktop)
            const YallaSidebar(currentRoute: AppRoutes.repairDetail),
          Expanded(
            child: Scaffold(
              drawer: isDesktop
                  ? null
                  : const Drawer(
                      child: YallaSidebar(
                        currentRoute: AppRoutes.repairDetail,
                      ),
                    ),
              appBar: AppBar(
                leading: isDesktop
                    ? null
                    : Builder(
                        builder: (context) => IconButton(
                          tooltip: 'القائمة',
                          icon: const Icon(Icons.menu),
                          onPressed: () => Scaffold.of(context).openDrawer(),
                        ),
                      ),
                title: const Text('تفاصيل إصلاح المركبة'),
                actions: [
                  IconButton(
                    tooltip: 'حفظ ملف PDF وفتحه',
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      try {
                        await RepairPdfGenerator.saveToFileAndOpen(_repair);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('✅ تم حفظ وفتح ملف PDF بنجاح.')));
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                '❌ فشل إنشاء PDF: ${UserFacingError.message(e)}')));
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
                child: isDesktop
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
                                    _buildWorkflowCard(),
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
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: <Widget>[
                                              ElevatedButton.icon(
                                                icon: const Icon(
                                                    Icons.receipt_long),
                                                label:
                                                    const Text('عرض الفاتورة'),
                                                onPressed: () {
                                                  Navigator.of(context)
                                                      .pushNamed(
                                                    AppRoutes.invoiceView,
                                                    arguments:
                                                        _repair.invoiceId!,
                                                  );
                                                },
                                              ),
                                              if (_invoiceGlEntryId != null)
                                                ElevatedButton.icon(
                                                  icon: const Icon(
                                                      Icons.account_balance),
                                                  label: Text(
                                                    'عرض قيد GL #$_invoiceGlEntryId',
                                                  ),
                                                  onPressed: () {
                                                    Navigator.of(context)
                                                        .pushNamed(
                                                      AppRoutes.financeGL,
                                                      arguments: <String,
                                                          Object?>{
                                                        'entryId':
                                                            _invoiceGlEntryId,
                                                      },
                                                    );
                                                  },
                                                )
                                              else
                                                const Text(
                                                  'الفاتورة موجودة وتحتاج مراجعة ربط القيد المحاسبي.',
                                                  style: TextStyle(
                                                      color: Colors.orange),
                                                ),
                                            ],
                                          )
                                        else
                                          Text(
                                            _repair.totalFileValue <= 0
                                                ? 'لا توجد فاتورة لأن قيمة الملف الحالية صفر.'
                                                : 'سيتم إنشاء المستند المحاسبي تلقائيًا عند حفظ/تعديل الملف.',
                                            style: const TextStyle(
                                                color: Colors.black54),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          RepairProfitabilityCard(
                            repairId: _repair.id,
                            isClosed: _repair.isClosed,
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
                          const SizedBox(height: 16),
                          _buildNotesCard(),
                          const SizedBox(height: 16),
                          _buildChangeHistoryCard(),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: ListTile(
                              leading: RepairThumb(
                                repairId: _repair.id,
                                fallbackFirstPath: thumb,
                                size: 56,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              title: const Text('البيانات المالية 💰'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'حالة السداد: ${_repair.displayPaymentStatus}',
                                  ),
                                  Text(
                                    'قيمة الملف: ${MoneyFormatter.format(_repair.totalFileValue)}',
                                  ),
                                  Text(
                                    'المدفوع: ${MoneyFormatter.format(_repair.totalPaidAmount)}',
                                  ),
                                  Text(
                                    'المتبقي: ${MoneyFormatter.format(_repair.remainingAmount)}',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: ListTile(
                              title: const Text('بيانات المركبة والمستفيد'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('نوع: ${_repair.vehicleType}'),
                                  Text('الموديل: ${_repair.vehicleModel}'),
                                  Text('رقم: ${_repair.vehicleNumber}'),
                                  Text(
                                    'تاريخ الاستلام: ${f.format(_repair.receivedDate)}',
                                  ),
                                  Text('نوع العمل: $repairType'),
                                  Text('حالة المركبة: $vehicleStatus'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'نوع المستفيد: ${_repair.beneficiaryType}',
                                  ),
                                  Text('الاسم: ${_repair.beneficiaryName}'),
                                  if (_repair.beneficiaryType == 'شركة تأمين')
                                    Text('متابعة التأمين: $insuranceStatus'),
                                  const SizedBox(height: 12),
                                  if (hasInvoice)
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: <Widget>[
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.receipt_long),
                                          label: const Text('عرض الفاتورة'),
                                          onPressed: () =>
                                              Navigator.of(context).pushNamed(
                                            AppRoutes.invoiceView,
                                            arguments: _repair.invoiceId!,
                                          ),
                                        ),
                                        if (_invoiceGlEntryId != null)
                                          ElevatedButton.icon(
                                            icon: const Icon(
                                              Icons.account_balance,
                                            ),
                                            label: Text(
                                              'عرض قيد GL #$_invoiceGlEntryId',
                                            ),
                                            onPressed: () =>
                                                Navigator.of(context).pushNamed(
                                              AppRoutes.financeGL,
                                              arguments: <String, Object?>{
                                                'entryId': _invoiceGlEntryId,
                                              },
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildWorkflowCard(),
                          const SizedBox(height: 12),
                          _buildStatusPanel(),
                          const SizedBox(height: 12),
                          RepairProfitabilityCard(
                            repairId: _repair.id,
                            isClosed: _repair.isClosed,
                          ),
                          _buildActionsBar(),
                          const SizedBox(height: 16),
                          _buildImagesStrip(),
                          const SizedBox(height: 16),
                          _buildDataTable('أعمال الإصلاح', _repairWorks),
                          const SizedBox(height: 16),
                          _buildDataTable('القطع المطلوبة', _repairParts),
                          const SizedBox(height: 16),
                          _buildNotesCard(),
                          const SizedBox(height: 16),
                          _buildChangeHistoryCard(),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
