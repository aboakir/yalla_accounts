import 'package:flutter/foundation.dart';

/// Centralizes diagnostics so release builds never expose raw runtime details.
class ReleaseDiagnostics {
  const ReleaseDiagnostics._();

  static const String startupBlockedCode = 'STARTUP_BLOCKED';

  static void debug(
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    if (!kDebugMode) return;
    debugPrint(message);
    if (error != null) debugPrint(error.toString());
    if (stack != null) debugPrint(stack.toString());
  }

  static String publicFailureText(
    Object error, {
    bool? debugMode,
  }) {
    final showDetails = debugMode ?? kDebugMode;
    if (showDetails) return error.toString();
    return 'رمز الخطأ: $startupBlockedCode';
  }
}
