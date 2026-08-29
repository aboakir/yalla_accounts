import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';

import '../providers/insurance_calculator_provider.dart';
import '../widgets/category_selector.dart';
import '../widgets/dynamic_inputs_form.dart';
import '../widgets/result_card.dart';
import '../widgets/discount_card.dart';

class InsuranceCalculatorScreen extends StatelessWidget {
  const InsuranceCalculatorScreen({super.key});

  // Responsive breakpoints
  static const double wideBp = 1200;
  static const double mediumBp = 850;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InsuranceCalculatorProvider(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;

          final bool isWide = w >= wideBp;
          final bool isMedium = w >= mediumBp && w < wideBp;
          final bool isNarrow = w < mediumBp;

          return Scaffold(
            backgroundColor: AppColors.scaffoldBg,
            appBar: AppBar(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textLight,
              elevation: 0,
              title: const Text(
                'حاسبة التأمين',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'إعادة ضبط',
                  onPressed: () =>
                      context.read<InsuranceCalculatorProvider>().reset(),
                ),
                const SizedBox(width: 8),
              ],
            ),

            // ✅ Mobile/Tablet: Drawer on LEFT
            drawer: isNarrow ? const _SidebarDrawer() : null,

            // ✅ Desktop/large: Sidebar fixed on LEFT
            body: _ResponsiveBody(
              isWide: isWide,
              isMedium: isMedium,
              isNarrow: isNarrow,
            ),
          );
        },
      ),
    );
  }
}

/* ----------------------- Responsive Body ----------------------- */

class _ResponsiveBody extends StatelessWidget {
  final bool isWide;
  final bool isMedium;
  final bool isNarrow;

  const _ResponsiveBody({
    required this.isWide,
    required this.isMedium,
    required this.isNarrow,
  });

  @override
  Widget build(BuildContext context) {
    // Desktop styles: show fixed sidebar when not narrow (desktop/tablet wide)
    final bool showFixedSidebar = !isNarrow;

    return Row(
      children: [
        if (showFixedSidebar)
          const SizedBox(
            width: 300,
            child: _DesktopSidebar(),
          ),
        Expanded(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  // ✅ dynamic max width for better spacing on large screens
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 1400 : (isMedium ? 1100 : 700),
                  ),
                  child: _ResponsiveContent(
                    isWide: isWide,
                    isMedium: isMedium,
                    isNarrow: isNarrow,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ----------------------- Sidebar ----------------------- */

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBackground,
      child: const SafeArea(
        child: YallaSidebar(),
      ),
    );
  }
}

class _SidebarDrawer extends StatelessWidget {
  const _SidebarDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.cardBackground,
      child: const SafeArea(
        child: YallaSidebar(),
      ),
    );
  }
}

/* ----------------------- Content ----------------------- */

class _ResponsiveContent extends StatelessWidget {
  final bool isWide;
  final bool isMedium;
  final bool isNarrow;

  const _ResponsiveContent({
    required this.isWide,
    required this.isMedium,
    required this.isNarrow,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InsuranceCalculatorProvider>();
    final canCalculate = provider.input != null && provider.input!.isValid;

    // Wide/Medium => 2 columns
    if (!isNarrow) {
      final int leftFlex = isWide ? 7 : 8;
      final int rightFlex = isWide ? 5 : 6;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ HeaderCard now becomes "help card" and hides after result
          if (!provider.hasResult) const _HeaderHelpCard(),
          if (!provider.hasResult) const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Inputs
              Expanded(
                flex: leftFlex,
                child: Column(
                  children: [
                    const _SectionCard(
                      title: 'نوع المركبة',
                      child: CategorySelector(),
                    ),
                    const SizedBox(height: 12),
                    const _SectionCard(
                      title: 'بيانات المركبة',
                      child: DynamicInputsForm(),
                    ),
                    const SizedBox(height: 12),
                    _ActionBar(
                      enabled: canCalculate,
                      onCalculate: provider.calculate,
                      onReset: provider.reset,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Result / Hint
              Expanded(
                flex: rightFlex,
                child: provider.hasResult
                    ? Column(
                        children: const [
                          _SectionCard(
                            title: 'النتيجة',
                            child: ResultCard(),
                          ),
                          SizedBox(height: 12),
                          _SectionCard(
                            title: 'نسبة الخصم',
                            child: DiscountCard(),
                          ),
                        ],
                      )
                    : const _HintCard(),
              ),
            ],
          ),
        ],
      );
    }

    // Narrow => 1 column stack
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ✅ Same behavior on mobile: show help only before result
        if (!provider.hasResult) const _HeaderHelpCard(),
        if (!provider.hasResult) const SizedBox(height: 12),

        const _SectionCard(
          title: 'نوع المركبة',
          child: CategorySelector(),
        ),
        const SizedBox(height: 12),
        const _SectionCard(
          title: 'بيانات المركبة',
          child: DynamicInputsForm(),
        ),
        const SizedBox(height: 12),
        _ActionBar(
          enabled: canCalculate,
          onCalculate: provider.calculate,
          onReset: provider.reset,
        ),
        const SizedBox(height: 16),
        provider.hasResult
            ? Column(
                children: const [
                  _SectionCard(
                    title: 'النتيجة',
                    child: ResultCard(),
                  ),
                  SizedBox(height: 12),
                  _SectionCard(
                    title: 'نسبة الخصم',
                    child: DiscountCard(),
                  ),
                ],
              )
            : const _HintCard(),
      ],
    );
  }
}

/* ----------------------- UI Components ----------------------- */

/// ✅ NEW: header without duplicated title
class _HeaderHelpCard extends StatelessWidget {
  const _HeaderHelpCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.lightGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shield, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'اختر نوع المركبة وأدخل البيانات ثم اضغط "احسب التأمين".',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onCalculate;
  final VoidCallback onReset;

  const _ActionBar({
    required this.enabled,
    required this.onCalculate,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Wrap(
        alignment: WrapAlignment.end,
        runSpacing: 10,
        spacing: 10,
        children: [
          OutlinedButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة ضبط'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondary,
              side: BorderSide(color: AppColors.lightGrey),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.calculate),
            label: const Text('احسب التأمين'),
            onPressed: enabled ? onCalculate : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textLight,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: const [
          Icon(Icons.info_outline, color: AppColors.secondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'اختر نوع المركبة وأدخل البيانات ثم اضغط "احسب التأمين".',
              textAlign: TextAlign.right,
              style: TextStyle(color: AppColors.secondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
