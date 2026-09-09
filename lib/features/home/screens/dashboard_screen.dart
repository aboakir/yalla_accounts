import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/design/yalla_design_tokens.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/storage/yalla_stored_image.dart';
import 'package:yalla_accounts/core/widgets/sidebar/yalla_sidebar.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_bottom_nav.dart';
import 'package:yalla_accounts/features/repairs/services/repair_database_service.dart';
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
      final data = await DailyDashboardService.load(_period);
      if (!mounted || request != _request) return;
      setState(() => _data = data);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  Future<void> _open(String route, String? repairId) async {
    try {
      if (repairId != null) {
        final repair = await RepairDatabaseService.getRepairById(repairId);
        if (!mounted) return;
        if (repair == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('الملف غير متاح؛ تم تحديث الملخص.')));
        } else {
          await Navigator.pushNamed(context, AppRoutes.repairDetail,
              arguments: repair);
        }
      } else {
        await Navigator.pushNamed(context, route);
      }
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح الصفحة. حاول مجددًا.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
            data: Theme.of(context).copyWith(
                brightness: Brightness.light,
                textTheme: Theme.of(context).textTheme.apply(
                    fontFamily: 'Cairo',
                    fontFamilyFallback: const [
                      'DashboardArabic',
                      'DashboardSymbols'
                    ]),
                scaffoldBackgroundColor: YallaColors.canvas,
                filledButtonTheme: FilledButtonThemeData(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(YallaRadii.control))))),
            child: Scaffold(
              drawer: const Drawer(
                  child: SafeArea(
                      child: YallaSidebar(currentRoute: AppRoutes.dashboard))),
              appBar: AppBar(
                leading: Builder(
                    builder: (headerContext) => IconButton(
                        key: const Key('yalla_mobile_menu_button'),
                        tooltip: 'القائمة',
                        icon: const Icon(Icons.menu_rounded),
                        onPressed: () =>
                            Scaffold.of(headerContext).openDrawer())),
                backgroundColor: YallaColors.brand,
                foregroundColor: YallaColors.surface,
                surfaceTintColor: Colors.transparent,
                title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('أهلًا بك',
                          style:
                              TextStyle(fontSize: 12, color: Colors.white70)),
                      Text(_data?.name ?? 'ورشتي',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                    ]),
                actions: [
                  if (_data?.logo?.isNotEmpty ?? false)
                    Padding(
                        padding: const EdgeInsetsDirectional.only(end: 16),
                        child: YallaStoredImage(
                            storedPath: _data!.logo,
                            width: 40,
                            height: 40,
                            borderRadius: BorderRadius.circular(10),
                            fallback: const Icon(Icons.store_outlined)))
                ],
              ),
              body: SafeArea(
                  child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                          children: [
                            Center(
                                child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: _loading
                                  ? const Padding(
                                      padding: EdgeInsets.all(48),
                                      child: Center(
                                          child: CircularProgressIndicator()))
                                  : _error
                                      ? Column(children: [
                                          const SizedBox(height: 32),
                                          const Icon(Icons.cloud_off_outlined,
                                              size: 36),
                                          const SizedBox(height: 12),
                                          const Text(
                                              'تعذر تحميل ملخص الورشة. حاول مجددًا.'),
                                          TextButton(
                                              onPressed: _load,
                                              child:
                                                  const Text('إعادة المحاولة'))
                                        ])
                                      : DailyDashboardContent(
                                          data: _data!,
                                          period: _period,
                                          onPeriod: (period) {
                                            setState(() => _period = period);
                                            _load();
                                          },
                                          onOpen: _open,
                                          onEntry: () async {
                                            final id = _data?.lastEntry?['id'];
                                            if (id is int) {
                                              await AppRoutes.openGlEntry(
                                                  context, id);
                                              if (mounted) await _load();
                                            }
                                          }),
                            )),
                          ]))),
              bottomNavigationBar: Builder(
                  builder: (navContext) => YallaMobileBottomNav(
                      currentRoute: AppRoutes.dashboard,
                      onMore: () => Scaffold.of(navContext).openDrawer())),
            )),
      );
}
