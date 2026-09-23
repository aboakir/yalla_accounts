import 'package:yalla_accounts/core/utils/user_facing_error.dart';
// lib/features/insurance_agent/contacts/screens/insurance_contacts_list_screen.dart
//
// InsuranceContactsListScreen — UPDATED (Hamburger + Back + Right Overlay Sidebar)
// ✅ زر هامبرجر (Overlay Sidebar من اليمين) على Desktop + Mobile
// ✅ سهم رجوع في AppBar
// ✅ باقي الميزات كما هي: Tabs 13 + Add/Edit Dialog + SharedPrefs + PDF + Filters

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/features/insurance_agent/contacts/services/insurance_crm_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

// ✅ Sidebar
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

typedef InsuranceProspectLoader = Future<List<InsuranceProspectRecord>>
    Function();

class InsuranceContactsListScreen extends StatefulWidget {
  const InsuranceContactsListScreen({super.key, this.loader});

  final InsuranceProspectLoader? loader;

  @override
  State<InsuranceContactsListScreen> createState() =>
      _InsuranceContactsListScreenState();
}

class _InsuranceContactsListScreenState
    extends State<InsuranceContactsListScreen>
    with SingleTickerProviderStateMixin {
  final _nfDate = DateFormat('yyyy-MM-dd', 'en_US');

  bool _busy = false;
  String _query = '';
  String _statusFilter = 'ALL';

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
      final records =
          await (widget.loader?.call() ?? InsuranceCrmService.listProspects());
      _items = records
          .map(
            (row) => _LeadContact(
              id: row.id,
              partyId: row.partyId,
              name: row.name,
              phone: row.phone,
              status: row.status,
              city: row.city,
              source: row.source,
              currentCompany: row.currentCompany,
              vehicleMake: row.vehicleSummary,
              endDate: row.currentPolicyExpiry,
              lastContactAt: row.lastContactAt,
              nextContactAt: row.nextContactAt,
              contactResult: row.contactResult,
              notes: row.notes,
              createdAt: row.createdAt,
              updatedAt: row.updatedAt,
            ),
          )
          .toList();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ============================================================
  // Filtering / Grouping
  // ============================================================

  bool _matchesQuery(_LeadContact e, String q) {
    if (q.trim().isEmpty) return true;
    String normalize(String? value) => YallaDigitNormalizer.normalize(
          value ?? '',
        ).trim().toLowerCase();
    final qq = normalize(q);
    return <String?>[
      e.name,
      e.phone,
      e.vehicleMake,
      e.city,
      e.currentCompany,
      e.source,
      e.contactResult,
      e.notes,
      e.status,
    ].any((value) => normalize(value).contains(qq));
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
      if (_statusFilter != 'ALL' &&
          e.status.trim().toUpperCase() != _statusFilter) {
        return false;
      }

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

    await InsuranceCrmService.createProspect(
      name: result.name ?? '',
      phone: result.phone ?? '',
      status: result.status,
      vehicleSummary: result.vehicleMake,
      currentPolicyExpiry: result.endDate,
      city: result.city,
      source: result.source,
      currentCompany: result.currentCompany,
      notes: result.notes,
    );
    await _load();

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

    await InsuranceCrmService.updateProspect(
      id: lead.id,
      name: edited.name ?? '',
      phone: edited.phone ?? '',
      status: edited.status,
      vehicleSummary: edited.vehicleMake,
      currentPolicyExpiry: edited.endDate,
      city: edited.city,
      source: edited.source,
      currentCompany: edited.currentCompany,
      lastContactAt: lead.lastContactAt,
      nextContactAt: lead.nextContactAt,
      contactResult: lead.contactResult,
      notes: edited.notes,
    );
    await _load();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ تم تحديث بيانات الزبون')),
    );
  }

  Future<void> _openFollowUpDialog(_LeadContact lead) async {
    final result = await showDialog<_FollowUpDraft>(
      context: context,
      builder: (_) => _FollowUpDialog(
        nfDate: _nfDate,
        existing: lead,
      ),
    );
    if (result == null) return;

    try {
      await InsuranceCrmService.recordContact(
        prospectId: lead.id,
        channel: result.channel,
        status: result.status,
        result: result.result,
        notes: result.notes,
        nextFollowUpAt: result.nextContactAt,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ تم تسجيل المتابعة وموعد التواصل القادم')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ تعذر تسجيل المتابعة: ${UserFacingError.message(e)}'),
        ),
      );
    }
  }

  Future<void> _openLicenseDialog(_LeadContact lead) async {
    try {
      final licenses = await InsuranceCrmService.listDrivingLicenses(
        partyId: lead.partyId,
      );
      if (!mounted) return;
      final result = await showDialog<_LicenseDraft>(
        context: context,
        builder: (_) => _LicenseDialog(
          nfDate: _nfDate,
          existing: licenses.isEmpty ? null : licenses.first,
        ),
      );
      if (result == null) return;

      await InsuranceCrmService.upsertDrivingLicense(
        partyId: lead.partyId,
        licenseNumber: result.licenseNumber,
        licenseType: result.licenseType,
        issueDate: result.issueDate,
        expiryDate: result.expiryDate,
        categories: result.categories,
        notes: result.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('✅ تم حفظ رخصة القيادة وتحديث تنبيهات انتهائها')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('❌ تعذر حفظ رخصة القيادة: ${UserFacingError.message(e)}'),
        ),
      );
    }
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
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await InsuranceCrmService.archiveProspect(lead.id);
    await _load();

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
        SnackBar(
            content: Text('❌ فشل إنشاء PDF: ${UserFacingError.message(e)}')),
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
      key: const Key('insuranceCrmScreen'),
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
          onPressed: () => AppRoutes.popOrDashboard(context),
        ),

        actions: [
          IconButton(
            key: const Key('openInsuranceContactCenter'),
            tooltip: 'مركز التواصل والمتابعات',
            onPressed: _busy
                ? null
                : () => Navigator.of(context).pushNamed(
                      AppRoutes.insuranceAgentContactCenter,
                    ),
            icon: const Icon(Icons.support_agent, color: Colors.white),
          ),
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
                  statusFilter: _statusFilter,
                  expiring30Only: _expiring30Only,
                  expiringCountInTab: _countExpiring30InCurrentTab(),
                  onQueryChanged: (v) => setState(() => _query = v),
                  onStatusChanged: (v) =>
                      setState(() => _statusFilter = v ?? 'ALL'),
                  onToggleExpiring30: () =>
                      setState(() => _expiring30Only = !_expiring30Only),
                ),
                const SizedBox(height: 10),
                KeyedSubtree(
                  key: const Key('insuranceCrmExpiringBanner'),
                  child: _ExpiringBanner(
                    busy: _busy,
                    tabIndex: tabIndex,
                    count: _countExpiring30InCurrentTab(),
                    expiring30Only: _expiring30Only,
                    onToggle: () =>
                        setState(() => _expiring30Only = !_expiring30Only),
                  ),
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
                                  onFollowUp: _openFollowUpDialog,
                                  onLicense: _openLicenseDialog,
                                  onEdit: _openEditDialog,
                                  onDelete: _confirmDelete,
                                )
                              : _CardsList(
                                  items: items,
                                  nfDate: _nfDate,
                                  daysLeft: _daysLeft,
                                  onInsure: _openAddPolicyPrefilled,
                                  onFollowUp: _openFollowUpDialog,
                                  onLicense: _openLicenseDialog,
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
  final String statusFilter;

  final bool expiring30Only;
  final int expiringCountInTab;

  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onToggleExpiring30;

  const _HeaderBar({
    required this.busy,
    required this.tabIndex,
    required this.shown,
    required this.statusFilter,
    required this.expiring30Only,
    required this.expiringCountInTab,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onToggleExpiring30,
  });

  @override
  Widget build(BuildContext context) {
    final isNoDateTab = tabIndex == 0;
    final shownText = isNoDateTab
        ? 'المعروض: $shown (بدون تاريخ)'
        : 'المعروض: $shown (الشهر $tabIndex)';

    final expiringFilter = Tooltip(
      message: isNoDateTab
          ? 'فلتر ≤30 يوم يحتاج تاريخ انتهاء'
          : 'عرض فقط التي تنتهي خلال 30 يوم',
      child: InkWell(
        onTap: isNoDateTab ? null : onToggleExpiring30,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isNoDateTab ? 0.35 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                  isNoDateTab ? '≤ 30 يوم' : '≤ 30 يوم ($expiringCountInTab)',
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
    );

    final statusField = DropdownButtonFormField<String>(
      key: const Key('insuranceCrmStatusFilter'),
      value: statusFilter,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'حالة العميل',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: <String>['ALL', ...InsuranceCrmService.prospectStatuses]
          .map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(
                status == 'ALL' ? 'كل الحالات' : _crmStatusLabel(status),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: onStatusChanged,
    );

    final searchField = TextField(
      key: const Key('insuranceCrmSearch'),
      inputFormatters: const [YallaDigitNormalizer()],
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم / الهاتف / المدينة / الشركة',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      onChanged: onQueryChanged,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (busy) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      shownText,
                      style: TextStyle(color: Colors.grey.shade700),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  expiringFilter,
                ],
              ),
              const SizedBox(height: 8),
              statusField,
              const SizedBox(height: 8),
              searchField,
            ],
          );
        }

        return Row(
          children: [
            if (busy) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            Text(shownText, style: TextStyle(color: Colors.grey.shade700)),
            const Spacer(),
            expiringFilter,
            const SizedBox(width: 10),
            SizedBox(width: 210, child: statusField),
            const SizedBox(width: 10),
            SizedBox(width: 380, child: searchField),
          ],
        );
      },
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final message = Text(
            '⚠️ تنبيه: يوجد $count ملف/ملفات تنتهي خلال 30 يوم في هذا الشهر (حسب البحث الحالي).',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade900,
            ),
          );
          final action = OutlinedButton.icon(
            onPressed: onToggle,
            icon: Icon(
              expiring30Only ? Icons.filter_alt_off : Icons.filter_alt,
              color: Colors.orange.shade800,
            ),
            label:
                Text(expiring30Only ? 'إلغاء فلتر القريبة' : 'عرض القريبة فقط'),
          );

          if (constraints.maxWidth < 520) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: message),
                  ],
                ),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }

          return Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade800,
              ),
              const SizedBox(width: 10),
              Expanded(child: message),
              const SizedBox(width: 10),
              action,
            ],
          );
        },
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
  final void Function(_LeadContact) onFollowUp;
  final void Function(_LeadContact) onLicense;
  final void Function(_LeadContact) onEdit;
  final void Function(_LeadContact) onDelete;

  const _WideTable({
    required this.items,
    required this.nfDate,
    required this.daysLeft,
    required this.onInsure,
    required this.onFollowUp,
    required this.onLicense,
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
        constraints: const BoxConstraints(minWidth: 1600),
        child: SingleChildScrollView(
          child: AdaptiveDataTable(
            headingRowHeight: 44,
            dataRowMinHeight: 64,
            dataRowMaxHeight: 88,
            columns: const [
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('رقم الهاتف')),
              DataColumn(label: Text('المدينة')),
              DataColumn(label: Text('نوع المركبة')),
              DataColumn(label: Text('شركة التأمين الحالية')),
              DataColumn(label: Text('انتهاء التأمين')),
              DataColumn(label: Text('حالة CRM')),
              DataColumn(label: Text('المتابعة القادمة')),
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
                  DataCell(
                      Text(_dashIfEmpty(e.city), textAlign: TextAlign.right)),
                  DataCell(Text(_dashIfEmpty(e.vehicleMake),
                      textAlign: TextAlign.right)),
                  DataCell(Text(_dashIfEmpty(e.currentCompany),
                      textAlign: TextAlign.right)),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(end, textAlign: TextAlign.right),
                        Text(
                          status,
                          style: TextStyle(
                            color: c,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.withOpacity(0.10),
                          border: Border.all(color: Colors.blueGrey),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _crmStatusLabel(e.status),
                          style: const TextStyle(
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      e.nextContactAt == null
                          ? '-'
                          : nfDate.format(e.nextContactAt!),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  DataCell(
                    AdaptiveRow(
                      children: [
                        IconButton(
                          key: Key('crmFollowUp-${e.id}'),
                          tooltip: 'تسجيل متابعة',
                          onPressed: () => onFollowUp(e),
                          icon: const Icon(Icons.add_task,
                              color: AppColors.primary),
                        ),
                        IconButton(
                          key: Key('crmLicense-${e.id}'),
                          tooltip: 'رخصة القيادة',
                          onPressed: () => onLicense(e),
                          icon: const Icon(Icons.badge_outlined),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onInsure(e),
                          icon: const Icon(Icons.verified_user,
                              color: AppColors.primary),
                          label: const Text('تأمين'),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'تعديل',
                          onPressed: () => onEdit(e),
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.blueGrey),
                        ),
                        IconButton(
                          tooltip: 'حذف',
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
  final void Function(_LeadContact) onFollowUp;
  final void Function(_LeadContact) onLicense;
  final void Function(_LeadContact) onEdit;
  final void Function(_LeadContact) onDelete;

  const _CardsList({
    required this.items,
    required this.nfDate,
    required this.daysLeft,
    required this.onInsure,
    required this.onFollowUp,
    required this.onLicense,
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
                    tooltip: 'حذف',
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
              _kv('حالة CRM', _crmStatusLabel(e.status)),
              _kv('رقم الهاتف', _dashIfEmpty(e.phone)),
              _kv('المدينة', _dashIfEmpty(e.city)),
              _kv('نوع المركبة', _dashIfEmpty(e.vehicleMake)),
              _kv('الشركة الحالية', _dashIfEmpty(e.currentCompany)),
              _kv('انتهاء التأمين', end),
              _kv(
                'آخر تواصل',
                e.lastContactAt == null ? '-' : nfDate.format(e.lastContactAt!),
              ),
              _kv(
                'المتابعة القادمة',
                e.nextContactAt == null ? '-' : nfDate.format(e.nextContactAt!),
              ),
              _kv('نتيجة التواصل', _dashIfEmpty(e.contactResult)),
              const SizedBox(height: 10),
              AdaptiveRow(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('crmFollowUp-${e.id}'),
                      onPressed: () => onFollowUp(e),
                      icon: const Icon(Icons.add_task),
                      label: const Text('تسجيل متابعة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('crmLicense-${e.id}'),
                      onPressed: () => onLicense(e),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('رخصة القيادة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
  late final TextEditingController _city;
  late final TextEditingController _source;
  late final TextEditingController _currentCompany;
  late final TextEditingController _notes;

  late String _status;
  DateTime? _endDate;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _phone = TextEditingController(text: widget.existing?.phone ?? '');
    _vehicleMake =
        TextEditingController(text: widget.existing?.vehicleMake ?? '');
    _city = TextEditingController(text: widget.existing?.city ?? '');
    _source = TextEditingController(text: widget.existing?.source ?? '');
    _currentCompany =
        TextEditingController(text: widget.existing?.currentCompany ?? '');
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    _status = widget.existing?.status ?? 'PROSPECT';
    if (!InsuranceCrmService.prospectStatuses.contains(_status)) {
      _status = 'PROSPECT';
    }
    _endDate = widget.existing?.endDate;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicleMake.dispose();
    _city.dispose();
    _source.dispose();
    _currentCompany.dispose();
    _notes.dispose();
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
    final city = _city.text.trim();
    final source = _source.text.trim();
    final currentCompany = _currentCompany.text.trim();
    final notes = _notes.text.trim();

    final allEmpty = name.isEmpty &&
        phone.isEmpty &&
        make.isEmpty &&
        city.isEmpty &&
        currentCompany.isEmpty &&
        _endDate == null;
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
      partyId: widget.existing?.partyId ?? '',
      name: name,
      phone: phone,
      status: _status,
      city: city.isEmpty ? null : city,
      source: source.isEmpty ? null : source,
      currentCompany: currentCompany.isEmpty ? null : currentCompany,
      vehicleMake: make,
      endDate: _endDate,
      lastContactAt: widget.existing?.lastContactAt,
      nextContactAt: widget.existing?.nextContactAt,
      contactResult: widget.existing?.contactResult,
      notes: notes.isEmpty ? null : notes,
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('crmLeadStatus'),
                value: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'حالة العميل المحتمل',
                  border: OutlineInputBorder(),
                ),
                items: InsuranceCrmService.prospectStatuses
                    .where((status) => status != 'CONVERTED')
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_crmStatusLabel(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadName'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _name,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'الاسم (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadPhone'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _phone,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.phone,
                decoration:
                    const InputDecoration(labelText: 'رقم الهاتف (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadCity'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _city,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'المدينة'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadVehicle'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _vehicleMake,
                textAlign: TextAlign.right,
                decoration:
                    const InputDecoration(labelText: 'نوع المركبة (اختياري)'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadCurrentCompany'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _currentCompany,
                textAlign: TextAlign.right,
                decoration:
                    const InputDecoration(labelText: 'شركة التأمين الحالية'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadSource'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _source,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'مصدر العميل (إحالة / حملة / اتصال...)',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('crmLeadNotes'),
                inputFormatters: const [YallaDigitNormalizer()],
                controller: _notes,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(labelText: 'ملاحظات'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('crmLeadExpiryPicker'),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}

String _crmStatusLabel(String status) {
  const labels = <String, String>{
    'PROSPECT': 'محتمل',
    'CONTACTED': 'تم التواصل',
    'NO_ANSWER': 'لا إجابة',
    'WHATSAPP_SENT': 'أرسل واتساب',
    'QUOTE_SENT': 'أرسل عرض',
    'INTERESTED': 'مهتم',
    'NOT_INTERESTED': 'غير مهتم',
    'FOLLOW_UP': 'متابعة',
    'CONVERTED': 'تحول لمؤمن له',
    'LOST': 'فقدت الفرصة',
    'REJECTED': 'مرفوض',
    'CLOSED': 'مغلق',
    'CANCELLED': 'ملغى',
  };
  return labels[status.trim().toUpperCase()] ?? status;
}

class _FollowUpDraft {
  const _FollowUpDraft({
    required this.status,
    required this.channel,
    this.result,
    this.notes,
    this.nextContactAt,
  });

  final String status;
  final String channel;
  final String? result;
  final String? notes;
  final DateTime? nextContactAt;
}

class _FollowUpDialog extends StatefulWidget {
  const _FollowUpDialog({
    required this.nfDate,
    required this.existing,
  });

  final DateFormat nfDate;
  final _LeadContact existing;

  @override
  State<_FollowUpDialog> createState() => _FollowUpDialogState();
}

class _FollowUpDialogState extends State<_FollowUpDialog> {
  late String _status;
  String _channel = 'PHONE';
  late final TextEditingController _result;
  late final TextEditingController _notes;
  DateTime? _nextContactAt;

  @override
  void initState() {
    super.initState();
    _status =
        InsuranceCrmService.prospectStatuses.contains(widget.existing.status)
            ? widget.existing.status
            : 'FOLLOW_UP';
    _result = TextEditingController(text: widget.existing.contactResult ?? '');
    _notes = TextEditingController();
    _nextContactAt = widget.existing.nextContactAt;
  }

  @override
  void dispose() {
    _result.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickNextContact() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextContactAt ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _nextContactAt = picked);
  }

  void _submit() {
    Navigator.of(context).pop(
      _FollowUpDraft(
        status: _status,
        channel: _channel,
        result: _result.text.trim().isEmpty ? null : _result.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        nextContactAt: _nextContactAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final next = _nextContactAt == null
        ? 'بدون موعد متابعة'
        : widget.nfDate.format(_nextContactAt!);
    return AdaptiveAlertDialog(
      title: Text('تسجيل متابعة — ${widget.existing.name ?? ''}'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('crmFollowUpStatus'),
                value: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'حالة العميل بعد التواصل',
                  border: OutlineInputBorder(),
                ),
                items: InsuranceCrmService.prospectStatuses
                    .where((status) => status != 'CONVERTED')
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_crmStatusLabel(status)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: const Key('crmFollowUpChannel'),
                value: _channel,
                decoration: const InputDecoration(
                  labelText: 'قناة التواصل',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'PHONE', child: Text('اتصال هاتفي')),
                  DropdownMenuItem(value: 'WHATSAPP', child: Text('واتساب')),
                  DropdownMenuItem(
                      value: 'EMAIL', child: Text('بريد إلكتروني')),
                  DropdownMenuItem(value: 'VISIT', child: Text('زيارة')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _channel = value);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crmFollowUpResult'),
                controller: _result,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'نتيجة التواصل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crmFollowUpNotes'),
                controller: _notes,
                maxLines: 3,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الاتصال',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('crmFollowUpDate'),
                      onPressed: _pickNextContact,
                      icon: const Icon(Icons.event_repeat),
                      label: Text(next),
                    ),
                    if (_nextContactAt != null)
                      TextButton(
                        onPressed: () => setState(() => _nextContactAt = null),
                        child: const Text('بدون موعد'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('crmFollowUpSave'),
          onPressed: _submit,
          child: const Text('حفظ المتابعة'),
        ),
      ],
    );
  }
}

class _LicenseDraft {
  const _LicenseDraft({
    required this.licenseNumber,
    required this.expiryDate,
    required this.categories,
    this.licenseType,
    this.issueDate,
    this.notes,
  });

  final String licenseNumber;
  final String? licenseType;
  final DateTime? issueDate;
  final DateTime expiryDate;
  final List<String> categories;
  final String? notes;
}

class _LicenseDialog extends StatefulWidget {
  const _LicenseDialog({
    required this.nfDate,
    this.existing,
  });

  final DateFormat nfDate;
  final InsuranceDrivingLicenseRecord? existing;

  @override
  State<_LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends State<_LicenseDialog> {
  late final TextEditingController _number;
  late final TextEditingController _type;
  late final TextEditingController _categories;
  late final TextEditingController _notes;
  DateTime? _issueDate;
  late DateTime _expiryDate;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.existing?.licenseNumber ?? '');
    _type = TextEditingController(text: widget.existing?.licenseType ?? '');
    _categories = TextEditingController(
      text: widget.existing?.categories.join(', ') ?? '',
    );
    _notes = TextEditingController(text: widget.existing?.notes ?? '');
    _issueDate = widget.existing?.issueDate;
    _expiryDate = widget.existing?.expiryDate ??
        DateTime.now().add(const Duration(days: 365));
  }

  @override
  void dispose() {
    _number.dispose();
    _type.dispose();
    _categories.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 15),
    );
  }

  Future<void> _pickIssue() async {
    final picked = await _pick(_issueDate ?? DateTime.now());
    if (picked != null) setState(() => _issueDate = picked);
  }

  Future<void> _pickExpiry() async {
    final picked = await _pick(_expiryDate);
    if (picked != null) setState(() => _expiryDate = picked);
  }

  void _submit() {
    final number = _number.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم رخصة القيادة مطلوب')),
      );
      return;
    }
    final categories = _categories.text
        .split(RegExp(r'[,،]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    Navigator.of(context).pop(
      _LicenseDraft(
        licenseNumber: number,
        licenseType: _type.text.trim().isEmpty ? null : _type.text.trim(),
        issueDate: _issueDate,
        expiryDate: _expiryDate,
        categories: categories,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveAlertDialog(
      title: const Text('رخصة القيادة'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('crmLicenseNumber'),
                controller: _number,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'رقم الرخصة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crmLicenseType'),
                controller: _type,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'نوع الرخصة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crmLicenseCategories'),
                controller: _categories,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'الفئات (B, C...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('crmLicenseNotes'),
                controller: _notes,
                maxLines: 2,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const Key('crmLicenseIssueDate'),
                    onPressed: _pickIssue,
                    icon: const Icon(Icons.event),
                    label: Text(
                      _issueDate == null
                          ? 'تاريخ الإصدار'
                          : 'الإصدار: ${widget.nfDate.format(_issueDate!)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('crmLicenseExpiryDate'),
                    onPressed: _pickExpiry,
                    icon: const Icon(Icons.event_busy),
                    label: Text(
                      'الانتهاء: ${widget.nfDate.format(_expiryDate)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: const Key('crmLicenseSave'),
          onPressed: _submit,
          child: const Text('حفظ الرخصة'),
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
  final String partyId;
  final String? name;
  final String? phone;
  final String status;
  final String? city;
  final String? source;
  final String? currentCompany;
  final String? vehicleMake;
  final DateTime? endDate;
  final DateTime? lastContactAt;
  final DateTime? nextContactAt;
  final String? contactResult;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  _LeadContact({
    required this.id,
    required this.partyId,
    required this.name,
    required this.phone,
    required this.status,
    required this.city,
    required this.source,
    required this.currentCompany,
    required this.vehicleMake,
    required this.endDate,
    required this.lastContactAt,
    required this.nextContactAt,
    required this.contactResult,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });
}
