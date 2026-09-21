import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart';
import 'package:yalla_accounts/core/design/yalla_components.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

class InsuranceAgentHomeScreen extends StatefulWidget {
  const InsuranceAgentHomeScreen({super.key});

  @override
  State<InsuranceAgentHomeScreen> createState() =>
      _InsuranceAgentHomeScreenState();
}

class _InsuranceAgentHomeScreenState extends State<InsuranceAgentHomeScreen> {
  int _selectedTab = 0;

  static const _tabs = <String>[
    'الوثائق',
    'التجديدات',
    'المطالبات',
    'الشركات',
  ];

  Future<void> _open(String route) async {
    await AppRoutes.pushNamedSafe(context, route);
  }

  PreferredSizeWidget _appBar(bool isDesktop) {
    return AppBar(
      automaticallyImplyLeading: !isDesktop,
      leading: isDesktop
          ? null
          : Builder(
              builder: (headerContext) => IconButton(
                tooltip: 'القائمة',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(headerContext).openDrawer(),
              ),
            ),
      backgroundColor: YallaColors.brand,
      foregroundColor: YallaColors.surface,
      surfaceTintColor: Colors.transparent,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'التأمين',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            'الوثائق والتجديدات والمطالبات',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'حاسبة التأمين',
          onPressed: () => _open(AppRoutes.insuranceAgentCalculator),
          icon: const Icon(Icons.calculate_outlined),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _content(bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageHeader(
          onAddPolicy: () => _open(AppRoutes.insuranceAgentAddNew),
          onCalculator: () => _open(AppRoutes.insuranceAgentCalculator),
        ),
        const SizedBox(height: YallaSpacing.lg),
        const _MetricsGrid(),
        const SizedBox(height: YallaSpacing.lg),
        _QuickActions(
          onAddPolicy: () => _open(AppRoutes.insuranceAgentAddNew),
          onCalculator: () => _open(AppRoutes.insuranceAgentCalculator),
          onPolicies: () => _open(AppRoutes.insurancePoliciesList),
          onContacts: () => _open(AppRoutes.insuranceAgentContacts),
        ),
        const SizedBox(height: YallaSpacing.lg),
        YallaSurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TabsBar(
                labels: _tabs,
                selectedIndex: _selectedTab,
                onSelected: (index) => setState(() => _selectedTab = index),
              ),
              const Divider(height: 1, color: YallaColors.border),
              AnimatedSwitcher(
                duration: YallaDurations.normal,
                child: _TabBody(
                  key: ValueKey(_selectedTab),
                  index: _selectedTab,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = YallaBreakpoints.isDesktop(context);

    final page = Scaffold(
      drawer: isDesktop
          ? null
          : const Drawer(
              child: SafeArea(
                child: YallaSidebar(
                  currentRoute: AppRoutes.insuranceAgentHome,
                ),
              ),
            ),
      appBar: _appBar(isDesktop),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 28 : 16,
            isDesktop ? 24 : 16,
            isDesktop ? 28 : 16,
            isDesktop ? 36 : 28,
          ),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isDesktop ? 1360 : 760,
                ),
                child: _content(isDesktop),
              ),
            ),
          ],
        ),
      ),
    );

    final shell = isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                width: 300,
                child: YallaSidebar(
                  currentRoute: AppRoutes.insuranceAgentHome,
                ),
              ),
              Expanded(child: page),
            ],
          )
        : page;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.light,
          scaffoldBackgroundColor: YallaColors.canvas,
          textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'DashboardArabic',
              'DashboardSymbols',
            ],
          ),
        ),
        child: shell,
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.onAddPolicy,
    required this.onCalculator,
  });

  final VoidCallback onAddPolicy;
  final VoidCallback onCalculator;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مركز التأمين',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: YallaColors.text,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'كل ما يحتاجه وكيل التأمين في شاشة واحدة مختصرة.',
              style: TextStyle(color: YallaColors.textMuted),
            ),
          ],
        );

        final actions = Wrap(
          spacing: YallaSpacing.sm,
          runSpacing: YallaSpacing.sm,
          children: [
            FilledButton.icon(
              onPressed: onAddPolicy,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة تأمين'),
            ),
            OutlinedButton.icon(
              onPressed: onCalculator,
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('الحاسبة'),
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: YallaSpacing.md),
              actions,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            actions,
          ],
        );
      },
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid();
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1050
            ? 4
            : constraints.maxWidth >= 600
                ? 2
                : 1;
        final gap = YallaSpacing.md;
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _MetricCard(
              width: width,
              icon: Icons.verified_user_outlined,
              title: 'الوثائق السارية',
              value: '0',
              tone: YallaColors.brand,
            ),
            _MetricCard(
              width: width,
              icon: Icons.event_repeat_outlined,
              title: 'تنتهي خلال 30 يوم',
              value: '0',
              tone: YallaColors.warning,
            ),
            _MetricCard(
              width: width,
              icon: Icons.account_balance_wallet_outlined,
              title: 'أقساط غير محصلة',
              value: '0',
              tone: YallaColors.brand,
            ),
            _MetricCard(
              width: width,
              icon: Icons.car_crash_outlined,
              title: 'مطالبات مفتوحة',
              value: '0',
              tone: YallaColors.danger,
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.value,
    required this.tone,
  });

  final double width;
  final IconData icon;
  final String title;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: YallaSurfaceCard(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.10),
                borderRadius: BorderRadius.circular(YallaRadii.compact),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: tone, size: 24),
            ),
            const SizedBox(width: YallaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: YallaColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: YallaColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddPolicy,
    required this.onCalculator,
    required this.onPolicies,
    required this.onContacts,
  });

  final VoidCallback onAddPolicy;
  final VoidCallback onCalculator;
  final VoidCallback onPolicies;
  final VoidCallback onContacts;
  @override
  Widget build(BuildContext context) {
    final actions = <({IconData icon, String label, VoidCallback onTap})>[
      (
        icon: Icons.add_circle_outline,
        label: 'إضافة تأمين',
        onTap: onAddPolicy,
      ),
      (
        icon: Icons.calculate_outlined,
        label: 'حاسبة التأمين',
        onTap: onCalculator,
      ),
      (
        icon: Icons.list_alt_outlined,
        label: 'قائمة التأمينات',
        onTap: onPolicies,
      ),
      (
        icon: Icons.contacts_outlined,
        label: 'جهات الاتصال',
        onTap: onContacts,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 4 : 2;
        final gap = YallaSpacing.sm;
        final width = (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: actions
              .map(
                (action) => SizedBox(
                  width: width,
                  child: OutlinedButton.icon(
                    onPressed: action.onTap,
                    icon: Icon(action.icon),
                    label: Text(action.label),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: YallaColors.surface,
                      foregroundColor: YallaColors.text,
                      side: const BorderSide(color: YallaColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(YallaRadii.control),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _TabsBar extends StatelessWidget {
  const _TabsBar({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelected(index),
            child: Container(
              constraints: const BoxConstraints(minWidth: 132),
              padding: const EdgeInsets.symmetric(
                horizontal: YallaSpacing.lg,
                vertical: 17,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? YallaColors.brand : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                labels[index],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? YallaColors.brand : YallaColors.textMuted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({
    super.key,
    required this.index,
  });

  final int index;
  @override
  Widget build(BuildContext context) {
    if (index == 0) {
      return const _PoliciesPanel();
    }
    if (index == 1) {
      return const _EmptyPanel(
        icon: Icons.event_repeat_outlined,
        title: 'التجديدات',
        message: 'ستظهر هنا الوثائق القريبة من تاريخ الانتهاء.',
      );
    }
    if (index == 2) {
      return const _EmptyPanel(
        icon: Icons.car_crash_outlined,
        title: 'المطالبات',
        message: 'ستظهر هنا المطالبات المفتوحة وحالة متابعتها.',
      );
    }
    return const _EmptyPanel(
      icon: Icons.apartment_outlined,
      title: 'شركات التأمين',
      message: 'ستظهر هنا الشركات والأرصدة والتسويات المرتبطة بها.',
    );
  }
}

class _PoliciesPanel extends StatelessWidget {
  const _PoliciesPanel();

  @override
  Widget build(BuildContext context) {
    const headers = <String>[
      'العميل',
      'المركبة',
      'شركة التأمين',
      'تاريخ الانتهاء',
      'القسط',
      'الحالة',
    ];

    return Padding(
      padding: const EdgeInsets.all(YallaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'بحث باسم العميل، رقم المركبة أو الوثيقة',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: YallaColors.canvas,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YallaRadii.control),
                borderSide: const BorderSide(color: YallaColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(YallaRadii.control),
                borderSide: const BorderSide(color: YallaColors.border),
              ),
            ),
          ),
          const SizedBox(height: YallaSpacing.md),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: YallaSpacing.md,
                  vertical: YallaSpacing.sm,
                ),
                decoration: const BoxDecoration(
                  color: YallaColors.canvas,
                  border: Border(
                    bottom: BorderSide(color: YallaColors.border),
                  ),
                ),
                child: Row(
                  children: headers
                      .map(
                        (header) => Expanded(
                          child: Text(
                            header,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: YallaColors.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(
                height: 150,
                child: Center(
                  child: _CompactEmptyState(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 34,
          color: YallaColors.textMuted,
        ),
        SizedBox(height: 8),
        Text(
          'لا توجد وثائق معروضة حاليًا',
          style: TextStyle(
            color: YallaColors.text,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(YallaSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: YallaColors.brand),
              const SizedBox(height: YallaSpacing.sm),
              Text(
                title,
                style: const TextStyle(
                  color: YallaColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: YallaColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
