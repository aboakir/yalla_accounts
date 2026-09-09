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

abstract interface class CloudIdentityProvider {
  Future<VerifiedCloudIdentity> verifyIdentity();
}

/// Lazy initialization is intentional: offline local login never calls this SDK.
class SupabaseIdentityProvider extends ChangeNotifier
    implements CloudIdentityProvider {
  SupabaseIdentityProvider(this.config);
  final CloudAuthConfig config;
  Future<void>? _initialization;
  late CloudSecureStorage _storage;
  StreamSubscription<AuthState>? _events;
  StreamSubscription<Uri>? _links;
  final Set<String> _handledCodes = {};
  bool _initialLinkRead = false;
  bool recoveryPending = false;
  bool signedInThisVisit = false;
  String? callbackError;
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> initialize() => _initialization ??= _initialize();
  Future<void> _initialize() async {
    if (!config.enabled) throw StateError('Cloud identity is not configured');
    hierarchicalLoggingEnabled = true;
    Logger('supabase').level = Level.OFF;
    _storage = CloudSecureStorage(
        sha256.convert(utf8.encode(config.issuer)).toString());
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
    _events = _client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        recoveryPending = true;
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
      final response = await _client.auth.getSessionFromUrl(uri);
      recoveryPending = uri.path == '/recovery' ||
          response.redirectType == 'recovery' ||
          response.redirectType == AuthChangeEvent.passwordRecovery.name;
      await _storage.persistSession(jsonEncode(response.session.toJson()));
      signedInThisVisit = !recoveryPending;
    } catch (_) {
      callbackError =
          'انتهت صلاحية الرابط أو لم يكتمل التحقق. اطلب رابطًا جديدًا.';
      signedInThisVisit = false;
    }
    notifyListeners();
  }

  Future<void> beginVisit() async {
    signedInThisVisit = false;
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
    recoveryPending = false;
    signedInThisVisit = true;
    await verifyIdentity();
  }

  Future<void> signUp(String email, String password) async {
    await initialize();
    await _client.auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: CloudAuthConfig.callback);
    // Account creation grants no local user, owner role, workshop or license.
    signedInThisVisit = false;
  }

  Future<void> resetPassword(String email) async {
    await initialize();
    await _client.auth.resetPasswordForEmail(email.trim(),
        redirectTo: CloudAuthConfig.recovery);
  }

  Future<void> updateRecoveredPassword(String password) async {
    await initialize();
    if (!recoveryPending) throw StateError('Recovery is not active');
    await _client.auth.getUser();
    await _client.auth.updateUser(UserAttributes(password: password));
    recoveryPending = false;
    signedInThisVisit = false;
    await _client.auth.signOut(scope: SignOutScope.local);
    notifyListeners();
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
    var session = _client.auth.currentSession;
    if (session == null) throw StateError('Cloud session missing');
    if (session.isExpired) {
      session = (await _client.auth.refreshSession()).session;
    }
    if (session == null) throw StateError('Cloud session expired');
    // Network validation is compulsory. Cached currentUser and JWT role claims
    // are not authorization to enter the local workshop.
    final user = (await _client.auth.getUser(session.accessToken)).user;
    if (user == null || user.id != session.user.id || user.id.isEmpty) {
      throw StateError('Cloud identity verification failed');
    }
    await _storage.persistSession(jsonEncode(session.toJson()));
    return VerifiedCloudIdentity(config.issuer, user.id);
  }

  @override
  void dispose() {
    _events?.cancel();
    _links?.cancel();
    super.dispose();
  }
}
