// 📁 lib/main.dart — Production bootstrap + Riverpod root
// FINAL — Global EN digits (Latin) while keeping Arabic UI + RTL

import 'dart:async';
import 'dart:ui' as ui show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Intl;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sq;

import 'package:yalla_accounts/core/services/db_service.dart';
import 'package:yalla_accounts/core/routes/app_routes.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';
import 'package:yalla_accounts/core/licensing/lifecycle/license_runtime_service.dart';
import 'package:yalla_accounts/core/licensing/validation/periodic_license_validation_service.dart';
import 'package:yalla_accounts/features/settings/services/workshop_settings_service.dart';
import 'package:yalla_accounts/features/settings/services/commercial_settings_service.dart';

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
    debugPrint(
      '🧨 [ProviderError] ${provider.name ?? provider.runtimeType}: $error\n$stackTrace',
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

  // ✅ هذا أهم سطر: يخلي intl (DateFormat/NumberFormat) يستخدم أرقام 0-9
  Intl.defaultLocale = 'ar-u-nu-latn';

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  if (isDesktop) {
    sqfliteFfiInit();
    sq.databaseFactory = databaseFactoryFfi;
    debugPrint("📌 Using sqflite_common_ffi (Desktop mode)");
  }

  try {
    final path = await DBService.dbFilePath();
    debugPrint('📂 DB Path = $path');

    final db = await DBService.database.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException('DB open timed out');
      },
    );

    // SQLite runtime configuration is owned by DatabaseMigration.
    await WorkshopSettingsService.createTable(db);
    await DBService.ensureDefaultAccountsExist();
    await CommercialSettingsService.instance.get();

    // SEC.005 - materialize a stable local installation/device identity.
    await DeviceIdentityService().ensureCurrent();

    // SEC.011 - project the signed license into a local operational mode.
    // Existing unactivated legacy installs remain activation-required, while a
    // signed expired/suspended/revoked license becomes DB-enforced READ ONLY.
    final runtimeDecision =
        await LicenseRuntimeService().refreshFromStoredLicense();
    debugPrint(
      '🔐 SEC.011 runtime mode: ${runtimeDecision.mode} '
      '(${runtimeDecision.reason})',
    );

    // SEC.012 - periodic online validation. Startup never crashes merely
    // because the network/server is unavailable; the signed offline grace
    // window decides whether writes remain available.
    PeriodicLicenseValidationScheduler.start();

    debugPrint(
      '✅ DB + commercial presentation settings + device identity + '
      'license runtime + periodic validation ready',
    );
  } catch (e, st) {
    debugPrint('🛑 DB bootstrap failed: $e\n$st');
    Error.throwWithStackTrace(e, st);
  }

  FlutterError.onError = (details) {
    debugPrint('🧨 FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) debugPrint(details.stack.toString());
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('🧨 Platform error: $error\n$stack');
    return true;
  };
}

/// ---------------------------------------------------------------------------
/// App Entry Point (NO LICENSE)
/// ---------------------------------------------------------------------------
void main() {
  runZonedGuarded(() async {
    try {
      await _bootstrap();

      runApp(
        ProviderScope(
          observers: [_YallaObserver()],
          child: const MyApp(),
        ),
      );
    } catch (error, stack) {
      debugPrint('🛑 Startup blocked: $error\n$stack');
      runApp(_BootstrapFailureApp(error: error));
    }
  }, (error, stack) {
    debugPrint('❗ Uncaught error: $error\n$stack');
  });
}

class _BootstrapFailureApp extends StatelessWidget {
  final Object error;

  const _BootstrapFailureApp({required this.error});

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
                      'تعذر فتح قاعدة بيانات Yalla Accounts بأمان',
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
                      error.toString(),
                      textAlign: TextAlign.center,
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
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'Yalla Accounts',
        debugShowCheckedModeBanner: false,
        navigatorKey: AppRoutes.navigatorKey,

        /// 🔥 تشغيل مباشر بدون أي شرط
        initialRoute: AppRoutes.startup,
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
            data: YallaMobileTheme.from(Theme.of(context)),
            child: YallaMobilePage(child: page),
          );
        },
        scrollBehavior: YallaScrollBehavior(),

        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: Color(0xFF22C55E),
            brightness: Brightness.light,
          ),
          appBarTheme: AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
      ),
    );
  }
}
