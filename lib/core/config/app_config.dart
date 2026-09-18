// lib/core/config/app_config.dart

import 'environment.dart';

class AppConfig {
  static final AppConfig _instance = AppConfig._internal();

  factory AppConfig() => _instance;

  AppEnvironment environment = AppEnvironment.development;

  late String apiBaseUrl;
  late bool enableLogs;
  late String appName;

  AppConfig._internal();

  void initialize(AppEnvironment env) {
    environment = env;

    switch (env) {
      case AppEnvironment.development:
        apiBaseUrl = 'http://localhost:3000/api';
        enableLogs = true;
        appName = 'Yallah Accounts [Dev]';
        break;

      case AppEnvironment.production:
        apiBaseUrl = 'https://api.yalla.ps';
        enableLogs = false;
        appName = 'Yallah Accounts';
        break;
    }
  }

  static AppConfig get instance => _instance;
}
