// ============================================================================
// 📁 lib/features/insurance_agent/policies/services/insurance_policy_service.dart
// InsurancePolicyService — Save Policy Draft into DB (FINAL)
// ✅ يحفظ insurance_policies
// ✅ يحفظ تفاصيل الدفع حسب الخطة: شيكات / أقساط / كمبيالات
// ✅ Transaction واحدة (Atomic)
// ============================================================================

import 'package:yalla_accounts/core/services/db/db_service.dart';
import 'package:yalla_accounts/features/insurance_agent/policies/models/policy_draft.dart';

class InsurancePolicyService {
  /// يرجّع policyId بعد الحفظ
  static Future<String> savePolicyDraft(PolicyDraft draft) async {
    // مزامنة legacy (احتياط)
    draft.syncLegacyFromNew();

    final now = DateTime.now().toIso8601String();
    final policyId = DBService.newUuid();

    // =========================
    // Policy Row
    // =========================
    final policyData = <String, dynamic>{
      'id': policyId,
      'created_at': now,
      'updated_at': now,
      'vehicle_plate': (draft.vehiclePlate ?? draft.vehicleNumber ?? '').trim(),
      'vehicle_make': (draft.vehicleMake ?? draft.vehicleType ?? '').trim(),
      'vehicle_model_year': (draft.vehicleModelYear ?? '').trim(),
      'engine_cc': (draft.engineCc ?? draft.engineSize ?? '').trim(),
      'insured_name': (draft.insuredName ?? '').trim(),
      'insured_phone': (draft.insuredPhone ?? '').trim(),
      'company_name': (draft.companyName ?? '').trim(),
      'start_date': draft.startDate!.toIso8601String(),
      'end_date': draft.endDate!.toIso8601String(),
      'is_vip': draft.isVip ? 1 : 0,
      'buy_price': (draft.buyPrice ?? 0.0),
      'sell_price': (draft.sellPrice ?? 0.0),
      'payment_type': draft.payment.type.name,
      'cash_amount': (draft.payment.cashAmount ?? 0.0),
      'notes': (draft.notes ?? '').trim(),
    };

    // =========================
    // Save in one TX
    // =========================
    await DBService.inTx((ex) async {
      final db = ex; // DatabaseExecutor

      // 1) Insert Policy
      await db.insert('insurance_policies', policyData);

      // 2) Insert Cheques (if any)
      if (draft.payment.cheques.isNotEmpty) {
        for (final c in draft.payment.cheques) {
          final chequeId = DBService.newUuid();

          await db.insert('insurance_policy_cheques', {
            'id': chequeId,
            'policy_id': policyId,
            'amount': (c.amount ?? 0.0),
            'due_date': c.dueDate?.toIso8601String(),
            'bank_name': (c.bankName ?? '').trim(),
            'drawer_name': (c.drawerName ?? '').trim(),
            'cheque_number': (c.chequeNumber ?? '').trim(),
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      // 3) Insert Installments (if any)
      if (draft.payment.installments.isNotEmpty) {
        for (final i in draft.payment.installments) {
          final instId = DBService.newUuid();

          await db.insert('insurance_policy_installments', {
            'id': instId,
            'policy_id': policyId,
            'amount': (i.amount ?? 0.0),
            'due_date': i.dueDate?.toIso8601String(),
            'note': (i.note ?? '').trim(),
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      // 4) Insert Promissories (if any)
      if (draft.payment.promissories.isNotEmpty) {
        for (final p in draft.payment.promissories) {
          final promId = DBService.newUuid();

          await db.insert('insurance_policy_promissories', {
            'id': promId,
            'policy_id': policyId,
            'amount': (p.amount ?? 0.0),
            'due_date': p.dueDate?.toIso8601String(),
            'created_at': now,
            'updated_at': now,
          });
        }
      }

      return true;
    });

    return policyId;
  }
}
