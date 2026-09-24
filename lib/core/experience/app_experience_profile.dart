enum BusinessActivity { garage, insurance, parts }

enum ExperienceMode { simple, advanced }

enum AppModule {
  repairs,
  insurance,
  inventory,
  purchases,
  employees,
  finance,
  vouchers,
  cheques,
  parties,
  reports,
}

class AppExperienceProfile {
  const AppExperienceProfile({
    required this.activities,
    required this.mode,
    this.moduleOverrides = const <AppModule, bool>{},
    this.hiddenRoutes = const <String>{},
  });

  final Set<BusinessActivity> activities;
  final ExperienceMode mode;
  final Map<AppModule, bool> moduleOverrides;
  final Set<String> hiddenRoutes;

  static const AppExperienceProfile defaults = AppExperienceProfile(
    activities: <BusinessActivity>{BusinessActivity.garage},
    mode: ExperienceMode.simple,
  );

  static const Set<String> advancedAccountingRoutes = <String>{
    '/finance/journal/entries',
    '/finance/account-ledger',
    '/finance/gl',
    '/finance/general-journal',
    '/finance/accounting-periods',
    '/reports/trial-balance',
    '/reports/general-ledger',
    '/reports/balance-sheet',
  };

  Set<AppModule> get recommendedModules {
    final modules = <AppModule>{
      AppModule.finance,
      AppModule.vouchers,
      AppModule.parties,
      AppModule.reports,
    };
    if (activities.contains(BusinessActivity.garage)) {
      modules.addAll(const <AppModule>{
        AppModule.repairs,
        AppModule.inventory,
        AppModule.purchases,
        AppModule.employees,
        AppModule.cheques,
      });
    }
    if (activities.contains(BusinessActivity.parts)) {
      modules.addAll(const <AppModule>{
        AppModule.inventory,
        AppModule.purchases,
        AppModule.cheques,
      });
    }
    if (activities.contains(BusinessActivity.insurance)) {
      modules.addAll(const <AppModule>{AppModule.insurance, AppModule.cheques});
    }
    return modules;
  }

  bool moduleEnabled(AppModule module) =>
      moduleOverrides[module] ?? recommendedModules.contains(module);

  bool isRouteVisible(String route, {required bool insurancePilotVisible}) {
    if (route.isEmpty || _isAlwaysVisible(route)) return true;
    if (_isInsuranceRoute(route) && !insurancePilotVisible) return false;
    if (hiddenRoutes.contains(route)) return false;
    if (mode == ExperienceMode.simple &&
        advancedAccountingRoutes.contains(route)) {
      return false;
    }
    final module = moduleForRoute(route);
    return module == null || moduleEnabled(module);
  }

  bool isSearchSourceVisible(
    String source, {
    required bool insurancePilotVisible,
  }) {
    switch (source) {
      case 'repairs':
      case 'vehicles':
        return moduleEnabled(AppModule.repairs);
      case 'documents':
        return insurancePilotVisible && moduleEnabled(AppModule.insurance);
      case 'items':
        return moduleEnabled(AppModule.inventory);
      case 'purchases':
        return moduleEnabled(AppModule.purchases);
      case 'employees':
        return moduleEnabled(AppModule.employees);
      case 'cheques':
        return moduleEnabled(AppModule.cheques);
      case 'clients':
      case 'suppliers':
        return moduleEnabled(AppModule.parties);
      case 'receipts':
      case 'payments':
      case 'invoices':
        return moduleEnabled(AppModule.finance) ||
            moduleEnabled(AppModule.vouchers);
      default:
        return true;
    }
  }

  static AppModule? moduleForRoute(String route) {
    if (route.startsWith('/repairs')) return AppModule.repairs;
    if (_isInsuranceRoute(route)) return AppModule.insurance;
    if (route.startsWith('/inventory') || route.startsWith('/raw_materials')) {
      return AppModule.inventory;
    }
    if (route.startsWith('/purchases')) return AppModule.purchases;
    if (route.startsWith('/employees')) return AppModule.employees;
    if (route.startsWith('/cheques')) return AppModule.cheques;
    if (route.startsWith('/clients') ||
        route.startsWith('/suppliers') ||
        route.startsWith('/parties')) {
      return AppModule.parties;
    }
    if (route.startsWith('/reports')) return AppModule.reports;
    if (route.startsWith('/finance/receipt-voucher') ||
        route.startsWith('/finance/payment-voucher')) {
      return AppModule.vouchers;
    }
    if (route.startsWith('/finance') || route == '/expenses') {
      return AppModule.finance;
    }
    return null;
  }

  static bool _isInsuranceRoute(String route) =>
      route.startsWith('/insurance-agent') || route.startsWith('/insurance/');

  static bool _isAlwaysVisible(String route) =>
      route == '/' ||
      route == '/startup' ||
      route == '/login' ||
      route == '/logout' ||
      route == '/register' ||
      route == '/activation' ||
      route == '/trial-expired' ||
      route == '/dashboard' ||
      route == '/home/dashboard' ||
      route == '/search' ||
      route.startsWith('/settings') ||
      route.startsWith('/subscription') ||
      route == '/current-subscription' ||
      route == '/technical-support';

  AppExperienceProfile copyWith({
    Set<BusinessActivity>? activities,
    ExperienceMode? mode,
    Map<AppModule, bool>? moduleOverrides,
    Set<String>? hiddenRoutes,
  }) =>
      AppExperienceProfile(
        activities: activities ?? this.activities,
        mode: mode ?? this.mode,
        moduleOverrides: moduleOverrides ?? this.moduleOverrides,
        hiddenRoutes: hiddenRoutes ?? this.hiddenRoutes,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'activities': activities.map((e) => e.name).toList(),
        'mode': mode.name,
        'module_overrides': <String, bool>{
          for (final entry in moduleOverrides.entries)
            entry.key.name: entry.value,
        },
        'hidden_routes': hiddenRoutes.toList(),
      };

  factory AppExperienceProfile.fromJson(Map<String, Object?> json) {
    final parsedActivities = <BusinessActivity>{};
    final rawActivities = json['activities'];
    if (rawActivities is List) {
      for (final raw in rawActivities) {
        for (final value in BusinessActivity.values) {
          if (value.name == raw?.toString()) parsedActivities.add(value);
        }
      }
    }
    if (parsedActivities.isEmpty) parsedActivities.add(BusinessActivity.garage);

    final parsedOverrides = <AppModule, bool>{};
    final rawOverrides = json['module_overrides'];
    if (rawOverrides is Map) {
      for (final entry in rawOverrides.entries) {
        for (final module in AppModule.values) {
          if (module.name == entry.key.toString() && entry.value is bool) {
            parsedOverrides[module] = entry.value as bool;
          }
        }
      }
    }

    final parsedHidden = <String>{};
    final rawHidden = json['hidden_routes'];
    if (rawHidden is List) {
      parsedHidden.addAll(
        rawHidden
            .map((value) => value?.toString() ?? '')
            .where((e) => e.isNotEmpty),
      );
    }

    return AppExperienceProfile(
      activities: parsedActivities,
      mode: ExperienceMode.values.firstWhere(
        (value) => value.name == json['mode']?.toString(),
        orElse: () => ExperienceMode.simple,
      ),
      moduleOverrides: parsedOverrides,
      hiddenRoutes: parsedHidden,
    );
  }
}
