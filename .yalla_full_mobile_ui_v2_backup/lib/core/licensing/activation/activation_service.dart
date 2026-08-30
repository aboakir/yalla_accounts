import 'dart:convert';

import 'package:yalla_accounts/core/device_identity/device_identity.dart';
import 'package:yalla_accounts/core/device_identity/device_identity_service.dart';

import 'activation_state_repository.dart';
import 'activation_transport.dart';
import 'license_envelope_verifier.dart';

abstract class ActivationDeviceIdentityGateway {
  Future<DeviceIdentity> ensureCurrent();
  Future<DeviceProof> signChallenge(List<int> challenge);
}

class Sec005DeviceIdentityGateway implements ActivationDeviceIdentityGateway {
  Sec005DeviceIdentityGateway([DeviceIdentityService? service])
      : _service = service ?? DeviceIdentityService();

  final DeviceIdentityService _service;

  @override
  Future<DeviceIdentity> ensureCurrent() => _service.ensureCurrent();

  @override
  Future<DeviceProof> signChallenge(List<int> challenge) =>
      _service.signChallenge(challenge);
}

class ActivationService {
  ActivationService({
    ActivationDeviceIdentityGateway? deviceIdentity,
    ActivationTransport? transport,
    ActivationStateRepository? stateRepository,
    LicenseEnvelopeVerifier? verifier,
  })  : _deviceIdentity = deviceIdentity ?? Sec005DeviceIdentityGateway(),
        _transport = transport ?? HttpActivationTransport(),
        _stateRepository = stateRepository ?? ActivationStateRepository(),
        _verifier = verifier ?? LicenseEnvelopeVerifier();

  final ActivationDeviceIdentityGateway _deviceIdentity;
  final ActivationTransport _transport;
  final ActivationStateRepository _stateRepository;
  final LicenseEnvelopeVerifier _verifier;

  bool get isConfigured =>
      _transport.isConfigured && _verifier.isTrustConfigured;

  Future<VerifiedLicense> activateFirstInstallation(
      String activationCode) async {
    final identity = await _deviceIdentity.ensureCurrent();
    final challenge = await _transport.beginFirstActivation(
      activationCode: activationCode,
      identity: identity,
    );
    final proofBytes = _decodeProofBytes(challenge.proofBytesBase64Url);
    final proof = await _deviceIdentity.signChallenge(proofBytes);
    if (proof.deviceId != identity.deviceId || proof.algorithm != 'ED25519') {
      throw StateError('SEC.006 device proof identity mismatch.');
    }

    final completion = await _transport.completeFirstActivation(
      challenge: challenge,
      proof: proof,
    );
    final verified = await _verifier.verify(
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      identity: identity,
      now: completion.serverTime,
    );
    await _stateRepository.commitVerifiedActivation(
      identity: identity,
      license: verified,
      activationId: completion.activationId,
      envelope: completion.licenseEnvelope,
      verificationKeyset: completion.verificationKeyset,
      serverTime: completion.serverTime,
    );
    return verified;
  }

  static List<int> _decodeProofBytes(String value) {
    if (value.isEmpty || value.length > 2048) {
      throw const ActivationTransportException(
          'Invalid activation proof payload.');
    }
    try {
      final padding = List.filled((4 - value.length % 4) % 4, '=').join();
      final bytes = base64Url.decode('$value$padding');
      if (bytes.length < 16 || bytes.length > 1024) {
        throw const FormatException();
      }
      return bytes;
    } catch (_) {
      throw const ActivationTransportException(
          'Invalid activation proof payload.');
    }
  }
}
