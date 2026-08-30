// ًں“پ lib/features/insurance_agent/contacts/screens/insurance_contacts_list_screen.dart
//
// InsuranceContactsListScreen â€” UPDATED (Hamburger + Back + Right Overlay Sidebar)
// âœ… ط²ط± ظ‡ط§ظ…ط¨ط±ط¬ط± (Overlay Sidebar ظ…ظ† ط§ظ„ظٹظ…ظٹظ†) ط¹ظ„ظ‰ Desktop + Mobile
// âœ… ط³ظ‡ظ… ط±ط¬ظˆط¹ ظپظٹ AppBar
// âœ… ط¨ط§ظ‚ظٹ ط§ظ„ظ…ظٹط²ط§طھ ظƒظ…ط§ ظ‡ظٹ: Tabs 13 + Add/Edit Dialog + SharedPrefs + PDF + Filters

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';

// âœ… Sidebar
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

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

  // âœ… ظپظ„طھط±: ط¹ط±ط¶ ظپظ‚ط· ط§ظ„ظ‚ط±ظٹط¨ط© (<= 30 ظٹظˆظ…) â€” ظٹط´طھط؛ظ„ ظپظ‚ط· ظ„ظ…ظ† ظ„ط¯ظٹظ‡ظ… endDate
  bool _expiring30Only = false;

  // âœ… Sidebar overlay state
  bool _sideOpen = false;

  late final TabController _tabController;

  List<_LeadContact> _items = [];

  @override
  void initState() {
    super.initState();

    // âœ… 13 طھط¨ظˆظٹط¨: 0=ط¨ط¯ظˆظ† طھط§ط±ظٹط®, 1..12=ط§ظ„ط£ط´ظ‡ط±
    final now = DateTime.now();
    _tabController = TabController(length: 13, vsync: this);

    // ط§ظپطھط±ط§ط¶ظٹظ‹ط§ ط§ظپطھط­ ط´ظ‡ط± ط§ظ„ظٹظˆظ… (ظ„ط£ظ† 0 = ط¨ط¯ظˆظ† طھط§ط±ظٹط®)
    _tabController.index = now.month;

    // âœ… ط¥طµظ„ط§ط­ ظ…ظ‡ظ…: ط¥ط¹ط§ط¯ط© ط¨ظ†ط§ط، ط§ظ„ط´ط§ط´ط© ط¹ظ†ط¯ طھط؛ظٹظٹط± ط§ظ„طھط¨ظˆظٹط¨
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

      // âœ… طھط±طھظٹط¨ ط¹ط§ظ…:
      // 1) ط§ظ„ظ„ظٹ ط¹ظ†ط¯ظ‡ endDate ط§ظ„ط£ظ‚ط±ط¨ ط£ظˆظ„ظ‹ط§
      // 2) ط§ظ„ظ„ظٹ ط¨ط¯ظˆظ† endDate ظٹط¬ظٹ ط¢ط®ط±
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

  // tabIndex: 0 = ط¨ط¯ظˆظ† طھط§ط±ظٹط®, 1..12 = ط´ظ‡ط±
  List<_LeadContact> _itemsForTab(int tabIndex) {
    final q = _query.trim();

    final list = _items.where((e) {
      // âœ… ط¨ط­ط«
      if (!_matchesQuery(e, q)) return false;

      // âœ… طھط¨ظˆظٹط¨ ط¨ط¯ظˆظ† طھط§ط±ظٹط®
      if (tabIndex == 0) {
        return e.endDate == null;
      }

      // âœ… طھط¨ظˆظٹط¨ط§طھ ط§ظ„ط£ط´ظ‡ط±
      final d = e.endDate;
      if (d == null) return false;

      final month = tabIndex; // ظ„ط£ظ† tabIndex ظ†ظپط³ظ‡ ظ‡ظˆ ط§ظ„ط´ظ‡ط± 1..12
      if (d.month != month) return false;

      // âœ… ظپظ„طھط± ط§ظ„ظ‚ط±ظٹط¨ط© (ظٹط¹ظ…ظ„ ظپظ‚ط· ظ„ظ„ط£ط´ظ‡ط±)
      if (_expiring30Only && !_isExpiringWithin30(e)) return false;

      return true;
    }).toList();

    // طھط±طھظٹط¨ ط¯ط§ط®ظ„ ط§ظ„طھط¨ظˆظٹط¨:
    if (tabIndex == 0) {
      // ط¨ط¯ظˆظ† طھط§ط±ظٹط®: ط§ظ„ط£ط­ط¯ط« طھط­ط¯ظٹط«ظ‹ط§/ط¥ظ†ط´ط§ط،ظ‹ ط£ظˆظ„ظ‹ط§
      list.sort((a, b) {
        final bx = b.updatedAt ?? b.createdAt ?? DateTime(2000);
        final ax = a.updatedAt ?? a.createdAt ?? DateTime(2000);
        return bx.compareTo(ax);
      });
    } else {
      // ط§ظ„ط£ط´ظ‡ط±: ط§ظ„ط£ظ‚ط±ط¨ ط§ظ†طھظ‡ط§ط،ظ‹ ط£ظˆظ„ظ‹ط§
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
      const SnackBar(content: Text('âœ… طھظ… ط­ظپط¸ ط§ظ„ط²ط¨ظˆظ† ظپظٹ ظ‚ط§ط¦ظ…ط© ط§ظ„طھظˆط§طµظ„')),
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

    // ط¥ط¹ط§ط¯ط© طھط±طھظٹط¨ ط¹ط§ظ…
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
      const SnackBar(content: Text('âœ… طھظ… طھط­ط¯ظٹط« ط¨ظٹط§ظ†ط§طھ ط§ظ„ط²ط¨ظˆظ†')),
    );
  }

  Future<void> _confirmDelete(_LeadContact lead) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AdaptiveAlertDialog(
        title: const Text('ط¥ظ„ط؛ط§ط، ط§ظ„طھظˆط§طµظ„'),
        content: Text(
          'ظ…طھط£ظƒط¯ ط¨ط¯ظƒ طھط­ط°ظپ "${(lead.name ?? '').trim().isEmpty ? 'ط¨ط¯ظˆظ† ط§ط³ظ…' : lead.name!.trim()}"طں',
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
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
      const SnackBar(content: Text('ًں—‘ï¸ڈ طھظ… ط­ط°ظپ ط§ظ„ط³ط¬ظ„')),
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
        const SnackBar(content: Text('ظ„ط§ ظٹظˆط¬ط¯ ط¨ظٹط§ظ†ط§طھ ظ„ظ„ط·ط¨ط§ط¹ط© ظپظٹ ظ‡ط°ط§ ط§ظ„ط¹ط±ط¶')),
      );
      return;
    }

    final title = tabIndex == 0
        ? 'ظ‚ط§ط¦ظ…ط© ط§ظ„طھظˆط§طµظ„ â€” ط¨ط¯ظˆظ† طھط§ط±ظٹط® ط§ظ†طھظ‡ط§ط،'
        : 'ظ‚ط§ط¦ظ…ط© ط§ظ„طھظˆط§طµظ„ â€” ط´ظ‡ط± $tabIndex';

    final headers = <String>[
      'ط§ظ„ط§ط³ظ…',
      'ط§ظ„ظ‡ط§طھظپ',
      'ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©',
      'ط§ظ†طھظ‡ط§ط، ط§ظ„طھط£ظ…ظٹظ†',
      'ط§ظ„ط­ط§ظ„ط©',
    ];

    String statusText(_LeadContact e) {
      final d = e.endDate;
      if (d == null) return 'ط؛ظٹط± ظ…ط¹ط±ظˆظپ';
      final left = _daysLeft(d);
      if (left < 0) return 'ظ…ظ†طھظ‡ظٹط©';
      if (left <= 30) return 'ظ…طھط¨ظ‚ظٹ $left ظٹظˆظ…';
      return 'ط³ط§ط±ظٹط©';
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
        const SnackBar(content: Text('âœ… طھظ… ط¥ظ†ط´ط§ط، PDF ظˆظپطھط­ظ‡')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('â‌Œ ظپط´ظ„ ط¥ظ†ط´ط§ط، PDF: $e')),
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

    // âœ… ط¹ط±ط¶ ط§ظ„ط³ط§ظٹط¯ط¨ط§ط±
    final sideW = (w >= 1200) ? 320.0 : 300.0;

    final tabIndex = _tabController.index;
    final items = _itemsForTab(tabIndex);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'ظ‚ط§ط¦ظ…ط© ط§ظ„طھظˆط§طµظ„',
          style: TextStyle(color: Colors.white),
        ),

        // âœ… ط³ظ‡ظ… ط§ظ„ط±ط¬ظˆط¹
        leading: IconButton(
          tooltip: 'ط±ط¬ظˆط¹',
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('â„¹ï¸ڈ ظ„ط§ ظٹظˆط¬ط¯ طµظپط­ط© ط³ط§ط¨ظ‚ط© ظ„ظ„ط±ط¬ظˆط¹')),
              );
            }
          },
        ),

        actions: [
          IconButton(
            tooltip: 'طھطµط¯ظٹط± PDF (ط§ظ„ط¹ط±ط¶ ط§ظ„ط­ط§ظ„ظٹ)',
            onPressed: _busy ? null : _exportCurrentTabPdf,
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
          ),
          IconButton(
            tooltip: 'طھط­ط¯ظٹط«',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
          IconButton(
            tooltip: 'ط¥ط¶ط§ظپط© ط²ط¨ظˆظ† ظ…ط­طھظ…ظ„',
            onPressed: _busy ? null : _openAddDialog,
            icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
          ),

          // âœ… ط§ظ„ظ‡ط§ظ…ط¨ط±ط¬ط± ط¯ط§ط¦ظ…ط§ظ‹
          IconButton(
            tooltip: _sideOpen ? 'ط¥ط؛ظ„ط§ظ‚ ط§ظ„ظ‚ط§ط¦ظ…ط©' : 'ط§ظ„ظ‚ط§ط¦ظ…ط©',
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
                const Tab(child: Text('ط¨ط¯ظˆظ† طھط§ط±ظٹط®')),
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
        label: const Text('ط¥ط¶ط§ظپط©', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          // ط§ظ„ظ…ط­طھظˆظ‰ ط§ظ„ط£ط³ط§ط³ظٹ
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

          // âœ… Sidebar Overlay
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
              ? 'ط§ظ„ظ…ط¹ط±ظˆط¶: $shown (ط¨ط¯ظˆظ† طھط§ط±ظٹط®)'
              : 'ط§ظ„ظ…ط¹ط±ظˆط¶: $shown (ط§ظ„ط´ظ‡ط± $tabIndex)',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const Spacer(),
        Tooltip(
          message: isNoDateTab
              ? 'ظپظ„طھط± â‰¤30 ظٹظˆظ… ظٹط­طھط§ط¬ طھط§ط±ظٹط® ط§ظ†طھظ‡ط§ط،'
              : 'ط¹ط±ط¶ ظپظ‚ط· ط§ظ„طھظٹ طھظ†طھظ‡ظٹ ط®ظ„ط§ظ„ 30 ظٹظˆظ…',
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
                          ? 'â‰¤ 30 ظٹظˆظ…'
                          : 'â‰¤ 30 ظٹظˆظ… ($expiringCountInTab)',
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
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ط¨ط­ط« ط¨ط§ظ„ط§ط³ظ… / ط§ظ„ظ‡ط§طھظپ / ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©',
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
                'ظ‡ط°ط§ ط§ظ„طھط¨ظˆظٹط¨ ظ„ظ„ط²ط¨ط§ط¦ظ† ط¨ط¯ظˆظ† طھط§ط±ظٹط® ط§ظ†طھظ‡ط§ط،طŒ ظ„ط°ظ„ظƒ طھظ†ط¨ظٹظ‡ط§طھ â‰¤30 ظٹظˆظ… ظ„ط§ طھظ†ط·ط¨ظ‚ ظ‡ظ†ط§.',
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
          border: Border.all(color: Colors.green.shade200),
          color: Colors.green.withOpacity(0.08),
        ),
        child: AdaptiveRow(
          children: [
            Icon(Icons.verified, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'âœ… ظ„ط§ ظٹظˆط¬ط¯ ظ…ظ„ظپط§طھ طھظ†طھظ‡ظٹ ط®ظ„ط§ظ„ 30 ظٹظˆظ… ظپظٹ ظ‡ط°ط§ ط§ظ„ط´ظ‡ط± (ط­ط³ط¨ ط§ظ„ط¨ط­ط« ط§ظ„ط­ط§ظ„ظٹ).',
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
              'âڑ ï¸ڈ طھظ†ط¨ظٹظ‡: ظٹظˆط¬ط¯ $count ظ…ظ„ظپ/ظ…ظ„ظپط§طھ طھظ†طھظ‡ظٹ ط®ظ„ط§ظ„ 30 ظٹظˆظ… ظپظٹ ظ‡ط°ط§ ط§ظ„ط´ظ‡ط± (ط­ط³ط¨ ط§ظ„ط¨ط­ط« ط§ظ„ط­ط§ظ„ظٹ).',
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
                Text(expiring30Only ? 'ط¥ظ„ط؛ط§ط، ظپظ„طھط± ط§ظ„ظ‚ط±ظٹط¨ط©' : 'ط¹ط±ط¶ ط§ظ„ظ‚ط±ظٹط¨ط© ظپظ‚ط·'),
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
              'ظ„ط§ ظٹظˆط¬ط¯ ط²ط¨ط§ط¦ظ† ظپظٹ ظ‡ط°ط§ ط§ظ„ط¹ط±ط¶.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'ط¬ط±ظ‘ط¨ ط§ظ„ط¨ط­ط« ط£ظˆ طھط؛ظٹظٹط± ط§ظ„طھط¨ظˆظٹط¨طŒ ط£ظˆ ط£ط¶ظپ ط²ط¨ظˆظ† ط¬ط¯ظٹط¯.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('ط¥ط¶ط§ظپط© ط²ط¨ظˆظ†'),
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
    return Colors.green.shade700;
  }

  String _statusText(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return 'ط؛ظٹط± ظ…ط¹ط±ظˆظپ';
    final left = daysLeft(d);
    if (left < 0) return 'ظ…ظ†طھظ‡ظٹط©';
    if (left <= 30) return 'ظ…طھط¨ظ‚ظٹ $left ظٹظˆظ…';
    return 'ط³ط§ط±ظٹط©';
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
              DataColumn(label: Text('ط§ظ„ط§ط³ظ…')),
              DataColumn(label: Text('ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ')),
              DataColumn(label: Text('ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©')),
              DataColumn(label: Text('ط§ظ†طھظ‡ط§ط، ط§ظ„طھط£ظ…ظٹظ†')),
              DataColumn(label: Text('ط§ظ„ط­ط§ظ„ط©')),
              DataColumn(label: Text('ط¥ط¬ط±ط§ط،ط§طھ')),
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
                          label: const Text('طھط£ظ…ظٹظ† ط§ظ„ظ…ط±ظƒط¨ط©'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'طھط¹ط¯ظٹظ„',
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
    return Colors.green.shade700;
  }

  String _statusText(_LeadContact e) {
    final d = e.endDate;
    if (d == null) return 'ط؛ظٹط± ظ…ط¹ط±ظˆظپ';
    final left = daysLeft(d);
    if (left < 0) return 'ظ…ظ†طھظ‡ظٹط©';
    if (left <= 30) return 'ظ…طھط¨ظ‚ظٹ $left ظٹظˆظ…';
    return 'ط³ط§ط±ظٹط©';
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
                    tooltip: 'طھط¹ط¯ظٹظ„',
                    onPressed: () => onEdit(e),
                    icon:
                        const Icon(Icons.edit_outlined, color: Colors.blueGrey),
                  ),
                  const Spacer(),
                  Text(
                    (e.name ?? '').trim().isEmpty ? 'ط¨ط¯ظˆظ† ط§ط³ظ…' : e.name!.trim(),
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
                  Text('ط§ظ„ط­ط§ظ„ط©', style: TextStyle(color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(height: 10),
              _kv('ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ', _dashIfEmpty(e.phone)),
              _kv('ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط©', _dashIfEmpty(e.vehicleMake)),
              _kv('ط§ظ†طھظ‡ط§ط، ط§ظ„طھط£ظ…ظٹظ†', end),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onInsure(e),
                  icon:
                      const Icon(Icons.verified_user, color: AppColors.primary),
                  label: const Text('طھط£ظ…ظٹظ† ط§ظ„ظ…ط±ظƒط¨ط©'),
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
            content: Text('âڑ ï¸ڈ ط£ط¯ط®ظ„ ط¹ظ„ظ‰ ط§ظ„ط£ظ‚ظ„ ظ…ط¹ظ„ظˆظ…ط© ظˆط§ط­ط¯ط© ظ‚ط¨ظ„ ط§ظ„ط­ظپط¸')),
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
        ? 'ط¨ط¯ظˆظ† طھط§ط±ظٹط® ط§ظ†طھظ‡ط§ط،'
        : widget.nfDate.format(_endDate!);

    return AdaptiveAlertDialog(
      title: Text(isEdit ? 'طھط¹ط¯ظٹظ„ ط²ط¨ظˆظ† ظ…ط­طھظ…ظ„' : 'ط¥ط¶ط§ظپط© ط²ط¨ظˆظ† ظ…ط­طھظ…ظ„'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'ط§ظ„ط§ط³ظ… (ط§ط®طھظٹط§ط±ظٹ)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'ط±ظ‚ظ… ط§ظ„ظ‡ط§طھظپ (ط§ط®طھظٹط§ط±ظٹ)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _vehicleMake,
              textAlign: TextAlign.right,
              decoration:
                  const InputDecoration(labelText: 'ظ†ظˆط¹ ط§ظ„ظ…ط±ظƒط¨ط© (ط§ط®طھظٹط§ط±ظٹ)'),
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
                      label: const Text('ظ…ط³ط­ ط§ظ„طھط§ط±ظٹط®'),
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
          child: const Text('ط¥ظ„ط؛ط§ط،'),
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
    DateTime? _dt(String? s) =>
        (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

    return _LeadContact(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      phone: (j['phone'] ?? '').toString(),
      vehicleMake: (j['vehicleMake'] ?? '').toString(),
      endDate: _dt(j['endDate']?.toString()),
      createdAt: _dt(j['createdAt']?.toString()),
      updatedAt: _dt(j['updatedAt']?.toString()),
    );
  }
}

