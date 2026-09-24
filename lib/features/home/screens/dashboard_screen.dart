import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_breakpoints.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/experience/app_experience_profile.dart';
import 'package:yalla_accounts/core/experience/app_experience_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
import 'package:yalla_accounts/features/notifications/widgets/notification_bell_button.dart';
import 'package:yalla_accounts/features/settings/widgets/weekly_backup_guardian_dialog.dart';
import '../services/daily_dashboard_service.dart';
import '../widgets/daily_dashboard_content.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DailyDashboardData? _data;
  DashboardPeriod _period = DashboardPeriod.today;
  AppExperienceProfile _profile = AppExperienceProfile.defaults;
  DateTime? _customFrom;
  DateTime? _customTo;
  bool _loading = true;
  bool _error = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WeeklyBackupGuardianDialog.maybeShow(context);
    });
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final profile = await AppExperienceService.load(force: true);
      final data = await DailyDashboardService.load(
        _period,
        customFrom: _customFrom,
        customTo: _customTo,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _profile = profile;
        _data = data;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _selectPeriod(DashboardPeriod period) async {
    if (period == DashboardPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
        initialDateRange: _customFrom != null && _customTo != null
            ? DateTimeRange(start: _customFrom!, end: _customTo!)
            : DateTimeRange(start: now, end: now),
      );
      if (range == null || !mounted) return;
      _customFrom = range.start;
      _customTo = range.end;
    }
    setState(() => _period = period);
    await _load();
  }

  Future<void> _open(String route, String? repairId) async {
    try {
      if (repairId != null) {
        final repair = await RepairDatabaseService.getRepairById(repairId);
        if (!mounted) return;
        if (repair == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الملف غير متاح؛ تم تحديث الملخص.')),
          );
        } else {
          await Navigator.pushNamed(
            context,
            AppRoutes.repairDetail,
            arguments: repair,
          );
        }
      } else {
        await AppRoutes.pushNamedSafe(context, route);
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح الصفحة. حاول مجددًا.')),
        );
      }
    }
  }

  Widget _mainContent(bool isDesktop) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error) {
      return Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.cloud_off_outlined, size: 36),
          const SizedBox(height: 12),
          const Text('تعذر تحميل ملخص الورشة. حاول مجددًا.'),
          TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
        ],
      );
    }
    return DailyDashboardContent(
      data: _data!,
      profile: _profile,
      period: _period,
      onPeriod: _selectPeriod,
      onOpen: _open,
      onEntry: () async {
        final id = _data?.lastEntry?['id'];
        if (id is int) {
          await AppRoutes.openGlEntry(context, id);
          if (mounted) await _load();
        }
      },
    );
  }

  PreferredSizeWidget _appBar(bool isDesktop) {
    return AppBar(
      automaticallyImplyLeading: !isDesktop,
      leading: isDesktop
          ? null
          : Builder(
              builder: (headerContext) => IconButton(
                key: const Key('yalla_mobile_menu_button'),
                tooltip: 'القائمة',
                icon: const Icon(Icons.menu_rounded),
                onPressed: () => Scaffold.of(headerContext).openDrawer(),
              ),
            ),
      backgroundColor: YallaColors.brand,
      foregroundColor: YallaColors.surface,
      surfaceTintColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'أهلًا بك',
            style: TextStyle(fontSize: 12, color: Colors.white70),
          ),
          Text(
            _data?.name ?? 'ورشتي',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
      actions: [
        const NotificationBellButton(),
        if (_data?.logo?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: YallaStoredImage(
              storedPath: _data!.logo,
              width: 40,
              height: 40,
              borderRadius: BorderRadius.circular(10),
              fallback: const Icon(Icons.store_outlined),
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
                child: YallaSidebar(currentRoute: AppRoutes.dashboard),
              ),
            ),
      appBar: _appBar(isDesktop),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  child: _mainContent(isDesktop),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: isDesktop
          ? null
          : Builder(
              builder: (navContext) => YallaMobileBottomNav(
                currentRoute: AppRoutes.dashboard,
                onMore: () => Scaffold.of(navContext).openDrawer(),
              ),
            ),
    );

    final shell = isDesktop
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(
                width: 300,
                child: YallaSidebar(currentRoute: AppRoutes.dashboard),
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
          textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'Cairo',
            fontFamilyFallback: const [
              'DashboardArabic',
              'DashboardSymbols',
            ],
          ),
          scaffoldBackgroundColor: YallaColors.canvas,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: Size(isDesktop ? 44 : 48, isDesktop ? 42 : 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YallaRadii.control),
              ),
            ),
          ),
        ),
        child: shell,
      ),
    );
  }
}
