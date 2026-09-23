import 'dart:typed_data';

import 'package:yalla_accounts/core/pdf/yalla_pdf_service.dart';
import 'package:yalla_accounts/core/security/authorization_policy.dart';
import 'package:yalla_accounts/core/utils/money_formatter.dart';
import 'package:yalla_accounts/features/auth/services/authorization_guard.dart';
import 'package:yalla_accounts/features/insurance_agent/dashboard/services/insurance_dashboard_service.dart';

class InsuranceReportExportService {
  InsuranceReportExportService._();

  static String _csvCell(Object? value) {
    final text = (value ?? '')
        .toString()
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    return '"${text.replaceAll('"', '""')}"';
  }

  static String _date(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}';
  }

  static Future<String> buildPoliciesCsv(
    List<InsurancePolicyOverview> policies,
  ) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceReportExport);
    final buffer = StringBuffer('\uFEFF')
      ..writeln(
        const [
          'رقم الوثيقة',
          'المؤمن',
          'المركبة',
          'الشركة',
          'تاريخ الانتهاء',
          'سعر البيع',
          'الحالة',
        ].map(_csvCell).join(','),
      );
    for (final policy in policies) {
      buffer.writeln(
        [
          policy.number,
          policy.insuredName,
          policy.vehicle,
          policy.company,
          _date(policy.endDate),
          policy.sale.toStringAsFixed(2),
          policy.status,
        ].map(_csvCell).join(','),
      );
    }
    return buffer.toString();
  }

  static Future<Uint8List> buildPoliciesPdf(
    List<InsurancePolicyOverview> policies,
  ) async {
    await AuthorizationGuard.require(PermissionKeys.insuranceReportExport);
    return YallaPdfService.generateTablePdf(
      title: 'تقرير وثائق التأمين',
      headers: const [
        'رقم الوثيقة',
        'المؤمن',
        'المركبة',
        'الشركة',
        'الانتهاء',
        'البيع',
        'الحالة',
      ],
      rows: policies
          .map(
            (policy) => <String>[
              policy.number,
              policy.insuredName,
              policy.vehicle,
              policy.company,
              _date(policy.endDate),
              MoneyFormatter.number(policy.sale),
              policy.status,
            ],
          )
          .toList(growable: false),
    );
  }
}
