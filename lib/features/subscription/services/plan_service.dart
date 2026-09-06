import '../models/plan.dart';

/// Plans shown by the client must be a projection of server commercial state,
/// not rows created or trusted from local SQLite.
class PlanService {
  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  Never _deny() => throw StateError(serverAuthorityRequired);

  Future<List<Plan>> getAllActivePlans() async => _deny();

  Future<Plan?> getPlanById(String id) async => _deny();
}
