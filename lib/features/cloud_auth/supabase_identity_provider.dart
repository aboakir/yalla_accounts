import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_auth_config.dart';
import 'cloud_secure_storage.dart';

class VerifiedCloudIdentity {
  const VerifiedCloudIdentity(this.issuer, this.subject);
  final String issuer;
  final String subject;
}

class VerifiedOnboardingSession {
  const VerifiedOnboardingSession(this.authUserId, this.accessToken);
  final String authUserId;
  final String accessToken;
}

abstract interface class CloudIdentityProvider {
  Future<VerifiedCloudIdentity> verifyIdentity();
}

/// Lazy initialization is intentional: offline local login never calls this SDK.
class SupabaseIdentityProvider extends ChangeNotifier
    implements CloudIdentityProvider {
  SupabaseIdentityProvider(this.config, {SupabaseClient? client})
      : _injectedClient = client;
  final SupabaseClient? _injectedClient;
  final CloudAuthConfig config;
  Future<void>? _initialization;
  late CloudSecureStorage _storage;
  StreamSubscription<AuthState>? _events;
  StreamSubscription<Uri>? _links;
  final Set<String> _handledCodes = {};
  bool _initialLinkRead = false;
  bool recoveryPending = false;
  bool signedInThisVisit = false;
  bool _signedOutLocally = false;
  String? callbackError;
  SupabaseClient get _client => _injectedClient ?? Supabase.instance.client;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!config.enabled) throw StateError('Cloud identity is not configured');
    hierarchicalLoggingEnabled = true;
    Logger('supabase').level = Level.OFF;
    _storage = CloudSecureStorage(
        sha256.convert(utf8.encode(config.issuer)).toString());
    recoveryPending = recoveryPending || await _storage.isRecoveryPending();
    _signedOutLocally = await _storage.isSignedOut();
    if (_injectedClient == null) {
      await Supabase.initialize(
          url: config.url,
          publishableKey: config.publicKey,
          debug: false,
          authOptions: FlutterAuthClientOptions(
              authFlowType: AuthFlowType.pkce,
              autoRefreshToken: false,
              localStorage: _storage,
              pkceAsyncStorage: CloudPkceStorage(_storage),
              detectSessionInUri: false));
    }
    _events = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        recoveryPending = true;
        unawaited(_storage.setRecoveryPending(true).catchError((Object _) {}));
      }
      if (state.event == AuthChangeEvent.signedOut) signedInThisVisit = false;
      notifyListeners();
    }, onError: (_) {
      callbackError = 'لم يكتمل رابط الدخول. أعد المحاولة.';
      signedInThisVisit = false;
      notifyListeners();
    });
  }

  Future<void> _handleCallback(Uri uri) async {
    if (!CloudAuthConfig.acceptsCallback(uri)) return;
    final codeHash =
        sha256.convert(utf8.encode(uri.queryParameters['code']!)).toString();
    if (!_handledCodes.add(codeHash)) return;
    signedInThisVisit = false;
    try {
      // Persist the deny state before exchanging a callback for a session.
      recoveryPending = true;
      await _storage.setRecoveryPending(true);
      final response = await _client.auth.getSessionFromUrl(uri);
      recoveryPending = uri.path == '/recovery' ||
          response.redirectType == 'recovery' ||
          response.redirectType == AuthChangeEvent.passwordRecovery.name;
      await _storage.persistSession(jsonEncode(response.session.toJson()));
      await _storage.setRecoveryPending(recoveryPending);
      signedInThisVisit = !recoveryPending;
      if (!recoveryPending) {
        _signedOutLocally = false;
        await _storage.setSignedOut(false);
      }
    } catch (_) {
      callbackError =
          'انتهت صلاحية الرابط أو لم يكتمل التحقق. اطلب رابطًا جديدًا.';
      signedInThisVisit = false;
    }
    notifyListeners();
  }

  Future<bool> handleStartupCallback() async {
    callbackError = null;
    await initialize();
    if (_initialLinkRead) {
      return signedInThisVisit || recoveryPending || callbackError != null;
    }
    _initialLinkRead = true;
    final uri = await AppLinks().getInitialLink();
    if (uri == null || !CloudAuthConfig.acceptsCallback(uri)) return false;
    await _handleCallback(uri);
    return signedInThisVisit || recoveryPending || callbackError != null;
  }

  Future<String?> freshVerifiedEmail() async {
    if (!signedInThisVisit || recoveryPending) return null;
    try {
      final session = await _verifiedSession(requireNormalSignIn: false);
      return session.user.email;
    } catch (_) {
      return null;
    }
  }

  Future<void> beginVisit({bool preserveFreshSession = false}) async {
    if (!preserveFreshSession) signedInThisVisit = false;
    callbackError = null;
    await initialize();
    _links ??= AppLinks().uriLinkStream.listen((uri) {
      unawaited(_handleCallback(uri));
    }, onError: (_) {
      callbackError = 'تعذر فتح رابط الدخول.';
      notifyListeners();
    });
    if (!_initialLinkRead) {
      _initialLinkRead = true;
      final uri = await AppLinks().getInitialLink();
      if (uri != null) await _handleCallback(uri);
    }
  }

  Future<void> signIn(String email, String password) async {
    await initialize();
    await _client.auth
        .signInWithPassword(email: email.trim(), password: password);
    _signedOutLocally = false;
    await _storage.setSignedOut(false);
    recoveryPending = false;
    await _storage.setRecoveryPending(false);
    signedInThisVisit = true;
    await verifyIdentity();
  }

  Future<void> requestSignupCode(String email) async {
    await initialize();
    await _client.auth.signInWithOtp(
      email: email.trim(),
      shouldCreateUser: true,
    );
    signedInThisVisit = false;
  }

  Future<void> verifyRegistrationCode(String email, String code) async {
    await initialize();
    final response = await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.email,
    );
    if (response.session == null) {
      throw StateError('Registration verification did not create a session.');
    }
    _signedOutLocally = false;
    await _storage.setSignedOut(false);
    recoveryPending = false;
    await _storage.setRecoveryPending(false);
    signedInThisVisit = true;
    final session = await _verifiedSession(requireNormalSignIn: false);
    await _storage.persistSession(jsonEncode(session.toJson()));
    notifyListeners();
  }

  Future<void> setInitialPasswordAndSignIn(
      String email, String password) async {
    await initialize();
    final normalizedEmail = email.trim();
    final verified = await _verifiedSession(requireNormalSignIn: false);
    if ((verified.user.email ?? '').toLowerCase() !=
        normalizedEmail.toLowerCase()) {
      throw StateError('Verified email changed during registration.');
    }
    await _client.auth.updateUser(UserAttributes(password: password));
    await _client.auth.signOut(scope: SignOutScope.local);
    await _storage.removePersistedSession();
    _signedOutLocally = false;
    await _storage.setSignedOut(false);
    signedInThisVisit = false;
    await signIn(normalizedEmail, password);
  }

  Future<void> signUp(String email, String password) async {
    await initialize();
    await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    // Confirmation is completed in-app with OtpType.signup. Creating the
    // cloud identity alone never grants a local user, owner role or license.
    signedInThisVisit = false;
  }

  Future<void> verifySignupCode(String email, String code) async {
    await initialize();
    final response = await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.signup,
    );
    if (response.session == null) {
      throw StateError('Signup verification did not create a session.');
    }
    _signedOutLocally = false;
    await _storage.setSignedOut(false);
    recoveryPending = false;
    await _storage.setRecoveryPending(false);
    signedInThisVisit = true;
    final session = await _verifiedSession(requireNormalSignIn: false);
    await _storage.persistSession(jsonEncode(session.toJson()));
    notifyListeners();
  }

  Future<void> resendSignupCode(String email) async {
    await initialize();
    await _client.auth.resend(
      email: email.trim(),
      type: OtpType.signup,
    );
  }

  Future<void> resetPassword(String email) async {
    await initialize();
    await _client.auth.resetPasswordForEmail(email.trim());
    signedInThisVisit = false;
  }

  Future<void> verifyRecoveryCode(String email, String code) async {
    await initialize();
    recoveryPending = true;
    await _storage.setRecoveryPending(true);
    final response = await _client.auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: OtpType.recovery,
    );
    if (response.session == null) {
      throw StateError('Recovery verification did not create a session.');
    }
    recoveryPending = true;
    signedInThisVisit = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    await initialize();
    _signedOutLocally = true;
    signedInThisVisit = false;
    await _storage.setSignedOut(true);
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } finally {
      await _storage.removePersistedSession();
      recoveryPending = false;
      await _storage.setRecoveryPending(false);
      callbackError = null;
      notifyListeners();
    }
  }

  Future<void> updateRecoveredPassword(String password) async {
    await initialize();
    if (!recoveryPending) throw StateError('Recovery is not active');
    await _client.auth.getUser();
    await _client.auth.updateUser(UserAttributes(password: password));
    await signOut();
  }

  Future<void> oauth(OAuthProvider provider) async {
    await initialize();
    if (!config.oauthEnabled ||
        (provider != OAuthProvider.google && provider != OAuthProvider.apple)) {
      throw StateError('Provider is unavailable');
    }
    if (!await _client.auth
        .signInWithOAuth(provider, redirectTo: CloudAuthConfig.callback)) {
      throw StateError('Provider did not open');
    }
  }

  @override
  Future<VerifiedCloudIdentity> verifyIdentity() async {
    await initialize();
    if (!signedInThisVisit || recoveryPending) {
      throw StateError('Fresh sign-in required');
    }
    final session = await _verifiedSession();
    await _storage.persistSession(jsonEncode(session.toJson()));
    return VerifiedCloudIdentity(config.issuer, session.user.id);
  }

  /// Licensing may reuse a persisted session only after fresh network validation.
  /// It does not require the local-account linking flow's fresh-visit flag.
  Future<String?> verifiedAccessToken() async {
    try {
      await initialize();
      return (await _verifiedSession()).accessToken;
    } catch (_) {
      // Never propagate raw SDK errors or credential-bearing payloads.
      return null;
    }
  }

  Future<VerifiedOnboardingSession> verifiedOnboardingSession() async {
    await initialize();
    final session = await _verifiedSession();
    return VerifiedOnboardingSession(session.user.id, session.accessToken);
  }

  Future<Session> _verifiedSession({bool requireNormalSignIn = true}) async {
    if (_signedOutLocally) throw StateError('Local cloud session was revoked');
    if (recoveryPending) throw StateError('Recovery session is not permitted');
    var session = _client.auth.currentSession;
    if (session == null) throw StateError('Cloud session missing');
    if (session.isExpired) {
      session = (await _client.auth
              .refreshSession()
              .timeout(const Duration(seconds: 8)))
          .session;
    }
    if (session == null || session.expiresAt == null || session.isExpired) {
      throw StateError('Cloud session expired');
    }
    // Network validation is compulsory. Cached currentUser and JWT role claims
    // are not authorization to enter the local workshop.
    final user = (await _client.auth
            .getUser(session.accessToken)
            .timeout(const Duration(seconds: 8)))
        .user;
    if (user == null ||
        user.id != session.user.id ||
        user.id.isEmpty ||
        user.isAnonymous ||
        recoveryPending ||
        session.isExpired ||
        _client.auth.currentSession?.accessToken != session.accessToken ||
        _client.auth.currentSession?.user.id != user.id) {
      throw StateError('Cloud identity verification failed');
    }
    if (user.email == null || user.emailConfirmedAt == null) {
      throw StateError('Verified email required');
    }
    if (requireNormalSignIn) {
      final claims = jsonDecode(utf8.decode(base64Url.decode(
          base64Url.normalize(session.accessToken.split('.')[1])))) as Map;
      final amr = claims['amr'];
      if (amr is! List ||
          !amr.any(
              (x) => x is Map && ['password', 'oauth'].contains(x['method'])) ||
          amr.any((x) =>
              x is Map && ['recovery', 'invite'].contains(x['method']))) {
        throw StateError('Password sign-in required after OTP verification');
      }
    }
    return session;
  }

  @override
  void dispose() {
    _events?.cancel();
    _links?.cancel();
    super.dispose();
  }
}
