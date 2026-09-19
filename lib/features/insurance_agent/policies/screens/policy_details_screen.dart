import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// lib/features/insurance_agent/policies/screens/policy_details_screen.dart
//
// PolicyDetailsScreen — FIXED SCROLL + NO OVERFLOW
// ✅ Scroll يعمل (فوق/تحت) Desktop + Mobile
// ✅ لا Overflow في الشيكات (عرض أفقي عند الحاجة)
// ✅ Sidebar Desktop ثابت + Mobile Overlay
// ✅ بدون RTL / Directionality (محاذاة يمين فقط)
//
// ✅ UPDATED:
// - عرض "نوع الوثيقة" + "سعر المركبة" من مصدرها الحقيقي (الـ DB row)
// - Resolve ذكي لأسماء الأعمدة المحتملة (document_type / car_price ...)
// - عرضهم داخل بطاقة التفاصيل + (Chip) اختياري في الملخص المالي

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';
import 'package:yalla_accounts/core/storage/yalla_storage_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PolicyDetailsScreen extends StatefulWidget {
  final dynamic policyId; // int ط£ظˆ String
  final Map<String, dynamic>? row;

  const PolicyDetailsScreen({
    super.key,
    this.policyId,
    this.row,
  });

  @override
  State<PolicyDetailsScreen> createState() => _PolicyDetailsScreenState();
}

class _PolicyDetailsScreenState extends State<PolicyDetailsScreen> {
  bool _loading = true;
  Map<String, dynamic>? _row;

  // Mobile/Tablet overlay sidebar
  bool _sideOpen = false;

  // ✅ Scroll controller (مهم جدًا عشان السحب يشتغل)
  final ScrollController _scrollCtrl = ScrollController();

  // ✅ Cheques
  List<Map<String, dynamic>> _cheques = [];
  bool _loadingCheques = false;

  final _df = DateFormat('yyyy-MM-dd', 'en_US');
  final _currency = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    if (widget.row != null) {
      _row = Map<String, dynamic>.from(widget.row!);
      setState(() => _loading = false);

      final pid = _effectivePolicyId();
      if (pid != null) await _loadCheques(pid);
      return;
    }

    if (widget.policyId == null) {
      setState(() => _loading = false);
      return;
    }

    await _loadFromDb(widget.policyId);
  }

  Future<void> _loadFromDb(dynamic policyId) async {
    setState(() => _loading = true);

    try {
      final db = await DatabaseMigration.database;

      final candidates = <String>['id', 'policy_id', 'uuid'];
      Map<String, dynamic>? found;

      for (final col in candidates) {
        try {
          final rows = await db.query(
            'insurance_policies',
            where: '$col = ?',
            whereArgs: [policyId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            found = Map<String, dynamic>.from(rows.first);
            break;
          }
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _row = found;
        _loading = false;
      });

      if (found == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ لم يتم العثور على البوليصة')),
        );
        return;
      }

      final pid = found['id'] ?? found['policy_id'] ?? found['uuid'];
      if (pid != null) await _loadCheques(pid);

      // رجّع السكرول لأعلى بعد التحديث (اختياري)
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('❌ فشل تحميل التفاصيل: ${UserFacingError.message(e)}')),
      );
    }
  }

  Future<void> _loadCheques(dynamic policyId) async {
    setState(() => _loadingCheques = true);

    try {
      final db = await DatabaseMigration.database;

      final rows = await db.query(
        'insurance_policy_cheques',
        where: 'policy_id = ?',
        whereArgs: [policyId],
        orderBy: 'due_date ASC',
      );

      if (!mounted) return;
      setState(() {
        _cheques = rows.map((e) => Map<String, dynamic>.from(e)).toList();
        _loadingCheques = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingCheques = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('❌ فشل تحميل الشيكات: ${UserFacingError.message(e)}')),
      );
    }
  }

  // ===========================================================================
  // ✅ Real-source resolving helpers
  // ===========================================================================
  dynamic _resolveFirstValue(Map<String, dynamic> r, List<String> keys) {
    for (final k in keys) {
      if (!r.containsKey(k)) continue;
      final v = r[k];
      if (v == null) continue;

      if (v is String) {
        final t = v.trim();
        if (t.isNotEmpty) return t;
        continue;
      }

      // num/bool/etc
      return v;
    }
    return null;
  }

  String _resolveFirstText(Map<String, dynamic> r, List<String> keys,
      {String fallback = '—'}) {
    final v = _resolveFirstValue(r, keys);
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  double _resolveFirstDouble(Map<String, dynamic> r, List<String> keys) {
    final v = _resolveFirstValue(r, keys);
    return _toDouble(v);
  }

  // ✅ "نوع الوثيقة" (طرف ثالث / شامل)
  String _documentTypeLabel(Map<String, dynamic> r) {
    // حاول مفاتيح محتملة
    final raw = _resolveFirstText(
      r,
      [
        'document_type',
        'doc_type',
        'policy_type',
        'coverage_type',
        'insurance_type',
        'insurance_doc_type',
        'policy_document_type',
      ],
      fallback: '',
    ).trim();

    if (raw.isEmpty) return '—';

    // تطبيع بسيط لو كانت القيمة محفوظة بطرق مختلفة
    final s = raw.toLowerCase();
    if (s.contains('third') || s.contains('tp') || s.contains('طرف')) {
      return 'طرف ثالث';
    }
    if (s.contains('compre') || s.contains('full') || s.contains('شامل')) {
      return 'شامل';
    }
    return raw; // إذا كانت مكتوبة جاهزة بالعربي (طرف ثالث/شامل) أو أي نص آخر
  }

  // ✅ "سعر المركبة"
  double _vehiclePriceValue(Map<String, dynamic> r) {
    // أهم مفاتيح متوقعة لسعر المركبة
    return _resolveFirstDouble(
      r,
      [
        'car_price',
        'vehicle_price',
        'car_value',
        'vehicle_value',
        'market_value',
        'sum_insured', // أحيانًا قيمة التأمين = قيمة المركبة
        'insured_value',
        'vehicle_sum_insured',
      ],
    );
  }

  String _vehiclePriceLabel(Map<String, dynamic> r) {
    final v = _vehiclePriceValue(r);
    if (v <= 0) return '—';
    return _currency.format(v);
  }

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    try {
      return DateTime.parse(s);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy', 'en_US').parseStrict(s);
      } catch (_) {
        return null;
      }
    }
  }

  bool _isExpired(Map<String, dynamic> r) {
    final end = _parseDate(r['end_date']);
    if (end == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return end.isBefore(today);
  }

  bool _isExpiringSoon(Map<String, dynamic> r) {
    final end = _parseDate(r['end_date']);
    if (end == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (end.isBefore(today)) return false;
    return end.isBefore(now.add(const Duration(days: 12)));
  }

  String _statusText(Map<String, dynamic> r) {
    if (_isExpired(r)) return 'منتهية';
    if (_isExpiringSoon(r)) return 'تنتهي قريبًا';
    return 'سارية';
  }

  Color _statusColor(Map<String, dynamic> r) {
    if (_isExpired(r)) return Colors.red;
    if (_isExpiringSoon(r)) return Colors.orange;
    return AppColors.primary;
  }

  bool _isVip(Map<String, dynamic> r) => (r['is_vip'] ?? 0) == 1;

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().trim().replaceAll(',', '');
    return double.tryParse(s) ?? 0.0;
  }

  List<String> _extractImages(Map<String, dynamic> r) {
    dynamic v = r['vehicle_images'];
    v ??= r['images'];
    v ??= r['car_images'];

    if (v == null) return [];

    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }

    final s = v.toString().trim();
    if (s.isEmpty) return [];

    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString())
            .where((x) => x.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {}

    if (s.contains(',')) {
      return s
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    return [s];
  }

  void _toggleSide(bool open) => setState(() => _sideOpen = open);

  Widget _rightSidebar({required double width}) {
    return SizedBox(
      width: width,
      child: const Material(
        elevation: 10,
        child: YallaSidebar(currentRoute: AppRoutes.insurancePoliciesList),
      ),
    );
  }

  Widget _rightOverlaySidebar({required double width}) {
    return Stack(
      children: [
        if (_sideOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _toggleSide(false),
              child: Container(color: Colors.black.withOpacity(0.25)),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          top: 0,
          bottom: 0,
          right: _sideOpen ? 0 : -width,
          width: width,
          child: _rightSidebar(width: width),
        ),
      ],
    );
  }

  // =========================
  // Smart Update
  // =========================
  Future<String?> _findExistingColumn({
    required String table,
    required List<String> candidates,
  }) async {
    final db = await DatabaseMigration.database;
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final cols = rows.map((r) => (r['name'] ?? '').toString()).toSet();
    for (final c in candidates) {
      if (cols.contains(c)) return c;
    }
    return null;
  }

  dynamic _effectivePolicyId() {
    if (widget.policyId != null) return widget.policyId;
    final r = _row;
    if (r == null) return null;
    return r['id'] ?? r['policy_id'] ?? r['uuid'];
  }

  // =========================
  // Preview Images
  // =========================
  bool _isNetwork(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  Widget _previewImageWidget(String path) {
    if (_isNetwork(path)) {
      return Image.network(
        path,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Center(child: Text('صورة غير صالحة')),
      );
    }
    return FutureBuilder<String?>(
      future: YallaStorageService.resolveExistingPath(path),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ملف غير موجود',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return Image.file(File(resolved), fit: BoxFit.contain);
      },
    );
  }

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
                  onInvoke: (_) {
                    current = (current - 1 + images.length) % images.length;
                    return null;
                  },
                ),
                MoveSelectionRightIntent:
                    CallbackAction<MoveSelectionRightIntent>(
                  onInvoke: (_) {
                    current = (current + 1) % images.length;
                    return null;
                  },
                ),
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    Navigator.pop(dlgCtx);
                    return null;
                  },
                ),
                DeleteImageIntent: CallbackAction<DeleteImageIntent>(
                  onInvoke: (_) async {
                    final ok = await showDialog<bool>(
                      context: dlgCtx,
                      builder: (c2) => AdaptiveAlertDialog(
                        title: const Text('حذف الصورة'),
                        content: const Text('هل تريد حذف هذه الصورة نهائيًا؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c2, false),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c2, true),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _deletePolicyImage(images[current]);
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
                            child: _previewImageWidget(images[current]),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 30),
                            onPressed: () => Navigator.pop(dlgCtx),
                          ),
                        ),
                        if (images.length > 1)
                          Positioned(
                            left: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_back_ios,
                                  color: Colors.white),
                              onPressed: () => setDlg(() {
                                current = (current - 1 + images.length) %
                                    images.length;
                              }),
                            ),
                          ),
                        if (images.length > 1)
                          Positioned(
                            right: 10,
                            top: 0,
                            bottom: 0,
                            child: IconButton(
                              iconSize: 44,
                              icon: const Icon(Icons.arrow_forward_ios,
                                  color: Colors.white),
                              onPressed: () => setDlg(() {
                                current = (current + 1) % images.length;
                              }),
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

  // =========================
  // UI Helpers
  // =========================
  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AdaptiveRow(
        children: [
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            k,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.5)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: TextStyle(color: fg, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _fileThumb(String path) {
    return FutureBuilder<String?>(
      future: YallaStorageService.resolveExistingPath(path),
      builder: (context, snapshot) {
        final resolved = snapshot.data;
        if (resolved == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                'غير موجود',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }
        return Image.file(File(resolved), fit: BoxFit.cover);
      },
    );
  }

  Widget _expiryCountdownPanel(Map<String, dynamic> r) {
    final start = _parseDate(r['start_date']);
    final end = _parseDate(r['end_date']);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (end == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '⏳ عدّاد انتهاء التأمين',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'لا يوجد تاريخ نهاية للتأمين',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final remainingDays = end.difference(today).inDays;

    Color accent;
    if (remainingDays < 0) {
      accent = Colors.red;
    } else if (remainingDays <= 12) {
      accent = Colors.orange;
    } else {
      accent = AppColors.primary;
    }

    String headline;
    String subline;

    if (remainingDays < 0) {
      headline = 'منتهية';
      subline = 'منذ ${remainingDays.abs()} يوم';
    } else if (remainingDays == 0) {
      headline = 'تنتهي اليوم';
      subline = 'اليوم آخر يوم للتأمين';
    } else {
      headline = 'متبقي';
      subline = '$remainingDays يوم';
    }

    double progress = 0.0;
    if (start != null) {
      final total = end.difference(start).inDays;
      if (total > 0) {
        final used = today.difference(start).inDays;
        progress = (used / total).clamp(0.0, 1.0);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveRow(
              children: [
                Container(
                  width: 10,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '⏳ عدّاد انتهاء التأمين',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              headline,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subline,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 44,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'نهاية التأمين: ${_df.format(end)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (start != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: progress,
                  backgroundColor: Colors.black.withOpacity(0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'التقدم خلال مدة التأمين',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
            if (remainingDays >= 0 && remainingDays <= 12) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.35)),
                ),
                child: Text(
                  'تنبيه: متبقي أقل من 12 يوم — جهّز التجديد/التواصل مع العميل',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _financeCard(Map<String, dynamic> r, List<String> images) {
    final buyPrice = _toDouble(r['buy_price'] ?? r['purchase_price']);
    final sellPrice = _toDouble(r['sell_price'] ?? r['sale_price']);
    final profit = sellPrice - buyPrice;

    final paid = _toDouble(r['paid_amount'] ?? r['paid'] ?? r['amount_paid']);
    final remaining = (sellPrice > 0) ? (sellPrice - paid) : 0.0;

    final status = _statusText(r);
    final statusColor = _statusColor(r);
    final vip = _isVip(r);

    final plate = (r['vehicle_plate'] ?? '').toString().trim();
    final company = (r['company_name'] ?? '').toString().trim();

    // ✅ NEW: document type + vehicle price chips
    final docType = _documentTypeLabel(r);
    final carPriceStr = _vehiclePriceLabel(r);

    final thumbPath = images.isNotEmpty ? images.first : null;

    Widget thumbWidget() {
      if (thumbPath == null || thumbPath.trim().isEmpty) {
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF2F5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.policy, size: 28),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 56,
          height: 56,
          color: const Color(0xFFEFF2F5),
          child: _isNetwork(thumbPath)
              ? Image.network(thumbPath, fit: BoxFit.cover)
              : _fileThumb(thumbPath),
        ),
      );
    }

    return Card(
      child: ListTile(
        leading: thumbWidget(),
        title: const Text('الملخص المالي 💰', textAlign: TextAlign.right),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(height: 6),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(status, statusColor.withOpacity(0.12), statusColor),
                if (vip)
                  _chip('VIP', AppColors.primary.withOpacity(0.12),
                      AppColors.primary),
                if (docType != '—')
                  _chip(
                      docType, Colors.black.withOpacity(0.06), Colors.black87),
                if (carPriceStr != '—')
                  _chip('سعر المركبة: $carPriceStr',
                      Colors.black.withOpacity(0.06), Colors.black87),
                if (plate.isNotEmpty)
                  _chip(plate, Colors.black.withOpacity(0.06), Colors.black87),
                if (company.isNotEmpty)
                  _chip(
                      company, Colors.black.withOpacity(0.06), Colors.black87),
              ],
            ),
            const SizedBox(height: 10),
            _kv('شراء', buyPrice == 0 ? '—' : _currency.format(buyPrice)),
            _kv('بيع', sellPrice == 0 ? '—' : _currency.format(sellPrice)),
            _kv(
                'الربح',
                (sellPrice == 0 && buyPrice == 0)
                    ? '—'
                    : _currency.format(profit)),
            if (sellPrice > 0) ...[
              _kv('المدفوع', _currency.format(paid)),
              _kv('المتبقي', _currency.format(remaining)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(Map<String, dynamic> r) {
    final start = _parseDate(r['start_date']);
    final end = _parseDate(r['end_date']);

    final plate = (r['vehicle_plate'] ?? '—').toString();
    final engineSize =
        (r['engine_size'] ?? r['engine_cc'] ?? '').toString().trim();

    final insured = (r['insured_name'] ?? '—').toString();
    final phone = (r['insured_phone'] ?? '').toString().trim();
    final company = (r['company_name'] ?? '—').toString();

    // ✅ NEW (REAL SOURCE)
    final docType = _documentTypeLabel(r);
    final carPriceStr = _vehiclePriceLabel(r);

    final paymentMethod =
        (r['payment_method'] ?? r['payment_type'] ?? '').toString().trim();
    final notes = (r['notes'] ?? r['policy_notes'] ?? '').toString().trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'بيانات المركبة والمستفيد',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _kv('رقم المركبة', plate),
            _kv('حجم المحرك', engineSize.isEmpty ? '—' : engineSize),
            _kv('سعر المركبة', carPriceStr),
            _kv('نوع الوثيقة', docType),
            const Divider(height: 18),
            _kv('المؤمَّن له', insured),
            _kv('الهاتف', phone.isEmpty ? '—' : phone),
            const Divider(height: 18),
            _kv('الشركة', company),
            _kv('بداية التأمين', start == null ? '—' : _df.format(start)),
            _kv('نهاية التأمين', end == null ? '—' : _df.format(end)),
            _kv('VIP', _isVip(r) ? 'نعم' : 'لا'),
            _kv('الحالة', _statusText(r)),
            const Divider(height: 18),
            _kv('آلية الدفع', paymentMethod.isEmpty ? '—' : paymentMethod),
            const Divider(height: 18),
            const Text(
              'ملاحظات',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              notes.isEmpty ? '—' : notes,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chequesCard() {
    if (_loadingCheques) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: AdaptiveRow(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'جاري تحميل الشيكات...',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_cheques.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AdaptiveRow(
            children: [
              const Text(
                'الشيكات',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'لا توجد شيكات',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      );
    }

    double total = 0;
    for (final c in _cheques) {
      total += _toDouble(c['amount']);
    }

    // widths
    const wAmount = 138.0;
    const wDue = 150.0;
    const wBank = 190.0;
    const wDrawer = 190.0;
    const wNo = 166.0; // ✅ kill the 2px overflow (desktop rounding)

    // ✅ IMPORTANT: this must include row horizontal padding (8 + 8)
    const rowHPad = 8.0;
    final contentW = wAmount + wDue + wBank + wDrawer + wNo;
    final tableW = contentW + (rowHPad * 2) + 6; // ✅ breathing room ضد rounding

    Text cellText(String s, {FontWeight? weight}) {
      return Text(
        s,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: weight),
      );
    }

    Widget headerRow() {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: rowHPad),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: AdaptiveRow(
          children: [
            SizedBox(
                width: wAmount,
                child: cellText('المبلغ', weight: FontWeight.w800)),
            SizedBox(
                width: wDue,
                child: cellText('الاستحقاق', weight: FontWeight.w800)),
            SizedBox(
                width: wBank,
                child: cellText('البنك', weight: FontWeight.w800)),
            SizedBox(
                width: wDrawer,
                child: cellText('الساحب', weight: FontWeight.w800)),
            SizedBox(
                width: wNo,
                child: cellText('رقم الشيك', weight: FontWeight.w800)),
          ],
        ),
      );
    }

    Widget rowItem(Map<String, dynamic> c) {
      final amount = _toDouble(c['amount']);
      final due = _parseDate(c['due_date']);
      final bank = (c['bank_name'] ?? '—').toString();
      final drawer = (c['drawer_name'] ?? '—').toString();
      final number = (c['cheque_number'] ?? '—').toString();

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: rowHPad),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: AdaptiveRow(
          children: [
            SizedBox(
                width: wAmount,
                child: cellText(_currency.format(amount),
                    weight: FontWeight.w800)),
            SizedBox(
                width: wDue,
                child: cellText(due == null ? '—' : _df.format(due))),
            SizedBox(width: wBank, child: cellText(bank)),
            SizedBox(width: wDrawer, child: cellText(drawer)),
            SizedBox(width: wNo, child: cellText(number)),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'الشيكات',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // ✅ centered + no overflow + horizontal scroll if needed
            LayoutBuilder(
              builder: (ctx, cons) {
                return ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(overscroll: false),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: cons.maxWidth),
                      child: Center(
                        child: SizedBox(
                          width: tableW,
                          child: Column(
                            children: [
                              headerRow(),
                              const SizedBox(height: 8),
                              ..._cheques.map(rowItem),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const Divider(height: 18),
            Text(
              'مجموع الشيكات: ${_currency.format(total)}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsBar(Map<String, dynamic> r) {
    final end = _parseDate(r['end_date']);
    final remainingDays = (end == null)
        ? null
        : end
            .difference(DateTime(
                DateTime.now().year, DateTime.now().month, DateTime.now().day))
            .inDays;

    String expiryHint() {
      if (remainingDays == null) return '—';
      if (remainingDays < 0) return 'منتهية منذ ${remainingDays.abs()} يوم';
      if (remainingDays == 0) return 'تنتهي اليوم';
      return 'متبقي $remainingDays يوم';
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'الانتهاء: ${expiryHint()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
              onPressed: (_loading || widget.policyId == null)
                  ? null
                  : () async {
                      await _loadFromDb(widget.policyId);
                      final pid = _effectivePolicyId();
                      if (pid != null) await _loadCheques(pid);
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ✅ هنا الإصلاح الحقيقي: SizedBox.expand + SingleChildScrollView مع controller
  Widget _buildBody(bool desktop, double contentWidth) {
    final r = _row;
    if (r == null) {
      return const Center(child: Text('لا توجد بيانات لعرضها'));
    }

    final images = _extractImages(r);

    return SafeArea(
      child: SizedBox.expand(
        child: Container(
          color: const Color(0xFFF7F8FA),
          child: Align(
            alignment: Alignment.topRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    desktop ? contentWidth.clamp(900, 1600) : contentWidth,
              ),
              child: ScrollConfiguration(
                behavior: const ScrollBehavior().copyWith(overscroll: false),
                child: Scrollbar(
                  controller: _scrollCtrl,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    child: LayoutBuilder(
                      builder: (_, inner) {
                        final isWide = inner.maxWidth >= 1000;

                        if (isWide) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AdaptiveRow(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _financeCard(r, images),
                                        const SizedBox(height: 12),
                                        _expiryCountdownPanel(r),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(flex: 4, child: _detailsCard(r)),
                                ],
                              ),
                              _actionsBar(r),
                              const SizedBox(height: 16),
                              _chequesCard(),
                              const SizedBox(height: 16),
                              _vehicleImagesPanel(r),
                              const SizedBox(height: 24),
                            ],
                          );
                        }

                        // Mobile/Tablet
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _financeCard(r, images),
                            const SizedBox(height: 12),
                            _expiryCountdownPanel(r),
                            const SizedBox(height: 12),
                            _detailsCard(r),
                            _actionsBar(r),
                            const SizedBox(height: 12),
                            _chequesCard(),
                            const SizedBox(height: 12),
                            _vehicleImagesPanel(r),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth;
        final desktopFixed = w >= 1200;
        final sideW = 320.0;
        final contentW = desktopFixed ? (w - sideW) : w;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            title: const Text(
              'تفاصيل البوليصة',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: (_loading || widget.policyId == null)
                    ? null
                    : () async {
                        await _loadFromDb(widget.policyId);
                        final pid = _effectivePolicyId();
                        if (pid != null) await _loadCheques(pid);
                      },
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),
              if (!desktopFixed)
                IconButton(
                  tooltip: 'القائمة',
                  onPressed: () => _toggleSide(!_sideOpen),
                  icon: const Icon(Icons.menu, color: Colors.white),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : (desktopFixed
                  ? Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 320),
                          child: _buildBody(true, contentW),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _rightSidebar(width: sideW),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        _buildBody(false, contentW),
                        _rightOverlaySidebar(width: sideW),
                      ],
                    )),
        );
      },
    );
  }

  // =========================
  // Vehicle Images Panel (FIXED)
  // =========================

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openInExplorer(String path) async {
    try {
      if (path.trim().isEmpty) return;
      // Windows: open file location

      await Process.run('explorer', ['/select,', path]);
    } catch (e) {
      _toast('تعذر فتح الملف: $e');
    }
  }

  Future<void> _savePolicyImagesToDb(List<String> images) async {
    final r = _row;
    if (r == null) return;

    final idValue = _effectivePolicyId();
    if (idValue == null) return;

    final col = await _findExistingColumn(
      table: 'insurance_policies',
      candidates: ['vehicle_images', 'images', 'car_images'],
    );

    if (col == null) {
      _toast('⚠️ لم يتم العثور على عمود الصور في insurance_policies');
      return;
    }

    final db = await DatabaseMigration.database;

    // تحديث باستخدام نفس القيمة لكل أعمدة id المحتملة (متحمل)
    await db.update(
      'insurance_policies',
      {col: jsonEncode(images)},
      where: 'id = ?',
      whereArgs: [idValue],
    );

    // حدّث الـ UI
    setState(() {
      _row = {...r, col: jsonEncode(images)};
    });
  }

  Future<void> _pickImages() async {
    final r = _row;
    if (r == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    try {
      _toast('⏳ جاري معالجة الصور...');

      final current = _extractImages(r);

      final plate = (r['vehicle_plate'] ?? '').toString();
      final company = (r['company_name'] ?? '').toString();
      final insured = (r['insured_name'] ?? '').toString();
      final end = _parseDate(r['end_date']) ?? DateTime.now();

      for (final raw in picked) {
        final compressed =
            await ImageStorageService.compressImage(XFile(raw.path));

        final savedPath = await ImageStorageService.saveImage(
          image: compressed,
          module: 'insurance', // ✅ هذا هو الفصل الحقيقي
          vehicleType: company.isNotEmpty ? company : 'POLICY',
          vehicleNumber: plate.isNotEmpty ? plate : 'NO-PLATE',
          beneficiaryName: insured.isNotEmpty ? insured : 'INSURED',
          receivedDate: end,
        );

        current.add(savedPath);
      }

      await _savePolicyImagesToDb(current);
      _toast('✅ تم حفظ الصور');
    } catch (e) {
      _toast('❌ فشل إضافة الصور: $e');
    }
  }

  Future<void> _deletePolicyImage(String path) async {
    final r = _row;
    if (r == null) return;

    try {
      final current = _extractImages(r);

      // 1) حذف من القرص
      if (!_isNetwork(path)) {
        await ImageStorageService.deleteImage(path);
      }

      // 2) حذف من القائمة وتحديث DB
      current.removeWhere((p) => p == path);
      await _savePolicyImagesToDb(current);

      _toast('🗑️ تم حذف الصورة');
    } catch (e) {
      _toast('❌ فشل حذف الصورة: $e');
    }
  }

  Widget _vehicleImagesPanel(Map<String, dynamic> r) {
    final images = _extractImages(r);

    Widget actionBtn({
      required String label,
      required IconData icon,
      required VoidCallback? onTap,
    }) {
      final enabled = onTap != null;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.white : Colors.black.withOpacity(0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.black.withOpacity(enabled ? 0.10 : 0.06),
            ),
          ),
          child: AdaptiveRow(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? AppColors.primary : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: enabled ? Colors.black87 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final canPreview = images.isNotEmpty;
    final firstPath = canPreview ? images.first : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✅ Header ثابت + شريط أزرار قابل للسكرول (بدون ما يختفي زر)
            AdaptiveRow(
              children: [
                const Expanded(
                  child: Text(
                    '📷 صور المركبة',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),

                IconButton(
                  tooltip: 'إضافة صور',
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_a_photo),
                ),

                const SizedBox(width: 8),

                // ✅ هنا أصل المشكلة: لازم Expanded (tight) مش Flexible (loose)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true, // عشان الأزرار تبان من اليمين أولاً
                    child: AdaptiveRow(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        actionBtn(
                          label: 'معاينة',
                          icon: Icons.visibility,
                          onTap:
                              canPreview ? () => _openPreview(images, 0) : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'نسخ المسار',
                          icon: Icons.copy,
                          onTap: canPreview
                              ? () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: firstPath),
                                  );
                                  _toast('تم نسخ المسار');
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'فتح بالمجلد',
                          icon: Icons.folder_open,
                          onTap: canPreview
                              ? () => _openInExplorer(firstPath)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'تعديل',
                          icon: Icons.edit,
                          onTap: canPreview
                              ? () =>
                                  _toast('زر التعديل جاهز—اربطه لاحقًا بما بدك')
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (images.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'لا توجد صور',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              SizedBox(
                height: 130,
                child: ScrollConfiguration(
                  behavior: const ScrollBehavior().copyWith(overscroll: false),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, idx) {
                        final path = images[idx];

                        return GestureDetector(
                          onTap: () => _openPreview(images, idx),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  color: const Color(0xFFF2F3F5),
                                  child: _isNetwork(path)
                                      ? Image.network(
                                          path,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(
                                            child: Text(
                                              'صورة غير صالحة',
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        )
                                      : _fileThumb(path),
                                ),
                              ),

                              // زر حذف
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c2) => AdaptiveAlertDialog(
                                        title: const Text('حذف الصورة'),
                                        content:
                                            const Text('تأكيد حذف هذه الصورة؟'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c2, false),
                                            child: const Text('إلغاء'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(c2, true),
                                            child: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await _deletePolicyImage(path);
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
