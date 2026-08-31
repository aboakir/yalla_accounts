// 📁 lib/features/insurance_agent/policies/screens/policies_list_screen.dart
//
// PoliciesListScreen — UPDATED (Hamburger Sidebar Overlay for ALL screens)
// ✅ Sidebar صار Overlay (هامبرجر) على الديسكتوب والموبايل
// ✅ المحتوى (الجدول) Full Width دائماً
// ✅ زر الرجوع موجود (يرجع إذا فيه صفحة قبلها)
// ✅ باقي الميزات بدون تغيير (Lazy load + Filters + PDF + Actions)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/services/db/database_migration.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';

import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/screens/add_policy_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/policy_details_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/edit_policy_screen.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/screens/policy_payments_screen.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/widgets/policies_list_header.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/policies_desktop_table.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/widgets/policies_mobile_cards.dart';

import 'package:yalla_accounts/features/insurance_agent/policies/utils/policy_filters.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

class PoliciesListScreen extends StatefulWidget {
  const PoliciesListScreen({super.key});

  @override
  State<PoliciesListScreen> createState() => _PoliciesListScreenState();
}

class _PoliciesListScreenState extends State<PoliciesListScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;

  // ✅ Sidebar overlay state
  bool _sideOpen = false;

  // PDF busy
  bool _pdfBusy = false;

  // Filters
  String _query = '';
  String? _companyFilter;
  bool _vipOnly = false;
  bool _expiredOnly = false;
  bool _expiringSoonOnly = false; // خلال 12 يوم
  bool _expiring30Only = false; // خلال 30 يوم

  late final TextEditingController _searchController;
  late TabController _tabController;

  final Map<int, List<Map<String, dynamic>>> _monthCache = {};
  final Map<int, bool> _monthLoading = {};

  List<String> _companies = [];

  final DateFormat _dfUi = DateFormat('yyyy-MM-dd', 'en_US');
  final NumberFormat _nfInt = NumberFormat.decimalPattern('en_US');

  @override
  void initState() {
    super.initState();

    _searchController = TextEditingController();

    final now = DateTime.now();
    _tabController = TabController(
      length: 12,
      vsync: this,
      initialIndex: (now.month - 1).clamp(0, 11),
    );

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _ensureMonthLoaded(_tabController.index);
      if (mounted) setState(() {});
    });

    _boot();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      await _loadCompanies();
      await _ensureMonthLoaded(_tabController.index, force: true);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل التهيئة: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> _loadCompanies() async {
    final db = await DatabaseMigration.database;

    try {
      final rows = await db.rawQuery(
        "SELECT DISTINCT company_name FROM insurance_policies "
        "WHERE company_name IS NOT NULL AND TRIM(company_name) <> ''",
      );

      final set = <String>{};
      for (final r in rows) {
        final c = (r['company_name'] ?? '').toString().trim();
        if (c.isNotEmpty) set.add(c);
      }
      _companies = set.toList()..sort();
      return;
    } catch (_) {
      final rows = await db.query('insurance_policies');
      final set = <String>{};
      for (final r in rows) {
        final c = (r['company_name'] ?? '').toString().trim();
        if (c.isNotEmpty) set.add(c);
      }
      _companies = set.toList()..sort();
    }
  }

  // ---------------------------------------------------------------------------
  Future<void> _ensureMonthLoaded(int monthIndex, {bool force = false}) async {
    if (!force && _monthCache.containsKey(monthIndex)) return;
    if (_monthLoading[monthIndex] == true) return;

    _monthLoading[monthIndex] = true;
    if (mounted) setState(() {});

    try {
      final rows = await _loadMonthRowsFromDb(monthIndex);
      _monthCache[monthIndex] = rows;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ فشل تحميل الشهر: $e')),
        );
      }
    } finally {
      _monthLoading[monthIndex] = false;
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _loadMonthRowsFromDb(
      int monthIndex) async {
    final db = await DatabaseMigration.database;

    final m = monthIndex + 1;
    final mm = m.toString().padLeft(2, '0');

    try {
      final rows = await db.query(
        'insurance_policies',
        where: "end_date LIKE ?",
        whereArgs: ['____-$mm-%'],
        orderBy: 'created_at DESC',
      );
      if (rows.isNotEmpty) return rows;
    } catch (_) {}

    final all =
        await db.query('insurance_policies', orderBy: 'created_at DESC');

    final out = <Map<String, dynamic>>[];
    for (final r in all) {
      final end = PolicyFilters.parsePolicyDate(r['end_date']);
      if (end == null) continue;
      if (end.month == m) out.add(r);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  Future<void> _openAddPolicy() async {
    if (_loading) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddPolicyScreen()),
    );

    if (result == true) {
      await _loadCompanies();
      await _ensureMonthLoaded(_tabController.index, force: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تحديث قائمة التأمينات')),
        );
      }
    }
  }

  Future<void> _reloadCurrentMonth() async {
    await _ensureMonthLoaded(_tabController.index, force: true);
  }

  // ---------------------------------------------------------------------------
  bool _matchesFilters(Map<String, dynamic> r) {
    return PolicyFilters.matchesFilters(
      r,
      query: _query,
      companyFilter: _companyFilter,
      vipOnly: _vipOnly,
      expiredOnly: _expiredOnly,
      expiringSoonOnly: _expiringSoonOnly,
      expiring30Only: _expiring30Only,
    );
  }

  List<Map<String, dynamic>> get _currentMonthRows {
    final idx = _tabController.index;
    return _monthCache[idx] ?? [];
  }

  List<Map<String, dynamic>> get _filtered =>
      _currentMonthRows.where(_matchesFilters).toList();

  // ---------------------------------------------------------------------------
  void _toggleSide(bool open) => setState(() => _sideOpen = open);

  dynamic _resolvePolicyId(Map<String, dynamic> r) {
    if (r.containsKey('id')) return r['id'];
    if (r.containsKey('policy_id')) return r['policy_id'];
    if (r.containsKey('uuid')) return r['uuid'];
    return null;
  }

  Future<void> _openDetails(Map<String, dynamic> r) async {
    final id = _resolvePolicyId(r);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PolicyDetailsScreen(policyId: id, row: r),
      ),
    );
  }

  Future<void> _openEdit(Map<String, dynamic> r) async {
    final id = _resolvePolicyId(r);
    final ok = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditPolicyScreen(policyId: id, row: r),
      ),
    );
    if (ok == true) {
      await _reloadCurrentMonth();
      await _loadCompanies();
    }
  }

  Future<void> _openPayments(Map<String, dynamic> r) async {
    final id = _resolvePolicyId(r);
    final ok = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PolicyPaymentsScreen(policyId: id, row: r),
      ),
    );
    if (ok == true) await _reloadCurrentMonth();
  }

  Future<void> _deletePolicy(Map<String, dynamic> r) async {
    final id = _resolvePolicyId(r);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا يمكن تحديد معرف البوليصة للحذف')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AdaptiveAlertDialog(
        title: const Text('تأكيد الحذف', textAlign: TextAlign.right),
        content: const Text(
          'هل تريد حذف هذه البوليصة نهائياً؟',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final db = await DatabaseMigration.database;

      String whereCol = 'id';
      if (r.containsKey('policy_id')) whereCol = 'policy_id';
      if (r.containsKey('uuid')) whereCol = 'uuid';

      await db.delete('insurance_policies',
          where: '$whereCol = ?', whereArgs: [id]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم حذف البوليصة')),
      );

      await _reloadCurrentMonth();
      await _loadCompanies();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل الحذف: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  void _toggleExpiring30() {
    setState(() {
      _expiring30Only = !_expiring30Only;
      if (_expiring30Only) _expiringSoonOnly = false;
    });
  }

  void _openArchive() {
    setState(() {
      _expiredOnly = true;
      _expiringSoonOnly = false;
      _expiring30Only = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📦 تم تفعيل وضع الأرشيف (المنتهية)')),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS (PDF + UI)
  // ---------------------------------------------------------------------------
  String _resolveFirst(Map<String, dynamic> r, List<String> keys,
      {String fallback = '-'}) {
    for (final k in keys) {
      final v = r[k];
      if (v == null) continue;
      final t = v.toString().trim();
      if (t.isNotEmpty) return t;
    }
    return fallback;
  }

  bool _isVip(Map<String, dynamic> r) {
    final v = r['is_vip'] ?? r['vip'] ?? r['VIP'];
    if (v == null) return false;
    if (v is int) return v == 1;
    final s = v.toString().trim();
    return s == '1' || s.toLowerCase() == 'true' || s == 'نعم';
  }

  String _statusLabel(Map<String, dynamic> r) {
    try {
      final end = PolicyFilters.parsePolicyDate(r['end_date']);
      if (end == null) return '—';

      final now = DateTime.now();
      final diff =
          end.difference(DateTime(now.year, now.month, now.day)).inDays;

      if (diff < 0) return 'منتهية';
      if (diff <= 12) return 'تنتهي قريباً';
      if (diff <= 30) return 'تنتهي خلال 30 يوم';
      return 'سارية';
    } catch (_) {
      return '—';
    }
  }

  String _filtersLabel() {
    final chips = <String>[];
    if (_query.trim().isNotEmpty) chips.add('بحث');
    if ((_companyFilter ?? '').trim().isNotEmpty) chips.add('شركة');
    if (_vipOnly) chips.add('VIP');
    if (_expiredOnly) chips.add('منتهية');
    if (_expiringSoonOnly) chips.add('12 يوم');
    if (_expiring30Only) chips.add('30 يوم');
    if (chips.isEmpty) return 'كل البيانات';
    return chips.join(' + ');
  }

  String _monthNameAr(int month) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    if (month < 1 || month > 12) return month.toString();
    return months[month - 1];
  }

  String _formatDateOnly(dynamic raw) {
    final d = PolicyFilters.parsePolicyDate(raw);
    if (d == null) return '-';
    return _dfUi.format(d);
  }

  String _formatPhone(dynamic raw) {
    if (raw == null) return '-';
    final s = raw.toString().trim();
    if (s.isEmpty) return '-';
    if (RegExp(r'^\d+$').hasMatch(s) && s.length == 9 && !s.startsWith('0')) {
      return '0$s';
    }
    return s;
  }

  String _docTypeLabel(Map<String, dynamic> r) {
    final raw = _resolveFirst(
      r,
      [
        'document_type',
        'policy_document_type',
        'coverage_type',
        'policy_type',
        'insurance_type',
      ],
      fallback: '',
    ).trim();

    if (raw.isEmpty) return '-';

    final low = raw.toLowerCase();
    if (raw == 'طرف ثالث' ||
        low == 'third' ||
        low == 'tp' ||
        low == 'third_party') {
      return 'طرف ثالث';
    }
    if (raw == 'شامل' || low == 'comprehensive' || low == 'full') {
      return 'شامل';
    }
    return raw;
  }

  String _carPriceLabel(Map<String, dynamic> r) {
    final raw = _resolveFirst(
      r,
      [
        'car_price',
        'vehicle_price',
        'vehicle_value',
        'market_value',
        'carValue',
        'vehicleValue',
        'price',
      ],
      fallback: '',
    ).trim();

    if (raw.isEmpty) return '-';

    final cleaned = raw.replaceAll(',', '').trim();
    final n = double.tryParse(cleaned);
    if (n == null) return raw;

    if (n == n.roundToDouble()) return _nfInt.format(n.round());
    return n.toStringAsFixed(2);
  }

  // ---------------------------------------------------------------------------
  Future<void> _exportPdf() async {
    if (_loading) return;
    final monthBusy = _monthLoading[_tabController.index] == true;
    if (monthBusy || _pdfBusy) return;

    final items = _filtered;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ لا يوجد بيانات للتصدير')),
      );
      return;
    }

    setState(() => _pdfBusy = true);

    try {
      final m = _tabController.index + 1;
      final now = DateTime.now();
      final yyyy = now.year;
      final mm = m.toString().padLeft(2, '0');

      final title =
          'كشف بوالص التأمين — ${_monthNameAr(m)} $yyyy\n(${_filtersLabel()})';

      final headers = <String>[
        'المؤمن له',
        'الشركة',
        'نوع الوثيقة',
        'سعر المركبة',
        'بداية',
        'نهاية',
        'الهاتف',
        'VIP',
        'الحالة',
      ];

      final rows = items.map<List<String>>((r) {
        final insured = _resolveFirst(
          r,
          [
            'insured_name',
            'policy_holder_name',
            'customer_name',
            'client_name',
            'name',
            'owner_name',
          ],
          fallback: '-',
        );

        final company = _resolveFirst(
          r,
          ['company_name', 'insurance_company', 'company'],
          fallback: '-',
        );

        final docType = _docTypeLabel(r);
        final carPrice = _carPriceLabel(r);

        final start = _formatDateOnly(
          _resolveFirst(r, ['start_date', 'policy_start', 'start'],
              fallback: ''),
        );

        final end = _formatDateOnly(
          _resolveFirst(r, ['end_date', 'policy_end', 'end'], fallback: ''),
        );

        final phoneRaw = _resolveFirst(
          r,
          [
            'insured_phone',
            'policy_holder_phone',
            'phone',
            'phone1',
            'mobile',
            'client_phone',
            'customer_phone',
            'owner_phone',
            'insured_mobile',
            'holder_mobile',
          ],
          fallback: '',
        );
        final phone = _formatPhone(phoneRaw);

        final vip = _isVip(r) ? 'نعم' : 'لا';
        final status = _statusLabel(r);

        return [
          insured,
          company,
          docType,
          carPrice,
          start,
          end,
          phone,
          vip,
          status,
        ];
      }).toList();

      final bytes = await YallaPdfService.generateTablePdf(
        title: title,
        headers: headers,
        rows: rows,
      );

      final fileName =
          'policies_${yyyy}_${mm}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      await YallaPdfService.saveAndOpen(bytes: bytes, fileName: fileName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ تم تصدير PDF (${items.length} سجل)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل تصدير PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  // ---------------------------------------------------------------------------
  Widget _buildContent({required bool desktop}) {
    final items = _filtered;
    final monthIndex = _tabController.index;
    final monthBusy = _monthLoading[monthIndex] == true;

    return Container(
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PoliciesListHeader(
            items: items,
            companies: _companies,
            tabController: _tabController,
            loading: _loading,
            monthBusy: monthBusy || _pdfBusy,
            query: _query,
            companyFilter: _companyFilter,
            vipOnly: _vipOnly,
            expiredOnly: _expiredOnly,
            expiringSoonOnly: _expiringSoonOnly,
            expiring30Only: _expiring30Only,
            nfInt: _nfInt,
            onReload: _reloadCurrentMonth,
            onAdd: _openAddPolicy,
            onToggleExpiring30: _toggleExpiring30,
            onOpenArchive: _openArchive,
            onExportPdf: _exportPdf,
            onSearchChanged: (v) {
              _query = v;
              if (_searchController.text != v) _searchController.text = v;
              setState(() {});
            },
            onCompanyChanged: (v) => setState(() => _companyFilter = v),
            onVipOnlyChanged: (v) => setState(() => _vipOnly = v),
            onExpiredOnlyChanged: (v) => setState(() => _expiredOnly = v),
            onExpiringSoonOnlyChanged: (v) =>
                setState(() => _expiringSoonOnly = v),
            onClearFilters: () {
              setState(() {
                _query = '';
                _searchController.clear();
                _companyFilter = null;
                _vipOnly = false;
                _expiredOnly = false;
                _expiringSoonOnly = false;
                _expiring30Only = false;
              });
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: desktop
                ? PoliciesDesktopTable(
                    items: items,
                    busy: monthBusy || _pdfBusy,
                    dateFormat: _dfUi,
                    onOpenDetails: _openDetails,
                    onOpenEdit: _openEdit,
                    onOpenPayments: _openPayments,
                    onDelete: _deletePolicy,
                  )
                : PoliciesMobileCards(
                    items: items,
                    busy: monthBusy || _pdfBusy,
                    dateFormat: _dfUi,
                    onOpenDetails: _openDetails,
                    onOpenEdit: _openEdit,
                    onOpenPayments: _openPayments,
                    onDelete: _deletePolicy,
                  ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ✅ Sidebar Overlay (Right)
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;

        // فقط لتحديد (Desktop Table vs Mobile Cards)
        final desktopTable = w >= 980;

        // عرض السايدبار
        final sideW = w < 600 ? w : ((w >= 1200) ? 320.0 : 300.0);

        final monthBusy = _monthLoading[_tabController.index] == true;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            title: const Text(
              'قائمة التأمينات',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            iconTheme: const IconThemeData(color: Colors.white),

            // ✅ سهم الرجوع
            leading: IconButton(
              tooltip: 'رجوع',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  // ما في صفحة قبلها — خليها آمنة بدون Route
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('ℹ️ لا يوجد صفحة سابقة للرجوع')),
                  );
                }
              },
            ),

            actions: [
              IconButton(
                tooltip: 'تحديث',
                onPressed: (_loading || monthBusy || _pdfBusy)
                    ? null
                    : _reloadCurrentMonth,
                icon: const Icon(Icons.refresh, color: Colors.white),
              ),

              // ✅ هامبرجر دائماً
              IconButton(
                tooltip: _sideOpen ? 'إغلاق القائمة' : 'القائمة',
                onPressed: () => _toggleSide(!_sideOpen),
                icon: Icon(_sideOpen ? Icons.close : Icons.menu,
                    color: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    // ✅ Full Width Content دائماً
                    _buildContent(desktop: desktopTable),

                    // ✅ Sidebar Overlay دائماً (مش ثابت)
                    _rightOverlaySidebar(width: sideW),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed:
                (_loading || monthBusy || _pdfBusy) ? null : _openAddPolicy,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        );
      },
    );
  }
}
