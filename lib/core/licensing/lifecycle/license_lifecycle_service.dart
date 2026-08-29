import 'dart:convert';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';

import '../activation/activation_state_repository.dart';
import '../activation/license_envelope_verifier.dart';
import 'license_lifecycle_transport.dart';
import 'license_runtime_service.dart';

abstract class LicenseLifecycleDeviceGateway {
  Future<DeviceIdentity> ensureCurrent();
  Future<DeviceProof> signChallenge(List<int> challenge);
}

class Sec011DeviceGateway implements LicenseLifecycleDeviceGateway {
  Sec011DeviceGateway([DeviceIdentityService? service])
      : _service = service ?? DeviceIdentityService();

  final DeviceIdentityService _service;

  @override
  Future<DeviceIdentity> ensureCurrent() => _service.ensureCurrent();

  @override
  Future<DeviceProof> signChallenge(List<int> challenge) =>
      _service.signChallenge(challenge);
}

/// SEC.011 explicit online validation/renewal.
///
/// Periodic scheduling is deliberately deferred to SEC.012. This service
/// provides the secure lifecycle protocol that SEC.012 will call.
class LicenseLifecycleService {
  LicenseLifecycleService({
    LicenseLifecycleDeviceGateway? deviceGateway,
    LicenseLifecycleTransport? transport,
    ActivationStateRepository? activationStateRepository,
    LicenseEnvelopeVerifier? verifier,
    LicenseRuntimeService? runtimeService,
  })  : _deviceGateway = deviceGateway ?? Sec011DeviceGateway(),
        _transport = transport ?? HttpLicenseLifecycleTransport(),
        _activationStateRepository =
            activationStateRepository ?? ActivationStateRepository(),
        _verifier = verifier ?? LicenseEnvelopeVerifier(),
        _runtimeService = runtimeService ?? LicenseRuntimeService();

  final LicenseLifecycleDeviceGateway _deviceGateway;
  final LicenseLifecycleTransport _transport;
  final ActivationStateRepository _activationStateRepository;
  final LicenseEnvelopeVerifier _verifier;
  final LicenseRuntimeService _runtimeService;

  bool get isConfigured =>
      _transport.isConfigured && _verifier.isTrustConfigured;

  Future<VerifiedLicense> validateNow() => _execute('VALIDATE');

  Future<VerifiedLicense> renewNow() => _execute('RENEW');

  Future<VerifiedLicense> _execute(String action) async {
    final current = await _activationStateRepository
        .loadAuthenticLicenseForCurrentInstallation(allowExpired: true);
    if (current == null) {
      throw const LicenseLifecycleTransportException(
        'A valid signed activation receipt is required first.',
      );
    }

    final identity = await _deviceGateway.ensureCurrent();
    final challenge = await _transport.begin(
      action: action,
      identity: identity,
      licenseId: current.licenseId,
      subscriptionId: current.subscriptionId,
    );

    final proofBytes = _decodeProofBytes(challenge.proofBytesBase64Url);
    final proof = await _deviceGateway.signChallenge(proofBytes);
    if (proof.deviceId != identity.deviceId || proof.algorithm != 'ED25519') {
      throw StateError('SEC.011 device proof identity mismatch.');
    }

    final completion = await _transport.complete(
      challenge: challenge,
      proof: proof,
    );

    // Lifecycle responses are authorization-bearing. They are accepted only as
    // a normal Yalla signed-license envelope pinned to the build trust anchor.
    final verified = await _verifier.verify(
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      identity: identity,
      now: completion.serverTime,
      requireCurrentValidity: false,
    );

    await _activationStateRepository.commitVerifiedLicenseRefresh(
      identity: identity,
      license: verified,
      lifecycleEventId: completion.lifecycleEventId,
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      serverTime: completion.serverTime,
    );
    await _runtimeService.projectServerLifecycleDecision(
      license: verified,
      serverTime: completion.serverTime,
    );

    return verified;
  }

  static List<int> _decodeProofBytes(String value) {
    if (value.isEmpty || value.length > 2048) {
      throw const LicenseLifecycleTransportException(
        'Invalid lifecycle proof payload.',
      );
    }

    try {
      final padding = List.filled((4 - value.length % 4) % 4, '=').join();
      final bytes = base64Url.decode('$value$padding');
      if (bytes.length < 16 || bytes.length > 1024) {
        throw const FormatException();
      }
      return bytes;
    } catch (_) {
      throw const LicenseLifecycleTransportException(
        'Invalid lifecycle proof payload.',
      );
    }
  }
}
