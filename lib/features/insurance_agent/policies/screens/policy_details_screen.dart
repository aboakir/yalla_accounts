// ًں“پ lib/features/insurance_agent/policies/screens/policy_details_screen.dart
//
// PolicyDetailsScreen â€” FIXED SCROLL + NO OVERFLOW
// âœ… Scroll ظٹط¹ظ…ظ„ (ظپظˆظ‚/طھط­طھ) Desktop + Mobile
// âœ… ظ„ط§ Overflow ظپظٹ ط§ظ„ط´ظٹظƒط§طھ (ط¹ط±ط¶ ط£ظپظ‚ظٹ ط¹ظ†ط¯ ط§ظ„ط­ط§ط¬ط©)
// âœ… Sidebar Desktop ط«ط§ط¨طھ + Mobile Overlay
// âœ… ط¨ط¯ظˆظ† RTL / Directionality (ظ…ط­ط§ط°ط§ط© ظٹظ…ظٹظ† ظپظ‚ط·)
//
// âœ… UPDATED:
// - ط¹ط±ط¶ "ظ†ظˆط¹ ط§ظ„ظˆط«ظٹظ‚ط©" + "ط³ط¹ط± ط§ظ„ظ…ط±ظƒط¨ط©" ظ…ظ† ظ…طµط¯ط±ظ‡ط§ ط§ظ„ط­ظ‚ظٹظ‚ظٹ (ط§ظ„ظ€ DB row)
// - Resolve ط°ظƒظٹ ظ„ط£ط³ظ…ط§ط، ط§ظ„ط£ط¹ظ…ط¯ط© ط§ظ„ظ…ط­طھظ…ظ„ط© (document_type / car_price ...)
// - ط¹ط±ط¶ظ‡ظ… ط¯ط§ط®ظ„ ط¨ط·ط§ظ‚ط© ط§ظ„طھظپط§طµظٹظ„ + (Chip) ط§ط®طھظٹط§ط±ظٹ ظپظٹ ط§ظ„ظ…ظ„ط®طµ ط§ظ„ظ…ط§ظ„ظٹ

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:image_picker/image_picker.dart';
import 'package:yalla_accounts/core/services/image_storage_service.dart';

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

  // âœ… Scroll controller (ظ…ظ‡ظ… ط¬ط¯ظ‹ط§ ط¹ط´ط§ظ† ط§ظ„ط³ط­ط¨ ظٹط´طھط؛ظ„)
  final ScrollController _scrollCtrl = ScrollController();

  // âœ… Cheques
  List<Map<String, dynamic>> _cheques = [];
  bool _loadingCheques = false;

  static const List<String> _collectionOptions = [
    'ط؛ظٹط± ظ…ط¯ظپظˆط¹',
    'ظ…ط¯ظپظˆط¹ ط¬ط²ط¦ظٹ',
    'ظ…ط¯ظپظˆط¹',
    'ط£ظ‚ط³ط§ط·',
  ];

  static const List<String> _officeFollowupOptions = [
    'ط¬ط¯ظٹط¯',
    'طھظ… ط¥طµط¯ط§ط± ط§ظ„ط¨ظˆظ„ظٹطµط©',
    'طھظ… طھط³ظ„ظٹظ… ط§ظ„ط¨ظˆظ„ظٹطµط©',
    'طھظ… ط§ظ„طھط­طµظٹظ„ ظ…ظ† ط§ظ„ط¹ظ…ظٹظ„',
    'ظ…ط¹ظ„ظ‘ظ‚/ظ‚ظٹط¯ ط§ظ„ظ…طھط§ط¨ط¹ط©',
  ];

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
          const SnackBar(content: Text('âڑ ï¸ڈ ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط§ظ„ط¨ظˆظ„ظٹطµط©')),
        );
        return;
      }

      final pid = found['id'] ?? found['policy_id'] ?? found['uuid'];
      if (pid != null) await _loadCheques(pid);

      // ط±ط¬ظ‘ط¹ ط§ظ„ط³ظƒط±ظˆظ„ ظ„ط£ط¹ظ„ظ‰ ط¨ط¹ط¯ ط§ظ„طھط­ط¯ظٹط« (ط§ط®طھظٹط§ط±ظٹ)
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(0);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„طھظپط§طµظٹظ„: $e')),
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
        SnackBar(content: Text('â‌Œ ظپط´ظ„ طھط­ظ…ظٹظ„ ط§ظ„ط´ظٹظƒط§طھ: $e')),
      );
    }
  }

  // ===========================================================================
  // âœ… Real-source resolving helpers
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
      {String fallback = 'â€”'}) {
    final v = _resolveFirstValue(r, keys);
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  double _resolveFirstDouble(Map<String, dynamic> r, List<String> keys) {
    final v = _resolveFirstValue(r, keys);
    return _toDouble(v);
  }

  // âœ… "ظ†ظˆط¹ ط§ظ„ظˆط«ظٹظ‚ط©" (ط·ط±ظپ ط«ط§ظ„ط« / ط´ط§ظ…ظ„)
  String _documentTypeLabel(Map<String, dynamic> r) {
    // ط­ط§ظˆظ„ ظ…ظپط§طھظٹط­ ظ…ط­طھظ…ظ„ط©
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

    if (raw.isEmpty) return 'â€”';

    // طھط·ط¨ظٹط¹ ط¨ط³ظٹط· ظ„ظˆ ظƒط§ظ†طھ ط§ظ„ظ‚ظٹظ…ط© ظ…ط­ظپظˆط¸ط© ط¨ط·ط±ظ‚ ظ…ط®طھظ„ظپط©
    final s = raw.toLowerCase();
    if (s.contains('third') || s.contains('tp') || s.contains('ط·ط±ظپ')) {
      return 'ط·ط±ظپ ط«ط§ظ„ط«';
    }
    if (s.contains('compre') || s.contains('full') || s.contains('ط´ط§ظ…ظ„')) {
      return 'ط´ط§ظ…ظ„';
    }
    return raw; // ط¥ط°ط§ ظƒط§ظ†طھ ظ…ظƒطھظˆط¨ط© ط¬ط§ظ‡ط²ط© ط¨ط§ظ„ط¹ط±ط¨ظٹ (ط·ط±ظپ ط«ط§ظ„ط«/ط´ط§ظ…ظ„) ط£ظˆ ط£ظٹ ظ†طµ ط¢ط®ط±
  }

  // âœ… "ط³ط¹ط± ط§ظ„ظ…ط±ظƒط¨ط©"
  double _vehiclePriceValue(Map<String, dynamic> r) {
    // ط£ظ‡ظ… ظ…ظپط§طھظٹط­ ظ…طھظˆظ‚ط¹ط© ظ„ط³ط¹ط± ط§ظ„ظ…ط±ظƒط¨ط©
    return _resolveFirstDouble(
      r,
      [
        'car_price',
        'vehicle_price',
        'car_value',
        'vehicle_value',
        'market_value',
        'sum_insured', // ط£ط­ظٹط§ظ†ظ‹ط§ ظ‚ظٹظ…ط© ط§ظ„طھط£ظ…ظٹظ† = ظ‚ظٹظ…ط© ط§ظ„ظ…ط±ظƒط¨ط©
        'insured_value',
        'vehicle_sum_insured',
      ],
    );
  }

  String _vehiclePriceLabel(Map<String, dynamic> r) {
    final v = _vehiclePriceValue(r);
    if (v <= 0) return 'â€”';
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
    if (_isExpired(r)) return 'ظ…ظ†طھظ‡ظٹط©';
    if (_isExpiringSoon(r)) return 'طھظ†طھظ‡ظٹ ظ‚ط±ظٹط¨ظ‹ط§';
    return 'ط³ط§ط±ظٹط©';
  }

  Color _statusColor(Map<String, dynamic> r) {
    if (_isExpired(r)) return Colors.red;
    if (_isExpiringSoon(r)) return Colors.orange;
    return Colors.green;
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

  Future<void> _updatePolicyColumnSmart({
    required List<String> idCandidates,
    required dynamic idValue,
    required List<String> candidates,
    required dynamic value,
    required String successMsg,
  }) async {
    try {
      final db = await DatabaseMigration.database;

      final col = await _findExistingColumn(
        table: 'insurance_policies',
        candidates: candidates,
      );
      if (col == null) {
        throw 'ظ„ظ… ظٹظڈط¹ط«ط± ط¹ظ„ظ‰ ط¹ظ…ظˆط¯ ظ…ظ†ط§ط³ط¨: ${candidates.join(", ")}';
      }

      String? idCol;
      for (final c in idCandidates) {
        final ok = await _findExistingColumn(
          table: 'insurance_policies',
          candidates: [c],
        );
        if (ok != null) {
          idCol = ok;
          break;
        }
      }
      if (idCol == null) {
        throw 'ظ„ظ… ظٹظڈط¹ط«ط± ط¹ظ„ظ‰ ط¹ظ…ظˆط¯ طھط¹ط±ظٹظپ ظ„ظ„ط¨ظˆظ„ظٹطµط© (id/policy_id/uuid)';
      }

      await db.update(
        'insurance_policies',
        {col: value},
        where: '$idCol = ?',
        whereArgs: [idValue],
      );

      if (widget.policyId != null) {
        await _loadFromDb(widget.policyId);
      } else {
        setState(() {
          _row = {...?_row, col: value};
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMsg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('â‌Œ ظپط´ظ„ ط§ظ„طھط­ط¯ظٹط«: $e')));
    }
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
            const Center(child: Text('طµظˆط±ط© ط؛ظٹط± طµط§ظ„ط­ط©')),
      );
    }
    final f = File(path);
    if (!f.existsSync()) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'ظ…ظ„ظپ ط؛ظٹط± ظ…ظˆط¬ظˆط¯\n$path',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: Colors.grey.shade700, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Image.file(f, fit: BoxFit.contain);
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
                        title: const Text('ط­ط°ظپ ط§ظ„طµظˆط±ط©'),
                        content: const Text('ظ‡ظ„ طھط±ظٹط¯ ط­ط°ظپ ظ‡ط°ظ‡ ط§ظ„طµظˆط±ط© ظ†ظ‡ط§ط¦ظٹظ‹ط§طں'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c2, false),
                            child: const Text('ط¥ظ„ط؛ط§ط،'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(c2, true),
                            child: const Text('ط­ط°ظپ'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await _deletePolicyImage(images[current]);
                      Navigator.pop(dlgCtx);
                    }
                    return null;
                  },
                ),
              },
              child: StatefulBuilder(
                builder: (ctx, setDlg) { final viewport = MediaQuery.sizeOf(ctx); final phone = viewport.width < 600; return SizedBox(width: phone ? viewport.width - 24 : 900, height: phone ? (viewport.height * 0.72).clamp(320.0, 720.0).toDouble() : 720,
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
    final f = File(path);
    if (!f.existsSync()) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'ط؛ظٹط± ظ…ظˆط¬ظˆط¯',
            textAlign: TextAlign.right,
            style: TextStyle(
                color: Colors.grey.shade700, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }
    return Image.file(f, fit: BoxFit.cover);
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
                'âڈ³ ط¹ط¯ظ‘ط§ط¯ ط§ظ†طھظ‡ط§ط، ط§ظ„طھط£ظ…ظٹظ†',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'ظ„ط§ ظٹظˆط¬ط¯ طھط§ط±ظٹط® ظ†ظ‡ط§ظٹط© ظ„ظ„طھط£ظ…ظٹظ†',
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
      accent = Colors.green;
    }

    String headline;
    String subline;

    if (remainingDays < 0) {
      headline = 'ظ…ظ†طھظ‡ظٹط©';
      subline = 'ظ…ظ†ط° ${remainingDays.abs()} ظٹظˆظ…';
    } else if (remainingDays == 0) {
      headline = 'طھظ†طھظ‡ظٹ ط§ظ„ظٹظˆظ…';
      subline = 'ط§ظ„ظٹظˆظ… ط¢ط®ط± ظٹظˆظ… ظ„ظ„طھط£ظ…ظٹظ†';
    } else {
      headline = 'ظ…طھط¨ظ‚ظٹ';
      subline = '$remainingDays ظٹظˆظ…';
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
                    'âڈ³ ط¹ط¯ظ‘ط§ط¯ ط§ظ†طھظ‡ط§ط، ط§ظ„طھط£ظ…ظٹظ†',
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
              'ظ†ظ‡ط§ظٹط© ط§ظ„طھط£ظ…ظٹظ†: ${_df.format(end)}',
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
                'ط§ظ„طھظ‚ط¯ظ… ط®ظ„ط§ظ„ ظ…ط¯ط© ط§ظ„طھط£ظ…ظٹظ†',
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
                  'طھظ†ط¨ظٹظ‡: ظ…طھط¨ظ‚ظٹ ط£ظ‚ظ„ ظ…ظ† 12 ظٹظˆظ… â€” ط¬ظ‡ظ‘ط² ط§ظ„طھط¬ط¯ظٹط¯/ط§ظ„طھظˆط§طµظ„ ظ…ط¹ ط§ظ„ط¹ظ…ظٹظ„',
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

    // âœ… NEW: document type + vehicle price chips
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
        title: const Text('ط§ظ„ظ…ظ„ط®طµ ط§ظ„ظ…ط§ظ„ظٹ ًں’°', textAlign: TextAlign.right),
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
                if (docType != 'â€”')
                  _chip(
                      docType, Colors.black.withOpacity(0.06), Colors.black87),
                if (carPriceStr != 'â€”')
                  _chip('ط³ط¹ط± ط§ظ„ظ…ط±ظƒط¨ط©: $carPriceStr',
                      Colors.black.withOpacity(0.06), Colors.black87),
                if (plate.isNotEmpty)
                  _chip(plate, Colors.black.withOpacity(0.06), Colors.black87),
                if (company.isNotEmpty)
                  _chip(
                      company, Colors.black.withOpacity(0.06), Colors.black87),
              ],
            ),
            const SizedBox(height: 10),
            _kv('ط´ط±ط§ط،', buyPrice == 0 ? 'â€”' : _currency.format(buyPrice)),
            _kv('ط¨ظٹط¹', sellPrice == 0 ? 'â€”' : _currency.format(sellPrice)),
            _kv(
                'ط§ظ„ط±ط¨ط­',
                (sellPrice == 0 && buyPrice == 0)
                    ? 'â€”'
                    : _currency.format(profit)),
            if (sellPrice > 0) ...[
              _kv('ط§ظ„ظ…ط¯ظپظˆط¹', _currency.format(paid)),
              _kv('ط§ظ„ظ…طھط¨ظ‚ظٹ', _currency.format(remaining)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(Map<String, dynamic> r) {
    final start = _parseDate(r['start_date']);
    final end = _parseDate(r['end_date']);

    final plate = (r['vehicle_plate'] ?? 'â€”').toString();
    final engineSize =
        (r['engine_size'] ?? r['engine_cc'] ?? '').toString().trim();

    final insured = (r['insured_name'] ?? 'â€”').toString();
    final phone = (r['insured_phone'] ?? '').toString().trim();
    final company = (r['company_name'] ?? 'â€”').toString();

    // âœ… NEW (REAL SOURCE)
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
              'ط¨ظٹط§ظ†ط§طھ ط§ظ„ظ…ط±ظƒط¨ط© ظˆط§ظ„ظ…ط³طھظپظٹط¯',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _kv('ط±ظ‚ظ… ط§ظ„ظ…ط±ظƒط¨ط©', plate),
            _kv('ط­ط¬ظ… ط§ظ„ظ…ط­ط±ظƒ', engineSize.isEmpty ? 'â€”' : engineSize),
            _kv('ط³ط¹ط± ط§ظ„ظ…ط±ظƒط¨ط©', carPriceStr),
            _kv('ظ†ظˆط¹ ط§ظ„ظˆط«ظٹظ‚ط©', docType),
            const Divider(height: 18),
            _kv('ط§ظ„ظ…ط¤ظ…ظ‘ظژظ† ظ„ظ‡', insured),
            _kv('ط§ظ„ظ‡ط§طھظپ', phone.isEmpty ? 'â€”' : phone),
            const Divider(height: 18),
            _kv('ط§ظ„ط´ط±ظƒط©', company),
            _kv('ط¨ط¯ط§ظٹط© ط§ظ„طھط£ظ…ظٹظ†', start == null ? 'â€”' : _df.format(start)),
            _kv('ظ†ظ‡ط§ظٹط© ط§ظ„طھط£ظ…ظٹظ†', end == null ? 'â€”' : _df.format(end)),
            _kv('VIP', _isVip(r) ? 'ظ†ط¹ظ…' : 'ظ„ط§'),
            _kv('ط§ظ„ط­ط§ظ„ط©', _statusText(r)),
            const Divider(height: 18),
            _kv('ط¢ظ„ظٹط© ط§ظ„ط¯ظپط¹', paymentMethod.isEmpty ? 'â€”' : paymentMethod),
            const Divider(height: 18),
            const Text(
              'ظ…ظ„ط§ط­ط¸ط§طھ',
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              notes.isEmpty ? 'â€”' : notes,
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
                  'ط¬ط§ط±ظٹ طھط­ظ…ظٹظ„ ط§ظ„ط´ظٹظƒط§طھ...',
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
                'ط§ظ„ط´ظٹظƒط§طھ',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                'ظ„ط§ طھظˆط¬ط¯ ط´ظٹظƒط§طھ',
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
    const wNo = 166.0; // âœ… kill the 2px overflow (desktop rounding)

    // âœ… IMPORTANT: this must include row horizontal padding (8 + 8)
    const rowHPad = 8.0;
    final contentW = wAmount + wDue + wBank + wDrawer + wNo;
    final tableW = contentW + (rowHPad * 2) + 6; // âœ… breathing room ط¶ط¯ rounding

    Text _cellText(String s, {FontWeight? weight}) {
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
                child: _cellText('ط§ظ„ظ…ط¨ظ„ط؛', weight: FontWeight.w800)),
            SizedBox(
                width: wDue,
                child: _cellText('ط§ظ„ط§ط³طھط­ظ‚ط§ظ‚', weight: FontWeight.w800)),
            SizedBox(
                width: wBank,
                child: _cellText('ط§ظ„ط¨ظ†ظƒ', weight: FontWeight.w800)),
            SizedBox(
                width: wDrawer,
                child: _cellText('ط§ظ„ط³ط§ط­ط¨', weight: FontWeight.w800)),
            SizedBox(
                width: wNo,
                child: _cellText('ط±ظ‚ظ… ط§ظ„ط´ظٹظƒ', weight: FontWeight.w800)),
          ],
        ),
      );
    }

    Widget rowItem(Map<String, dynamic> c) {
      final amount = _toDouble(c['amount']);
      final due = _parseDate(c['due_date']);
      final bank = (c['bank_name'] ?? 'â€”').toString();
      final drawer = (c['drawer_name'] ?? 'â€”').toString();
      final number = (c['cheque_number'] ?? 'â€”').toString();

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
                child: _cellText(_currency.format(amount),
                    weight: FontWeight.w800)),
            SizedBox(
                width: wDue,
                child: _cellText(due == null ? 'â€”' : _df.format(due))),
            SizedBox(width: wBank, child: _cellText(bank)),
            SizedBox(width: wDrawer, child: _cellText(drawer)),
            SizedBox(width: wNo, child: _cellText(number)),
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
              'ط§ظ„ط´ظٹظƒط§طھ',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // âœ… centered + no overflow + horizontal scroll if needed
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
              'ظ…ط¬ظ…ظˆط¹ ط§ظ„ط´ظٹظƒط§طھ: ${_currency.format(total)}',
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
      if (remainingDays == null) return 'â€”';
      if (remainingDays < 0) return 'ظ…ظ†طھظ‡ظٹط© ظ…ظ†ط° ${remainingDays.abs()} ظٹظˆظ…';
      if (remainingDays == 0) return 'طھظ†طھظ‡ظٹ ط§ظ„ظٹظˆظ…';
      return 'ظ…طھط¨ظ‚ظٹ $remainingDays ظٹظˆظ…';
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: AdaptiveRow(
          children: [
            Expanded(
              child: Text(
                'ط§ظ„ط§ظ†طھظ‡ط§ط،: ${expiryHint()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('طھط­ط¯ظٹط«'),
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

  // âœ… ظ‡ظ†ط§ ط§ظ„ط¥طµظ„ط§ط­ ط§ظ„ط­ظ‚ظٹظ‚ظٹ: SizedBox.expand + SingleChildScrollView ظ…ط¹ controller
  Widget _buildBody(bool desktop, double contentWidth) {
    final r = _row;
    if (r == null) {
      return const Center(child: Text('ظ„ط§ طھظˆط¬ط¯ ط¨ظٹط§ظ†ط§طھ ظ„ط¹ط±ط¶ظ‡ط§'));
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
              'طھظپط§طµظٹظ„ ط§ظ„ط¨ظˆظ„ظٹطµط©',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              IconButton(
                tooltip: 'طھط­ط¯ظٹط«',
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
                  tooltip: 'ط§ظ„ظ‚ط§ط¦ظ…ط©',
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
      _toast('طھط¹ط°ط± ظپطھط­ ط§ظ„ظ…ظ„ظپ: $e');
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
      _toast('âڑ ï¸ڈ ظ„ظ… ظٹطھظ… ط§ظ„ط¹ط«ظˆط± ط¹ظ„ظ‰ ط¹ظ…ظˆط¯ ط§ظ„طµظˆط± ظپظٹ insurance_policies');
      return;
    }

    final db = await DatabaseMigration.database;

    // طھط­ط¯ظٹط« ط¨ط§ط³طھط®ط¯ط§ظ… ظ†ظپط³ ط§ظ„ظ‚ظٹظ…ط© ظ„ظƒظ„ ط£ط¹ظ…ط¯ط© id ط§ظ„ظ…ط­طھظ…ظ„ط© (ظ…طھط­ظ…ظ„)
    await db.update(
      'insurance_policies',
      {col: jsonEncode(images)},
      where: 'id = ?',
      whereArgs: [idValue],
    );

    // ط­ط¯ظ‘ط« ط§ظ„ظ€ UI
    setState(() {
      _row = {...?r, col: jsonEncode(images)};
    });
  }

  Future<void> _pickImages() async {
    final r = _row;
    if (r == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    try {
      _toast('âڈ³ ط¬ط§ط±ظٹ ظ…ط¹ط§ظ„ط¬ط© ط§ظ„طµظˆط±...');

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
          module: 'insurance', // âœ… ظ‡ط°ط§ ظ‡ظˆ ط§ظ„ظپطµظ„ ط§ظ„ط­ظ‚ظٹظ‚ظٹ
          vehicleType: company.isNotEmpty ? company : 'POLICY',
          vehicleNumber: plate.isNotEmpty ? plate : 'NO-PLATE',
          beneficiaryName: insured.isNotEmpty ? insured : 'INSURED',
          receivedDate: end,
        );

        current.add(savedPath);
      }

      await _savePolicyImagesToDb(current);
      _toast('âœ… طھظ… ط­ظپط¸ ط§ظ„طµظˆط±');
    } catch (e) {
      _toast('â‌Œ ظپط´ظ„ ط¥ط¶ط§ظپط© ط§ظ„طµظˆط±: $e');
    }
  }

  Future<void> _deletePolicyImage(String path) async {
    final r = _row;
    if (r == null) return;

    try {
      final current = _extractImages(r);

      // 1) ط­ط°ظپ ظ…ظ† ط§ظ„ظ‚ط±طµ
      if (!_isNetwork(path)) {
        await ImageStorageService.deleteImage(path);
      }

      // 2) ط­ط°ظپ ظ…ظ† ط§ظ„ظ‚ط§ط¦ظ…ط© ظˆطھط­ط¯ظٹط« DB
      current.removeWhere((p) => p == path);
      await _savePolicyImagesToDb(current);

      _toast('ًں—‘ï¸ڈ طھظ… ط­ط°ظپ ط§ظ„طµظˆط±ط©');
    } catch (e) {
      _toast('â‌Œ ظپط´ظ„ ط­ط°ظپ ط§ظ„طµظˆط±ط©: $e');
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
            // âœ… Header ط«ط§ط¨طھ + ط´ط±ظٹط· ط£ط²ط±ط§ط± ظ‚ط§ط¨ظ„ ظ„ظ„ط³ظƒط±ظˆظ„ (ط¨ط¯ظˆظ† ظ…ط§ ظٹط®طھظپظٹ ط²ط±)
            AdaptiveRow(
              children: [
                const Expanded(
                  child: Text(
                    'ًں“· طµظˆط± ط§ظ„ظ…ط±ظƒط¨ط©',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),

                IconButton(
                  tooltip: 'ط¥ط¶ط§ظپط© طµظˆط±',
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_a_photo),
                ),

                const SizedBox(width: 8),

                // âœ… ظ‡ظ†ط§ ط£طµظ„ ط§ظ„ظ…ط´ظƒظ„ط©: ظ„ط§ط²ظ… Expanded (tight) ظ…ط´ Flexible (loose)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true, // ط¹ط´ط§ظ† ط§ظ„ط£ط²ط±ط§ط± طھط¨ط§ظ† ظ…ظ† ط§ظ„ظٹظ…ظٹظ† ط£ظˆظ„ط§ظ‹
                    child: AdaptiveRow(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        actionBtn(
                          label: 'ظ…ط¹ط§ظٹظ†ط©',
                          icon: Icons.visibility,
                          onTap:
                              canPreview ? () => _openPreview(images, 0) : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'ظ†ط³ط® ط§ظ„ظ…ط³ط§ط±',
                          icon: Icons.copy,
                          onTap: canPreview
                              ? () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: firstPath),
                                  );
                                  _toast('طھظ… ظ†ط³ط® ط§ظ„ظ…ط³ط§ط±');
                                }
                              : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'ظپطھط­ ط¨ط§ظ„ظ…ط¬ظ„ط¯',
                          icon: Icons.folder_open,
                          onTap: canPreview
                              ? () => _openInExplorer(firstPath)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        actionBtn(
                          label: 'طھط¹ط¯ظٹظ„',
                          icon: Icons.edit,
                          onTap: canPreview
                              ? () =>
                                  _toast('ط²ط± ط§ظ„طھط¹ط¯ظٹظ„ ط¬ط§ظ‡ط²â€”ط§ط±ط¨ط·ظ‡ ظ„ط§ط­ظ‚ظ‹ط§ ط¨ظ…ط§ ط¨ط¯ظƒ')
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
                  'ظ„ط§ طھظˆط¬ط¯ طµظˆط±',
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
                                              'طµظˆط±ط© ط؛ظٹط± طµط§ظ„ط­ط©',
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

                              // ط²ط± ط­ط°ظپ
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c2) => AdaptiveAlertDialog(
                                        title: const Text('ط­ط°ظپ ط§ظ„طµظˆط±ط©'),
                                        content:
                                            const Text('طھط£ظƒظٹط¯ ط­ط°ظپ ظ‡ط°ظ‡ ط§ظ„طµظˆط±ط©طں'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(c2, false),
                                            child: const Text('ط¥ظ„ط؛ط§ط،'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () =>
                                                Navigator.pop(c2, true),
                                            child: const Text('ط­ط°ظپ'),
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
// ًں”‘ Intents (Top-Level)
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

