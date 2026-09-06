/// Legacy local subscription facade.
///
/// P18 authority rule: the client never creates, renews, or invents a
/// subscription. The server issues signed commercial state.
class SubscriptionService {
  static const String serverAuthorityRequired = 'SERVER_AUTHORITY_REQUIRED';

  Never _deny() => throw StateError(serverAuthorityRequired);

  Future<void> createSubscription({
    required String id,
    required String planId,
    required DateTime startDate,
    required DateTime endDate,
    required String userId,
    required double price,
  }) async =>
      _deny();

  Future<Map<String, dynamic>?> getActiveSubscription(String userId) async =>
      _deny();

  Future<bool> isSubscriptionActive(String userId) async => _deny();

  Future<List<Map<String, dynamic>>> getAvailablePlans() async => _deny();

  Future<Map<String, dynamic>?> getPlanById(String planId) async => _deny();

  Future<bool> activateTrial(String userId, int durationDays) async => _deny();
}
