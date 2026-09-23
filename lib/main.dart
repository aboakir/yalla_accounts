import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
// 📁 lib/main.dart — Production bootstrap + Riverpod root
// FINAL — Global EN digits (Latin) while keeping Arabic UI + RTL

import 'dart:async';
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:yalla_accounts/core/theme/yalla_button_themes.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Intl;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sq;

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/services/sync/unified_sync_coordinator_v3.dart';
import 'package:yalla_accounts/core/config/owner_local_access.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/commercial_licensing_providers.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

import 'package:yalla_accounts/core/constants/colors.dart';
import 'package:yalla_accounts/core/security/release_diagnostics.dart';
import 'package:yalla_accounts/core/platform/windows_auth_callback_registration.dart';
import 'package:yalla_accounts/core/widgets/mobile/yalla_mobile_theme.dart';
import 'package:yalla_accounts/shared/widgets/yalla_mobile_adaptive.dart';

/// ---------------------------------------------------------------------------
/// ✅ Locale: Arabic UI but EN digits everywhere
/// - BCP47 tag: ar-u-nu-latn  (Arabic with Latin numerals)
/// ---------------------------------------------------------------------------
const Locale kAppLocale =
    Locale('ar', 'u-nu-latn'); // مهم: هذا يحوّل الأرقام للاتينية
const List<Locale> kSupportedLocales = [
  Locale('ar', 'u-nu-latn'),
  Locale('ar'),
];

/// ---------------------------------------------------------------------------
/// Riverpod Observer
/// ---------------------------------------------------------------------------
class _YallaObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderBase provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    ReleaseDiagnostics.debug(
      'Provider failed: ${provider.name ?? provider.runtimeType}',
      error: error,
      stack: stackTrace,
    );
    super.providerDidFail(provider, error, stackTrace, container);
  }
}

/// ---------------------------------------------------------------------------
/// Scroll behavior (Desktop friendly)
/// ---------------------------------------------------------------------------
class YallaScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

/// ---------------------------------------------------------------------------
/// Bootstrap — DB + settings (NO LICENSE)
/// ---------------------------------------------------------------------------
Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  ReleaseDiagnostics.markStartupPhase(StartupPhase.preparing);
  final authCallbackRegistered = await ensureWindowsAuthCallbackRegistration();
  ReleaseDiagnostics.debug(
    'Windows auth callback registration: $authCallbackRegistered',
  );
  AuthorizationGuard.enableInteractiveEnforcement();

  // ✅ هذا أهم سطر: يخلي intl (DateFormat/NumberFormat) يستخدم أرقام 0-9
  Intl.defaultLocale = 'ar-u-nu-latn';

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  if (isDesktop) {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
    ReleaseDiagnostics.debug('Using sqflite_common_ffi (Desktop mode)');
  }

  try {
    ReleaseDiagnostics.markStartupPhase(StartupPhase.databasePath);
    final path = await DBService.dbFilePath();
    ReleaseDiagnostics.debug('DB path resolved: $path');

    // Future.timeout does not cancel SQLite work. Do not report failure while
    // a migration is still writing; keep the progress UI until it settles.
    final db = await DBService.database;

    // SQLite runtime configuration is owned by DatabaseMigration.
    ReleaseDiagnostics.markStartupPhase(StartupPhase.settings);
    await WorkshopSettingsService.createTable(db);
    await DBService.ensureDefaultAccountsExist();
    await CommercialSettingsService.instance.get();

    // SEC.005 - materialize a stable local installation/device identity.
    ReleaseDiagnostics.markStartupPhase(StartupPhase.deviceIdentity);
    await DeviceIdentityService().ensureCurrent();

    // SEC.011 - project the signed license into a local operational mode.
    // Existing unactivated legacy installs remain activation-required, while a
    // signed expired/suspended/revoked license becomes DB-enforced READ ONLY.
    ReleaseDiagnostics.markStartupPhase(StartupPhase.license);
    final runtimeDecision =
        await LicenseRuntimeService().refreshFromStoredLicense();
    ReleaseDiagnostics.debug(
      'SEC.011 runtime mode: ${runtimeDecision.mode} '
      '(${runtimeDecision.reason})',
    );

    // SEC.012 - periodic online validation. Startup never crashes merely
    // because the network/server is unavailable; the signed offline grace
    // window decides whether writes remain available.
    // The Riverpod root starts validation with the authenticated transport.

    // Stage 8 - durable local-first sync. The client never calls Supabase
    // directly; it sends a device-signed challenge/complete exchange to the
    // configured Yalla server, which is the only component allowed to journal
    // the mutation through the server-authorized RPC.
    if (!OwnerLocalAccess.enabled) {
      await UnifiedSyncCoordinatorV3.instance.start();
    }

    ReleaseDiagnostics.markStartupPhase(StartupPhase.ready);
    ReleaseDiagnostics.debug(
      'DB + commercial presentation settings + device identity + '
      'license runtime + periodic validation ready',
    );
  } catch (e, st) {
    ReleaseDiagnostics.debug('DB bootstrap failed', error: e, stack: st);
    Error.throwWithStackTrace(e, st);
  }

  FlutterError.onError = (details) {
    ReleaseDiagnostics.debug(
      'Flutter framework error',
      error: details.exception,
      stack: details.stack,
    );
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    ReleaseDiagnostics.debug('Platform error', error: error, stack: stack);
    return true;
  };
}

/// ---------------------------------------------------------------------------
/// App Entry Point (NO LICENSE)
/// ---------------------------------------------------------------------------
void main() {
  runZonedGuarded(() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(const _BootstrapLoadingApp());
      await _bootstrap();

      runApp(
        ProviderScope(
          observers: [_YallaObserver()],
          child: const MyApp(),
        ),
      );
    } catch (error, stack) {
      ReleaseDiagnostics.debug('Startup blocked', error: error, stack: stack);
      runApp(_BootstrapFailureApp(error: error));
    }
  }, (error, stack) {
    ReleaseDiagnostics.debug('Uncaught zone error', error: error, stack: stack);
  });
}

class _BootstrapLoadingApp extends StatelessWidget {
  const _BootstrapLoadingApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            fontFamily: 'Cairo',
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              primaryContainer: AppColors.lightGreen,
              onPrimaryContainer: AppColors.textDark,
              secondary: AppColors.secondary,
              surface: Colors.white,
              onSurface: AppColors.textDark,
              error: AppColors.danger,
            )),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
              body: Center(
                  child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              const Text('جارٍ فتح بياناتك بأمان',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text(
                  'قد يستغرق تحديث قاعدة البيانات وقتًا في أول تشغيل. اترك التطبيق مفتوحًا حتى يكتمل.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ValueListenableBuilder<StartupPhase>(
                valueListenable: ReleaseDiagnostics.startupPhase,
                builder: (_, phase, __) => Text(
                    'مرحلة التشغيل: ${phase.name.toUpperCase()}',
                    textAlign: TextAlign.center),
              ),
            ]),
          ))),
        ),
      );
}

class _BootstrapFailureApp extends StatefulWidget {
  const _BootstrapFailureApp({required this.error});

  final Object error;

  @override
  State<_BootstrapFailureApp> createState() => _BootstrapFailureAppState();
}

class _BootstrapFailureAppState extends State<_BootstrapFailureApp> {
  late Object _error = widget.error;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _bootstrap();
      if (!mounted) return;
      runApp(
        ProviderScope(
          observers: [_YallaObserver()],
          child: const MyApp(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.storage_rounded,
                      size: 56,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'تعذر فتح قاعدة بيانات Yallah Accounts بأمان',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'تم إيقاف تشغيل النظام لحماية البيانات. '
                      'لن يتم إنشاء قاعدة بديلة أو متابعة العمل على قاعدة غير سليمة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      ReleaseDiagnostics.publicFailureText(_error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                        'مرحلة التشغيل: ${ReleaseDiagnostics.startupPhase.value.name.toUpperCase()}'),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _retrying ? null : _retry,
                      icon: _retrying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: Text(
                        _retrying ? 'جاري إعادة المحاولة...' : 'إعادة المحاولة',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Root App
/// ---------------------------------------------------------------------------
class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!OwnerLocalAccess.enabled) {
      ref.watch(commercialValidationSchedulerProvider);
      ref.watch(commercialSyncSchedulerProvider);
    }
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'Yallah Accounts',
        debugShowCheckedModeBanner: false,
        navigatorKey: AppRoutes.navigatorKey,

        /// التشغيل الطبيعي يبدأ من startup.
        initialRoute: AppRoutes.startup,
        onGenerateInitialRoutes: AppRoutes.generateInitialRoutes,
        onGenerateRoute: AppRoutes.onGenerateRoute,

        // ✅ أهم نقطة: Locale عربي لكن بأرقام إنجليزية
        locale: kAppLocale,
        supportedLocales: kSupportedLocales,

        // ✅ ضمان إن أي جهاز عربي يرجع على ar-u-nu-latn مباشرة
        localeResolutionCallback: (deviceLocale, supported) {
          if (deviceLocale == null) return kAppLocale;
          if (deviceLocale.languageCode.toLowerCase() == 'ar') {
            return kAppLocale;
          }
          return kAppLocale; // تطبيقك عربي أساسًا
        },

        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        // YALLA_FULL_MOBILE_UI_V2
        builder: (context, child) {
          final page = child ?? const SizedBox.shrink();
          if (MediaQuery.sizeOf(context).width >= 600) return page;
          return Theme(
            data: YallaMobileTheme.from(
              Theme.of(context),
              viewportWidth: MediaQuery.sizeOf(context).width,
            ),
            child: YallaMobilePage(child: page),
          );
        },
        scrollBehavior: YallaScrollBehavior(),

        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          fontFamily: 'Cairo',
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            primaryContainer: AppColors.lightGreen,
            onPrimaryContainer: AppColors.textDark,
            secondary: AppColors.secondary,
            onSecondary: Colors.white,
            secondaryContainer: Color(0xFFF0F1F2),
            onSecondaryContainer: AppColors.textDark,
            surface: Colors.white,
            onSurface: AppColors.textDark,
            error: AppColors.danger,
            onError: Colors.white,
          ),
          appBarTheme: AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          elevatedButtonTheme: YallaButtonThemes.elevated,
          filledButtonTheme: YallaButtonThemes.filled,
          textButtonTheme: YallaButtonThemes.text,
          outlinedButtonTheme: YallaButtonThemes.outlined,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
      ),
    );
  }
}
