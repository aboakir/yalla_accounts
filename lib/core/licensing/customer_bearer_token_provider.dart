/// Identity boundary only. The Control server resolves commercial authority.
/// Phase 3 supplies the authenticated session implementation.
typedef CustomerBearerTokenProvider = Future<String?> Function();
