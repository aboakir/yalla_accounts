// lib/features/insurance_agent/contacts/screens/insurance_contacts_list_screen.dart
//
// InsuranceContactsListScreen — UPDATED (Hamburger + Back + Right Overlay Sidebar)
// ✅ زر هامبرجر (Overlay Sidebar من اليمين) على Desktop + Mobile
// ✅ سهم رجوع في AppBar
// ✅ باقي الميزات كما هي: Tabs 13 + Add/Edit Dialog + SharedPrefs + PDF + Filters

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

// ✅ Sidebar
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class InsuranceContactsListScreen extends StatefulWidget {
  const InsuranceContactsListScreen({super.key});

  @override
  State<InsuranceContactsListScreen> createState() =>
      _InsuranceContactsListScreenState();
}

class _InsuranceContactsListScreenState
    extends State<InsuranceContactsListScreen>
    with SingleTickerProviderStateMixin {
  static const _prefsKey = 'insurance_contact_leads_v1';

  final _nfDate = DateFormat('yyyy-MM-dd', 'en_US');

  bool _busy = false;
  String _query = '';

  // ✅ فلتر: عرض فقط القريبة (<= 30 يوم) — يشتغل فقط لمن لديهم endDate
  bool _expiring30Only = false;

  // ✅ Sidebar overlay state
  bool _sideOpen = false;

  late final TabController _tabController;

  List<_LeadContact> _items = [];

  @override
  void initState() {
    super.initState();

    // ✅ 13 تبويب: 0=بدون تاريخ, 1..12=الأشهر
    final now = DateTime.now();
    _tabController = TabController(length: 13, vsync: this);

    // افتراضيًا افتح شهر اليوم (لأن 0 = بدون تاريخ)
    _tabController.index = now.month;

    // ✅ إصلاح مهم: إعادة بناء الشاشة عند تغيير التبويب
    _tabController.addListener(() {
      if (!mounted) return;
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });

    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Sidebar helpers
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

  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);

      if (raw == null || raw.trim().isEmpty) {
        _items = [];
      } else {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        _items = list.map(_LeadContact.fromJson).toList();
      }

      // ✅ ترتيب عام:
      // 1) اللي عنده endDate الأقرب أولًا
      // 2) اللي بدون endDate يجي آخر
      _items.sort((a, b) {
        final ad = a.endDate;
        final bd = b.endDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }

  // ============================================================
  // Filtering / Grouping
  // ============================================================

  bool _matchesQuery(_LeadContact e, String q) {
    if (q.isEmpty) return true;
    final qq = q.trim();
    return (e.name ?? '').contains(qq) ||
        (e.phone ?? '').contains(qq) ||
        (e.vehicleMake ?? '').contains(qq);
  }

  int _daysLeft(DateTime endDate) {
    final now = DateTime.now();
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final today = DateTime(now.year, now.month, now.day);
    return end.difference(today).inDays;
  }

  bool _isExpiringWithin30(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return false;
    final left = _daysLeft(d);
    return left >= 0 && left <= 30;
  }

  // tabIndex: 0 = بدون تاريخ, 1..12 = شهر
  List<_LeadContact> _itemsForTab(int tabIndex) {
    final q = _query.trim();

    final list = _items.where((e) {
      // ✅ بحث
      if (!_matchesQuery(e, q)) return false;

      // ✅ تبويب بدون تاريخ
      if (tabIndex == 0) {
        return e.endDate == null;
      }

      // ✅ تبويبات الأشهر
      final d = e.endDate;
      if (d == null) return false;

      final month = tabIndex; // لأن tabIndex نفسه هو الشهر 1..12
      if (d.month != month) return false;

      // ✅ فلتر القريبة (يعمل فقط للأشهر)
      if (_expiring30Only && !_isExpiringWithin30(e)) return false;

      return true;
    }).toList();

    // ترتيب داخل التبويب:
    if (tabIndex == 0) {
      // بدون تاريخ: الأحدث تحديثًا/إنشاءً أولًا
      list.sort((a, b) {
        final bx = b.updatedAt ?? b.createdAt ?? DateTime(2000);
        final ax = a.updatedAt ?? a.createdAt ?? DateTime(2000);
        return bx.compareTo(ax);
      });
    } else {
      // الأشهر: الأقرب انتهاءً أولًا
      list.sort((a, b) =>
          (a.endDate ?? DateTime(2100)).compareTo(b.endDate ?? DateTime(2100)));
    }

    return list;
  }

  int _countExpiring30InMonth(int month) {
    final items = _itemsForTab(month);
    return items.where(_isExpiringWithin30).length;
  }

  int _countExpiring30InCurrentTab() {
    final tabIndex = _tabController.index;
    if (tabIndex == 0) return 0;
    return _itemsForTab(tabIndex).where(_isExpiringWithin30).length;
  }

  // ============================================================
  // Actions
  // ============================================================

  Future<void> _openAddDialog() async {
    final result = await showDialog<_LeadContact>(
      context: context,
      builder: (_) => _LeadDialog(nfDate: _nfDate),
    );

    if (result == null) return;

    setState(() => _items.insert(0, result));
    await _save();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم حفظ الزبون في قائمة التواصل')),
    );
  }

  Future<void> _openEditDialog(_LeadContact lead) async {
    final edited = await showDialog<_LeadContact>(
      context: context,
      builder: (_) => _LeadDialog(
        nfDate: _nfDate,
        existing: lead,
      ),
    );

    if (edited == null) return;

    setState(() {
      final idx = _items.indexWhere((e) => e.id == lead.id);
      if (idx >= 0) _items[idx] = edited;
    });

    // إعادة ترتيب عام
    _items.sort((a, b) {
      final ad = a.endDate;
      final bd = b.endDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    await _save();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم تحديث بيانات الزبون')),
    );
  }

  Future<void> _confirmDelete(_LeadContact lead) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('إلغاء التواصل'),
        content: Text(
          'متأكد بدك تحذف "${(lead.name ?? '').trim().isEmpty ? 'بدون اسم' : lead.name!.trim()}"؟',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ط­ط°ظپ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _items.removeWhere((e) => e.id == lead.id));
    await _save();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ تم حذف السجل')),
    );
  }

  void _openAddPolicyPrefilled(_LeadContact lead) {
    final args = <String, dynamic>{
      'insuredName': (lead.name ?? '').trim(),
      'insuredPhone': (lead.phone ?? '').trim(),
      'vehicleMake': (lead.vehicleMake ?? '').trim(),
      'endDate': lead.endDate == null ? null : _nfDate.format(lead.endDate!),
    };

    Navigator.of(context)
        .pushNamed(AppRoutes.insuranceAgentAddNew, arguments: args);
  }

  Future<void> _exportCurrentTabPdf() async {
    if (_busy) return;

    final tabIndex = _tabController.index;
    final items = _itemsForTab(tabIndex);

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد بيانات للطباعة في هذا العرض')),
      );
      return;
    }

    final title = tabIndex == 0
        ? 'قائمة التواصل — بدون تاريخ انتهاء'
        : 'قائمة التواصل — شهر $tabIndex';

    final headers = <String>[
      'الاسم',
      'الهاتف',
      'نوع المركبة',
      'انتهاء التأمين',
      'الحالة',
    ];

    String statusText(_LeadContact e) {
      final d = e.endDate;
      if (d == null) return 'غير معروف';
      final left = _daysLeft(d);
      if (left < 0) return 'منتهية';
      if (left <= 30) return 'متبقي $left يوم';
      return 'سارية';
    }

    final rows = items.map((e) {
      final end = e.endDate == null ? '-' : _nfDate.format(e.endDate!);
      return <String>[
        _dashIfEmpty(e.name),
        _dashIfEmpty(e.phone),
        _dashIfEmpty(e.vehicleMake),
        end,
        statusText(e),
      ];
    }).toList();

    try {
      final bytes = await YallaPdfService.generateTablePdf(
        title: title,
        headers: headers,
        rows: rows,
      );

      final fileName = tabIndex == 0
          ? 'insurance_contacts_no_date${_expiring30Only ? '_expiring30' : ''}.pdf'
          : 'insurance_contacts_month_${tabIndex.toString().padLeft(2, '0')}${_expiring30Only ? '_expiring30' : ''}.pdf';

      await YallaPdfService.saveAndOpen(
        bytes: bytes,
        fileName: fileName,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ تم إنشاء PDF وفتحه')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ فشل إنشاء PDF: $e')),
      );
    }
  }

  String _dashIfEmpty(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? '-' : t;
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isWide = w >= 900;

    // ✅ عرض السايدبار
    final sideW = (w >= 1200) ? 320.0 : 300.0;

    final tabIndex = _tabController.index;
    final items = _itemsForTab(tabIndex);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'قائمة التواصل',
          style: TextStyle(color: Colors.white),
        ),

        // ✅ سهم الرجوع
        leading: IconButton(
          tooltip: 'رجوع',
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ℹ️ لا يوجد صفحة سابقة للرجوع')),
              );
            }
          },
        ),

        actions: [
          IconButton(
            tooltip: 'تصدير PDF (العرض الحالي)',
            onPressed: _busy ? null : _exportCurrentTabPdf,
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'إضافة زبون محتمل',
            onPressed: _busy ? null : _openAddDialog,
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          ),

          // ✅ الهامبرجر دائماً
          IconButton(
            tooltip: _sideOpen ? 'إغلاق القائمة' : 'القائمة',
            onPressed: () => _toggleSide(!_sideOpen),
            icon:
                Icon(_sideOpen ? Icons.close : Icons.menu, color: Colors.white),
          ),

          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: AppColors.primary.withOpacity(0.96),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                const Tab(child: Text('بدون تاريخ')),
                ...List.generate(12, (i) {
                  final m = i + 1;
                  final expCount = _countExpiring30InMonth(m);
                  return Tab(
                    child: AdaptiveRow(
                      children: [
                        Text('$m'),
                        if (expCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '$expCount',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _busy ? null : _openAddDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('إضافة', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          // المحتوى الأساسي
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _HeaderBar(
                  busy: _busy,
                  tabIndex: tabIndex,
                  shown: items.length,
                  query: _query,
                  expiring30Only: _expiring30Only,
                  expiringCountInTab: _countExpiring30InCurrentTab(),
                  onQueryChanged: (v) => setState(() => _query = v),
                  onToggleExpiring30: () =>
                      setState(() => _expiring30Only = !_expiring30Only),
                ),
                const SizedBox(height: 10),
                _ExpiringBanner(
                  busy: _busy,
                  tabIndex: tabIndex,
                  count: _countExpiring30InCurrentTab(),
                  expiring30Only: _expiring30Only,
                  onToggle: () =>
                      setState(() => _expiring30Only = !_expiring30Only),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : (items.isEmpty
                          ? _EmptyState(onAdd: _openAddDialog)
                          : (isWide
                              ? _WideTable(
                                  items: items,
                                  nfDate: _nfDate,
                                  daysLeft: _daysLeft,
                                  onInsure: _openAddPolicyPrefilled,
                                  onEdit: _openEditDialog,
                                  onDelete: _confirmDelete,
                                )
                              : _CardsList(
                                  items: items,
                                  nfDate: _nfDate,
                                  daysLeft: _daysLeft,
                                  onInsure: _openAddPolicyPrefilled,
                                  onEdit: _openEditDialog,
                                  onDelete: _confirmDelete,
                                ))),
                ),
              ],
            ),
          ),

          // ✅ Sidebar Overlay
          _rightOverlaySidebar(width: sideW),
        ],
      ),
    );
  }
}

// ============================================================
// Header
// ============================================================

class _HeaderBar extends StatelessWidget {
  final bool busy;
  final int tabIndex;
  final int shown;
  final String query;

  final bool expiring30Only;
  final int expiringCountInTab;

  final ValueChanged<String> onQueryChanged;
  final VoidCallback onToggleExpiring30;

  const _HeaderBar({
    required this.busy,
    required this.tabIndex,
    required this.shown,
    required this.query,
    required this.expiring30Only,
    required this.expiringCountInTab,
    required this.onQueryChanged,
    required this.onToggleExpiring30,
  });

  @override
  Widget build(BuildContext context) {
    final isNoDateTab = tabIndex == 0;

    return AdaptiveRow(
      children: [
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (busy) const SizedBox(width: 10),
        Text(
          isNoDateTab
              ? 'المعروض: $shown (بدون تاريخ)'
              : 'المعروض: $shown (الشهر $tabIndex)',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const Spacer(),
        Tooltip(
          message: isNoDateTab
              ? 'فلتر ≤30 يوم يحتاج تاريخ انتهاء'
              : 'عرض فقط التي تنتهي خلال 30 يوم',
          child: InkWell(
            onTap: isNoDateTab ? null : onToggleExpiring30,
            borderRadius: BorderRadius.circular(12),
            child: Opacity(
              opacity: isNoDateTab ? 0.35 : 1,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: expiring30Only
                        ? Colors.orange.shade700
                        : Colors.grey.shade300,
                  ),
                  color: expiring30Only
                      ? Colors.orange.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AdaptiveRow(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      size: 18,
                      color: expiring30Only
                          ? Colors.orange.shade700
                          : Colors.grey.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isNoDateTab
                          ? '≤ 30 يوم'
                          : '≤ 30 يوم ($expiringCountInTab)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: expiring30Only
                            ? Colors.orange.shade800
                            : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 380,
          child: TextField(
            inputFormatters: const [YallaDigitNormalizer()],
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم / الهاتف / نوع المركبة',
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              isDense: true,
            ),
            onChanged: onQueryChanged,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Banner
// ============================================================

class _ExpiringBanner extends StatelessWidget {
  final bool busy;
  final int tabIndex;
  final int count;
  final bool expiring30Only;
  final VoidCallback onToggle;

  const _ExpiringBanner({
    required this.busy,
    required this.tabIndex,
    required this.count,
    required this.expiring30Only,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) return const SizedBox.shrink();

    if (tabIndex == 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.withOpacity(0.06),
        ),
        child: AdaptiveRow(
          children: [
            Icon(Icons.info_outline, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'هذا التبويب للزبائن بدون تاريخ انتهاء، لذلك تنبيهات ≤30 يوم لا تنطبق هنا.',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    if (count <= 0) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.lightGreen),
          color: AppColors.primary.withOpacity(0.08),
        ),
        child: AdaptiveRow(
          children: [
            Icon(Icons.verified, color: AppColors.primary),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '✅ لا يوجد ملفات تنتهي خلال 30 يوم في هذا الشهر (حسب البحث الحالي).',
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
        color: Colors.orange.withOpacity(0.10),
      ),
      child: AdaptiveRow(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '⚠️ تنبيه: يوجد $count ملف/ملفات تنتهي خلال 30 يوم في هذا الشهر (حسب البحث الحالي).',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onToggle,
            icon: Icon(
              expiring30Only ? Icons.filter_alt_off : Icons.filter_alt,
              color: Colors.orange.shade800,
            ),
            label:
                Text(expiring30Only ? 'إلغاء فلتر القريبة' : 'عرض القريبة فقط'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Empty
// ============================================================

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contact_phone, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 10),
            const Text(
              'لا يوجد زبائن في هذا العرض.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'جرّب البحث أو تغيير التبويب، أو أضف زبون جديد.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('إضافة زبون'),
            )
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Wide Table
// ============================================================

class _WideTable extends StatelessWidget {
  final List<_LeadContact> items;
  final DateFormat nfDate;
  final int Function(DateTime) daysLeft;
  final void Function(_LeadContact) onInsure;
  final void Function(_LeadContact) onEdit;
  final void Function(_LeadContact) onDelete;

  const _WideTable({
    required this.items,
    required this.nfDate,
    required this.daysLeft,
    required this.onInsure,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return Colors.grey;
    final left = daysLeft(d);
    if (left < 0) return Colors.redAccent;
    if (left <= 30) return Colors.orange.shade800;
    return AppColors.primary;
  }

  String _statusText(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return 'غير معروف';
    final left = daysLeft(d);
    if (left < 0) return 'منتهية';
    if (left <= 30) return 'متبقي $left يوم';
    return 'سارية';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1180),
        child: SingleChildScrollView(
          child: AdaptiveDataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 72,
            columns: const [
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('رقم الهاتف')),
              DataColumn(label: Text('نوع المركبة')),
              DataColumn(label: Text('انتهاء التأمين')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('إجراءات')),
            ],
            rows: items.map((e) {
              final end = e.endDate == null ? '-' : nfDate.format(e.endDate!);
              final status = _statusText(e);
              final c = _statusColor(e);

              return DataRow(
                cells: [
                  DataCell(
                      Text(_dashIfEmpty(e.name), textAlign: TextAlign.right)),
                  DataCell(
                      Text(_dashIfEmpty(e.phone), textAlign: TextAlign.right)),
                  DataCell(Text(_dashIfEmpty(e.vehicleMake),
                      textAlign: TextAlign.right)),
                  DataCell(Text(end, textAlign: TextAlign.right)),
                  DataCell(
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.withOpacity(0.10),
                          border: Border.all(color: c),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status,
                          style:
                              TextStyle(color: c, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    AdaptiveRow(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => onInsure(e),
                          icon: const Icon(Icons.verified_user,
                              color: AppColors.primary),
                          label: const Text('تأمين المركبة'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'تعديل',
                          onPressed: () => onEdit(e),
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.blueGrey),
                        ),
                        IconButton(
                          tooltip: 'ط­ط°ظپ',
                          onPressed: () => onDelete(e),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  String _dashIfEmpty(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? '-' : t;
  }
}

// ============================================================
// Cards
// ============================================================

class _CardsList extends StatelessWidget {
  final List<_LeadContact> items;
  final DateFormat nfDate;
  final int Function(DateTime) daysLeft;
  final void Function(_LeadContact) onInsure;
  final void Function(_LeadContact) onEdit;
  final void Function(_LeadContact) onDelete;

  const _CardsList({
    required this.items,
    required this.nfDate,
    required this.daysLeft,
    required this.onInsure,
    required this.onEdit,
    required this.onDelete,
  });

  Color _statusColor(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return Colors.grey;
    final left = daysLeft(d);
    if (left < 0) return Colors.redAccent;
    if (left <= 30) return Colors.orange.shade800;
    return AppColors.primary;
  }

  String _statusText(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return 'غير معروف';
    final left = daysLeft(d);
    if (left < 0) return 'منتهية';
    if (left <= 30) return 'متبقي $left يوم';
    return 'سارية';
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final e = items[i];
        final end = e.endDate == null ? '-' : nfDate.format(e.endDate!);
        final c = _statusColor(e);
        final status = _statusText(e);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AdaptiveRow(
                children: [
                  IconButton(
                    tooltip: 'ط­ط°ظپ',
                    onPressed: () => onDelete(e),
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent),
                  ),
                  IconButton(
                    tooltip: 'تعديل',
                    onPressed: () => onEdit(e),
                    icon:
                        const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                  ),
                  const Spacer(),
                  Text(
                    (e.name ?? '').trim().isEmpty ? 'بدون اسم' : e.name!.trim(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AdaptiveRow(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.10),
                      border: Border.all(color: c),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(color: c, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const Spacer(),
                  Text('الحالة', style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 10),
              _kv('رقم الهاتف', _dashIfEmpty(e.phone)),
              _kv('نوع المركبة', _dashIfEmpty(e.vehicleMake)),
              _kv('انتهاء التأمين', end),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onInsure(e),
                  icon:
                      const Icon(Icons.verified_user, color: AppColors.primary),
                  label: const Text('تأمين المركبة'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: AdaptiveRow(
        children: [
          Expanded(child: Text(v, textAlign: TextAlign.right)),
          const SizedBox(width: 10),
          Text(k, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  String _dashIfEmpty(String? s) {
    final t = (s ?? '').trim();
    return t.isEmpty ? '-' : t;
  }
}

// ============================================================
// Add/Edit Dialog
// ============================================================

class _LeadDialog extends StatefulWidget {
  final DateFormat nfDate;
  final _LeadContact? existing;

  const _LeadDialog({
    required this.nfDate,
    this.existing,
  });

  @override
  State<_LeadDialog> createState() => _LeadDialogState();
}

class _LeadDialogState extends State<_LeadDialog> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _vehicleMake;

  DateTime? _endDate;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _vehicleMake =
        TextEditingController(text: widget.existing?.vehicleMake ?? '');
    _endDate = widget.existing?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicleMake.dispose();
    super.dispose();
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  void _clearEndDate() => setState(() => _endDate = null);

  void _submit() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final make = _vehicleMake.text.trim();

    final allEmpty =
        name.isEmpty && phone.isEmpty && make.isEmpty && _endDate == null;
    if (allEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('⚠️ أدخل على الأقل معلومة واحدة قبل الحفظ')),
      );
      return;
    }

    final lead = _LeadContact(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      phone: phone,
      vehicleMake: make,
      endDate: _endDate,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop(lead);
  }

  @override
  Widget build(BuildContext context) {
    final endText = _endDate == null
        ? 'بدون تاريخ انتهاء'
        : widget.nfDate.format(_endDate!);

    return AdaptiveAlertDialog(
      title: Text(isEdit ? 'تعديل زبون محتمل' : 'إضافة زبون محتمل'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _name,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'الاسم (اختياري)'),
            ),
            const SizedBox(height: 8),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _phone,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'رقم الهاتف (اختياري)'),
            ),
            const SizedBox(height: 8),
            TextField(
              inputFormatters: const [YallaDigitNormalizer()],
              controller: _vehicleMake,
              textAlign: TextAlign.right,
              decoration:
                  const InputDecoration(labelText: 'نوع المركبة (اختياري)'),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickEndDate,
                    icon: const Icon(Icons.event),
                    label: Text(endText),
                  ),
                  if (_endDate != null)
                    TextButton.icon(
                      onPressed: _clearEndDate,
                      icon: const Icon(Icons.clear),
                      label: const Text('مسح التاريخ'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('ط­ظپط¸'),
        ),
      ],
    );
  }
}

// ============================================================
// Model
// ============================================================

class _LeadContact {
  final String id;
  final String? name;
  final String? phone;
  final String? vehicleMake;
  final DateTime? endDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  _LeadContact({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleMake,
    required this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'vehicleMake': vehicleMake,
        'endDate': endDate?.toIso8601String(),
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static _LeadContact fromJson(Map<String, dynamic> j) {
    DateTime? dt(String? s) =>
        (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

    return _LeadContact(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      vehicleMake: (j['vehicleMake'] ?? '').toString(),
      endDate: dt(j['endDate']?.toString()),
      createdAt: dt(j['createdAt']?.toString()),
      updatedAt: dt(j['updatedAt']?.toString()),
    );
  }
}
