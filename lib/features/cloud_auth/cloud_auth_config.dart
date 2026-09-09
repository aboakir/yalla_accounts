class CloudAuthConfig {
  const CloudAuthConfig(
      {required this.url,
      required this.publicKey,
      this.releaseReady = false,
      this.oauthEnabled = false});
  factory CloudAuthConfig.environment() => const CloudAuthConfig(
      url: String.fromEnvironment('YALLA_SUPABASE_URL'),
      publicKey: String.fromEnvironment('YALLA_SUPABASE_PUBLISHABLE_KEY'),
      releaseReady: bool.fromEnvironment('YALLA_CLOUD_AUTH_RELEASE_READY'),
      oauthEnabled: bool.fromEnvironment('YALLA_CLOUD_OAUTH_ENABLED'));
  final String url;
  final String publicKey;
  final bool releaseReady;
  final bool oauthEnabled;
  static const callback = 'yallaaccounts://auth/callback';
  static const recovery = 'yallaaccounts://auth/recovery';
  bool get enabled {
    final uri = Uri.tryParse(url);
    // Only the modern public publishable key is accepted, never service-role JWTs.
    return releaseReady &&
        uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.path.isEmpty || uri.path == '/') &&
        publicKey.startsWith('sb_publishable_') &&
        publicKey.length > 20;
  }

  String get issuer => '${url.replaceFirst(RegExp(r'/$'), '')}/auth/v1';
  static bool acceptsCallback(Uri uri) =>
      uri.scheme == 'yallaaccounts' &&
      uri.host == 'auth' &&
      (uri.path == '/callback' || uri.path == '/recovery') &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment &&
      uri.queryParameters['code']?.isNotEmpty == true;
}
