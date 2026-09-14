import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/services/db_service.dart';
import '../cloud_auth/cloud_auth_service.dart';
import 'customer_onboarding_client.dart';

final customerOnboardingClientProvider = Provider((ref) {
  final client = CustomerOnboardingClient(
      sessionProvider:
          ref.watch(supabaseIdentityProvider).verifiedOnboardingSession);
  ref.onDispose(client.close);
  return client;
});
final customerOnboardingServiceProvider = Provider((ref) =>
    CustomerOnboardingService(
        client: ref.watch(customerOnboardingClientProvider),
        database: () => DBService.database));

/// This table stages owner details only. It deliberately has no user, role,
/// local session, installation binding, organization row or financial access.
/// Its cached response is NEVER used to authorize or restore approval.
class CustomerOnboardingService {
  CustomerOnboardingService({required this.client, required this.database});
  final CustomerOnboardingClient client;
  final Future<Database> Function() database;
  Future<Database> _db() async {
    final db = await database();
    await db.execute('''CREATE TABLE IF NOT EXISTS pending_customer_onboarding (
      auth_user_id TEXT PRIMARY KEY, draft_json TEXT, response_json TEXT,
      owner_stage TEXT NOT NULL CHECK(owner_stage IN ('DRAFT','PENDING','REJECTED','APPROVED_AWAITING_ACTIVATION'))
    )''');
    return db;
  }

  Future<CustomerOnboardingStatus> submit(Map<String, Object?> draft) async {
    final session = await client.sessionProvider();
    final db = await _db();
    const allowed = [
      'owner_name',
      'organization_name',
      'phone',
      'country_code',
      'city',
      'address',
      'province',
      'street'
    ];
    if (draft.keys.any((k) => !allowed.contains(k))) {
      throw const CustomerOnboardingException('INVALID_DRAFT');
    }
    await db.rawInsert(
        '''INSERT INTO pending_customer_onboarding(auth_user_id,draft_json,owner_stage)
      VALUES(?,?,'DRAFT') ON CONFLICT(auth_user_id) DO UPDATE SET
      draft_json=COALESCE(pending_customer_onboarding.draft_json,excluded.draft_json)''',
        [session.authUserId, jsonEncode(draft)]);
    final response = await client.send(session, 'request', draft);
    await _save(db, session.authUserId, response);
    return response;
  }

  Future<CustomerOnboardingStatus> refresh() async {
    final session = await client.sessionProvider();
    final response = await client.send(session, 'status', {});
    await _save(await _db(), session.authUserId, response);
    return response;
  }

  Future<void> _save(
      Database db, String userId, CustomerOnboardingStatus response) async {
    await db.rawInsert(
        '''INSERT INTO pending_customer_onboarding(auth_user_id,response_json,owner_stage)
      VALUES(?,?,?) ON CONFLICT(auth_user_id) DO UPDATE SET response_json=excluded.response_json,owner_stage=excluded.owner_stage''',
        [
          userId,
          jsonEncode(response.data),
          response.approved ? 'APPROVED_AWAITING_ACTIVATION' : response.status
        ]);
  }
}
