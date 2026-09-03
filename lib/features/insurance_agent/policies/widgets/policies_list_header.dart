// 📁 lib/features/insurance_agent/policies/widgets/policies_list_header.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import '../utils/policy_date_utils.dart';
import 'package:yalla_accounts/shared/widgets/adaptive_layout.dart';

import 'package:yalla_accounts/core/utils/yalla_digits.dart';

class PoliciesListHeader extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final List<String> companies;

  final TabController tabController;

  final bool loading;
  final bool monthBusy;

  // Filters state
  final String query;
  final String? companyFilter;
  final bool vipOnly;
  final bool expiredOnly;
  final bool expiringSoonOnly;

  // NEW quick buttons state
  final bool expiring30Only;

  // Formatters
  final NumberFormat nfInt;

  // Actions
  final VoidCallback onReload;
  final VoidCallback onAdd;

  // NEW actions
  final VoidCallback onToggleExpiring30;
  final VoidCallback onOpenArchive;
  final VoidCallback onExportPdf;

  // Filters callbacks
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCompanyChanged;
  final ValueChanged<bool> onVipOnlyChanged;
  final ValueChanged<bool> onExpiredOnlyChanged;
  final ValueChanged<bool> onExpiringSoonOnlyChanged;
  final VoidCallback onClearFilters;

  const PoliciesListHeader({
    super.key,
    required this.items,
    required this.companies,
    required this.tabController,
    required this.loading,
    required this.monthBusy,
    required this.query,
    required this.companyFilter,
    required this.vipOnly,
    required this.expiredOnly,
    required this.expiringSoonOnly,
    required this.expiring30Only,
    required this.nfInt,
    required this.onReload,
    required this.onAdd,
    required this.onToggleExpiring30,
    required this.onOpenArchive,
    required this.onExportPdf,
    required this.onSearchChanged,
    required this.onCompanyChanged,
    required this.onVipOnlyChanged,
    required this.onExpiredOnlyChanged,
    required this.onExpiringSoonOnlyChanged,
    required this.onClearFilters,
  });

  String _monthLabel(int index) {
    final m = index + 1;
    return m.toString().padLeft(2, '0');
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.18)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            color: Color(0x12000000),
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: AdaptiveRow(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withOpacity(0.20)),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------------
  // ✅ Quick Action Button (filled + colored + shadow) — not "plain"
  Widget _quickBtn({
    required String text,
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
    bool active = false,
    bool compactLabel = false,
  }) {
    final disabled = onTap == null;

    final bg = disabled
        ? Colors.grey.shade200
        : (active ? color : color.withOpacity(0.12));

    final border = disabled
        ? Colors.grey.shade300
        : (active ? color.withOpacity(0.75) : color.withOpacity(0.25));

    final fg =
        disabled ? Colors.grey.shade500 : (active ? Colors.white : color);

    return Tooltip(
      message: text,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            boxShadow: disabled
                ? const []
                : [
                    BoxShadow(
                      blurRadius: active ? 14 : 10,
                      color: color.withOpacity(active ? 0.25 : 0.18),
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: AdaptiveRow(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                compactLabel ? (text.length > 6 ? 'PDF' : text) : text,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              if (active && !disabled) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthTabsBar(bool isDisabled) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black12),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            color: Color(0x12000000),
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (_, c) {
          final narrow = c.maxWidth < 980;

          return AdaptiveRow(
            children: [
              // Month tabs
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TabBar(
                    controller: tabController,
                    isScrollable: true,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w900),
                    unselectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.w700),
                    indicator: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.25),
                      ),
                    ),
                    labelColor: AppColors.primary,
                    unselectedLabelColor: Colors.grey.shade800,
                    tabs: List.generate(
                      12,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Tab(text: _monthLabel(i)),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // Buttons group (right side)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AdaptiveRow(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _quickBtn(
                      text: 'تنتهي خلال 30 يوم',
                      icon: Icons.schedule,
                      onTap: isDisabled ? null : onToggleExpiring30,
                      active: expiring30Only,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    _quickBtn(
                      text: 'أرشيف',
                      icon: Icons.archive_outlined,
                      onTap: isDisabled ? null : onOpenArchive,
                      color: const Color(0xFF5B5BD6), // بنفسجي مميز
                    ),
                    const SizedBox(width: 10),
                    _quickBtn(
                      text: narrow ? 'PDF' : 'تصدير PDF',
                      icon: Icons.picture_as_pdf,
                      onTap: isDisabled ? null : onExportPdf,
                      compactLabel: narrow,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = items.length;
    final vipCount = items.where((r) => (r['is_vip'] ?? 0) == 1).length;
    final expiredCount = items.where(PolicyDateUtils.isExpiredPolicy).length;
    final soonCount = items
        .where((r) => PolicyDateUtils.isExpiringSoonPolicy(r, days: 12))
        .length;

    final monthIndex = tabController.index;
    final monthText = _monthLabel(monthIndex);

    final isDisabled = loading || monthBusy;

    final searchField = TextField(
      inputFormatters: const [YallaDigitNormalizer()],
      textAlign: TextAlign.right,
      decoration: InputDecoration(
        hintText: 'بحث: رقم مركبة / اسم / هاتف / شركة',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onChanged: onSearchChanged,
    );

    final companyDrop = DropdownButtonFormField<String?>(
      value: companyFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'الشركة',
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('كل الشركات'),
        ),
        ...companies.map(
          (c) => DropdownMenuItem<String?>(
            value: c,
            child: Text(c),
          ),
        ),
      ],
      onChanged: (v) => onCompanyChanged(v),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AdaptiveRow(
          children: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: isDisabled ? null : onReload,
              icon: const Icon(Icons.refresh),
            ),
            const Spacer(),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: isDisabled ? null : onAdd,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'إضافة بوليصة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'End Month: $monthText',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // KPIs
        SizedBox(
          height: 96,
          child: LayoutBuilder(
            builder: (_, c) {
              final w = c.maxWidth;
              final cardW = (w / 4).clamp(220.0, 320.0);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                physics: const BouncingScrollPhysics(),
                child: AdaptiveRow(
                  children: [
                    SizedBox(
                      width: cardW,
                      child: _kpiCard(
                        title: 'إجمالي بوالص الشهر',
                        value: nfInt.format(total),
                        icon: Icons.policy,
                        accent: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: cardW,
                      child: _kpiCard(
                        title: 'VIP',
                        value: nfInt.format(vipCount),
                        icon: Icons.star,
                        accent: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: cardW,
                      child: _kpiCard(
                        title: 'منتهية',
                        value: nfInt.format(expiredCount),
                        icon: Icons.cancel,
                        accent: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: cardW,
                      child: _kpiCard(
                        title: 'تنتهي خلال 12 يوم',
                        value: nfInt.format(soonCount),
                        icon: Icons.notifications_active,
                        accent: Colors.orange,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 14),

        // ✅ Month bar + 3 colored buttons
        _buildMonthTabsBar(isDisabled),

        const SizedBox(height: 14),

        // Filters container (same as before)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                blurRadius: 14,
                color: Color(0x12000000),
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LayoutBuilder(
                builder: (_, c2) {
                  final isNarrow = c2.maxWidth < 900;

                  if (isNarrow) {
                    return Column(
                      children: [
                        SizedBox(width: double.infinity, child: searchField),
                        const SizedBox(height: 12),
                        SizedBox(width: double.infinity, child: companyDrop),
                      ],
                    );
                  }

                  return AdaptiveRow(
                    children: [
                      SizedBox(width: 320, child: companyDrop),
                      const SizedBox(width: 12),
                      Expanded(child: searchField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilterChip(
                    label: const Text('VIP فقط'),
                    selected: vipOnly,
                    onSelected: onVipOnlyChanged,
                  ),
                  FilterChip(
                    label: const Text('منتهية'),
                    selected: expiredOnly,
                    onSelected: onExpiredOnlyChanged,
                  ),
                  FilterChip(
                    label: const Text('تنتهي خلال 12 يوم'),
                    selected: expiringSoonOnly,
                    onSelected: onExpiringSoonOnlyChanged,
                  ),
                  TextButton.icon(
                    onPressed: onClearFilters,
                    icon: const Icon(Icons.clear),
                    label: const Text('مسح الفلاتر'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
