import '../activation/license_envelope_verifier.dart';
import '../../services/db/tables/license_runtime_tables.dart';

/// One policy for a cryptographically verified, device-bound license.
class SubscriptionAccessPolicy {
  static const statuses = {
    'ACTIVE',
    'TRIAL',
    'GRACE',
    'EXPIRED',
    'FROZEN',
    'CANCELLED',
    'EXCEPTION',
    'DEMO',
    'SUSPENDED',
    'REVOKED'
  };
  static String normalize(String status) => status.trim().toUpperCase();

  static String mode(VerifiedLicense license, DateTime now) {
    final status = normalize(license.operationalStatus);
    if (!statuses.contains(status) ||
        status == 'CANCELLED' ||
        status == 'REVOKED') {
      return LicenseRuntimeMode.readOnlyRevoked;
    }
    if (status == 'FROZEN' || status == 'SUSPENDED') {
      return LicenseRuntimeMode.readOnlySuspended;
    }
    if (status == 'EXPIRED' || !license.expiresAt.isAfter(now.toUtc())) {
      return LicenseRuntimeMode.readOnlyExpired;
    }
    if (license.notBefore.isAfter(now.toUtc()) ||
        !license.validationGraceUntil.isAfter(now.toUtc())) {
      return LicenseRuntimeMode.readOnlyValidationRequired;
    }
    // Demo never grants write access to a real workshop's financial data.
    if (status == 'DEMO') return LicenseRuntimeMode.readOnlySuspended;
    return LicenseRuntimeMode.writable;
  }

  static String label(String status) => switch (normalize(status)) {
        'ACTIVE' => 'نشط',
        'TRIAL' => 'تجريبي',
        'GRACE' => 'فترة سماح',
        'EXPIRED' => 'منتهي',
        'FROZEN' || 'SUSPENDED' => 'مجمّد',
        'CANCELLED' || 'REVOKED' => 'ملغى',
        'EXCEPTION' => 'استثناء مؤقت',
        'DEMO' => 'عرض توضيحي',
        _ => 'غير معتمد',
      };

  static String message(String mode) => mode == LicenseRuntimeMode.writable
      ? 'العمل متاح ضمن صلاحيات المستخدم.'
      : 'للقراءة والطباعة والتصدير والنسخ الاحتياطي فقط؛ الإدخال والتعديل متوقفان.';
}
