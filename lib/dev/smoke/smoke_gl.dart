// 📁 lib/dev/smoke/smoke_gl.dart
//
// SmokeGL — تحقّق هيكلي سريع بدون إنشاء قيود أو بيانات.
// مخصص للبيئات الحقيقية: يضمن وجود الحسابات الأساسية فقط.

import 'package:yalla_accounts/core/services/accounting_gl.dart';
import 'package:yalla_accounts/features/finance/opening/opening_balances_service.dart';

class SmokeGL {
  /// لا ينشئ أي قيود. فقط يتأكد من الجداول والحسابات الأساسية.
  static Future<List<String>> run() async {
    final out = <String>[];
    await GL.ensureCoreAccounts();
    out.add('OK: ensureCoreAccounts');

    await OpeningBalancesService.ensureOpeningEquity();
    out.add('OK: ensure Opening Equity (3000)');

    return out;
  }
}
