import { createHash, randomUUID } from 'node:crypto';
import {
  b64url,
  devicePublicKey,
  ensureAuthority,
  fromB64url,
  randomProofBytes,
  sha256Hex,
  signBytes,
  verifyBytes,
} from './crypto.mjs';
import { canonicalize } from './canonical.mjs';
import { JsonStore } from './store.mjs';
import path from 'node:path';

const iso = (d = new Date()) => d.toISOString();
const plusDays = (base, days) =>
  new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
const minusMinutes = (base, minutes) =>
  new Date(base.getTime() - minutes * 60 * 1000);

function hashActivationCode(code) {
  return createHash('sha256').update(code.trim().toUpperCase(), 'utf8').digest('hex');
}

function requireString(value, name) {
  const text = String(value ?? '').trim();
  if (!text) throw new AuthorityError(400, `Missing field: ${name}.`);
  return text;
}

function requireUuidLike(value, name) {
  const text = requireString(value, name);
  if (!/^[0-9a-fA-F-]{32,36}$/.test(text)) {
    throw new AuthorityError(400, `Invalid UUID field: ${name}.`);
  }
  return text;
}

function cleanDevice(input) {
  if (!input || typeof input !== 'object') {
    throw new AuthorityError(400, 'Device registration payload is required.');
  }
  const device = {
    organization_id: requireUuidLike(input.organization_id, 'device.organization_id'),
    installation_id: requireUuidLike(input.installation_id, 'device.installation_id'),
    device_id: requireUuidLike(input.device_id, 'device.device_id'),
    public_key: requireString(input.public_key, 'device.public_key'),
    public_key_algorithm: requireString(
      input.public_key_algorithm,
      'device.public_key_algorithm',
    ).toUpperCase(),
    public_key_sha256: requireString(
      input.public_key_sha256,
      'device.public_key_sha256',
    ).toLowerCase(),
    fingerprint_hash: requireString(input.fingerprint_hash, 'device.fingerprint_hash'),
    platform: requireString(input.platform, 'device.platform'),
    platform_version: input.platform_version == null
      ? null
      : String(input.platform_version),
    app_version: requireString(input.app_version, 'device.app_version'),
    identity_generation: Number(input.identity_generation ?? 0),
  };
  if (device.public_key_algorithm !== 'ED25519') {
    throw new AuthorityError(400, 'Only ED25519 device keys are supported.');
  }
  const publicRaw = fromB64url(device.public_key);
  if (publicRaw.length !== 32 || sha256Hex(publicRaw) !== device.public_key_sha256) {
    throw new AuthorityError(400, 'Device public key hash mismatch.');
  }
  if (!Number.isInteger(device.identity_generation) || device.identity_generation < 1) {
    throw new AuthorityError(400, 'Invalid device identity generation.');
  }
  return device;
}

export class AuthorityError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export class C06Authority {
  constructor({ rootDir }) {
    this.rootDir = rootDir;
    this.secretDir = path.join(rootDir, 'secrets');
    this.dataDir = path.join(rootDir, 'data');
    this.store = new JsonStore(path.join(this.dataDir, 'c06-state.json'));
    this.keys = ensureAuthority(this.secretDir);
    this.kid = 'YALLA-LIC-C06-TEST-2026';
    this.keyNotBefore = '2026-09-01T00:00:00.000Z';
  }

  publicInfo() {
    return {
      mode: 'C06_TEST_ONLY',
      issuer: 'yalla-licensing',
      kid: this.kid,
      public_key: this.keys.publicKeyBase64Url,
      public_key_sha256: this.keys.publicKeySha256,
    };
  }

  initializeActivationCode(code) {
    const normalized = String(code).trim().toUpperCase();
    if (normalized.length < 12 || normalized.length > 96) {
      throw new Error('Activation code must be 12-96 characters.');
    }
    const state = this.store.load();
    state.activationCodeSha256 = hashActivationCode(normalized);
    this.store.save(state);
  }

  verificationKeyset(now = new Date()) {
    return {
      issuer: 'yalla-licensing',
      generated_at: iso(now),
      keys: [
        {
          kid: this.kid,
          alg: 'EdDSA',
          public_key: this.keys.publicKeyBase64Url,
          public_key_sha256: this.keys.publicKeySha256,
          status: 'ACTIVE',
          not_before: this.keyNotBefore,
          not_after: null,
          revoked_at: null,
        },
      ],
    };
  }

  beginActivation(body, now = new Date()) {
    if (Number(body?.api_version) !== 2) {
      throw new AuthorityError(400, 'api_version must be 2.');
    }
    const activationCode = requireString(body.activation_code, 'activation_code')
      .toUpperCase();
    const idempotencyKey = requireUuidLike(body.idempotency_key, 'idempotency_key');
    const device = cleanDevice(body.device);
    const state = this.store.load();
    if (!state.activationCodeSha256 ||
        hashActivationCode(activationCode) !== state.activationCodeSha256) {
      throw new AuthorityError(403, 'Activation code rejected.');
    }

    const existing = Object.values(state.activationChallenges).find(
      (item) => item.idempotencyKey === idempotencyKey,
    );
    if (existing) return existing.response;

    const challengeId = randomUUID();
    const proofBytes = randomProofBytes(32);
    const expiresAt = new Date(now.getTime() + 5 * 60 * 1000);
    const response = {
      challenge_id: challengeId,
      idempotency_key: idempotencyKey,
      proof_bytes: b64url(proofBytes),
      expires_at: iso(expiresAt),
    };
    state.activationChallenges[challengeId] = {
      challengeId,
      idempotencyKey,
      proofBytes: b64url(proofBytes),
      expiresAt: iso(expiresAt),
      device,
      completed: false,
      response,
      completionResponse: null,
    };
    this.store.save(state);
    return response;
  }

  completeActivation(body, now = new Date()) {
    if (![1, 2].includes(Number(body?.api_version))) {
      throw new AuthorityError(400, 'Unsupported activation completion api_version.');
    }
    const challengeId = requireUuidLike(body.challenge_id, 'challenge_id');
    const idempotencyKey = requireUuidLike(body.idempotency_key, 'idempotency_key');
    const deviceId = requireUuidLike(body.device_id, 'device_id');
    const state = this.store.load();
    const challenge = state.activationChallenges[challengeId];
    if (!challenge || challenge.idempotencyKey !== idempotencyKey) {
      throw new AuthorityError(404, 'Activation challenge not found.');
    }
    if (challenge.completed && challenge.completionResponse) {
      return challenge.completionResponse;
    }
    if (new Date(challenge.expiresAt).getTime() <= now.getTime()) {
      throw new AuthorityError(410, 'Activation challenge expired.');
    }
    if (challenge.device.device_id !== deviceId) {
      throw new AuthorityError(409, 'Activation device mismatch.');
    }
    const proof = body?.proof ?? {};
    if (String(proof.algorithm ?? '').toUpperCase() !== 'ED25519') {
      throw new AuthorityError(400, 'Invalid proof algorithm.');
    }
    const signature = fromB64url(requireString(proof.signature, 'proof.signature'));
    if (signature.length !== 64) {
      throw new AuthorityError(400, 'Invalid proof signature.');
    }
    const deviceKey = devicePublicKey(challenge.device.public_key);
    if (!verifyBytes(deviceKey, fromB64url(challenge.proofBytes), signature)) {
      throw new AuthorityError(403, 'Device proof verification failed.');
    }

    const orgId = challenge.device.organization_id;
    let subscription = state.subscriptions[orgId];
    if (!subscription) {
      subscription = {
        subscriptionId: randomUUID(),
        organizationId: orgId,
        status: 'ACTIVE',
        createdAt: iso(now),
        expiresAt: iso(plusDays(now, 365)),
        entitlementRevision: 1,
      };
      state.subscriptions[orgId] = subscription;
    }

    const deviceCount = Object.values(state.devices).filter(
      (d) => d.organizationId === orgId && d.status === 'ACTIVE',
    ).length;
    if (!state.devices[deviceId] && deviceCount >= 3) {
      throw new AuthorityError(409, 'MAX_DEVICES reached for C06 test authority.');
    }
    state.devices[deviceId] = {
      organizationId: orgId,
      installationId: challenge.device.installation_id,
      deviceId,
      publicKey: challenge.device.public_key,
      publicKeySha256: challenge.device.public_key_sha256,
      status: 'ACTIVE',
      registeredAt: state.devices[deviceId]?.registeredAt ?? iso(now),
      updatedAt: iso(now),
    };

    const existingLicense = Object.values(state.licenses).find(
      (l) => l.deviceId === deviceId && l.organizationId === orgId,
    );
    const licenseId = existingLicense?.licenseId ?? randomUUID();
    const payload = this.#licensePayload({
      now,
      licenseId,
      subscription,
      device: challenge.device,
      operationalStatus: 'ACTIVE',
    });
    const envelope = this.#signEnvelope(payload);
    state.licenses[licenseId] = {
      licenseId,
      subscriptionId: subscription.subscriptionId,
      organizationId: orgId,
      deviceId,
      installationId: challenge.device.installation_id,
      devicePublicKeySha256: challenge.device.public_key_sha256,
      expiresAt: payload.expires_at,
      operationalStatus: payload.operational_status,
      lastPayload: payload,
      updatedAt: iso(now),
    };

    const completionResponse = {
      activation_id: randomUUID(),
      license_envelope: envelope,
      verification_keyset: this.verificationKeyset(now),
      server_time: iso(now),
    };
    challenge.completed = true;
    challenge.completionResponse = completionResponse;
    state.activationChallenges[challengeId] = challenge;
    this.store.save(state);
    return completionResponse;
  }

  beginLifecycle(body, now = new Date()) {
    if (Number(body?.api_version) !== 1) {
      throw new AuthorityError(400, 'api_version must be 1.');
    }
    const action = requireString(body.action, 'action').toUpperCase();
    if (!['VALIDATE', 'RENEW'].includes(action)) {
      throw new AuthorityError(400, 'Unsupported lifecycle action.');
    }
    const licenseId = requireUuidLike(body.license_id, 'license_id');
    const subscriptionId = requireUuidLike(body.subscription_id, 'subscription_id');
    const device = cleanDevice(body.device);
    const state = this.store.load();
    const license = state.licenses[licenseId];
    if (!license ||
        license.subscriptionId !== subscriptionId ||
        license.deviceId !== device.device_id ||
        license.organizationId !== device.organization_id ||
        license.installationId !== device.installation_id ||
        license.devicePublicKeySha256 !== device.public_key_sha256) {
      throw new AuthorityError(409, 'Lifecycle binding mismatch.');
    }

    const challengeId = randomUUID();
    const proofBytes = randomProofBytes(32);
    const expiresAt = new Date(now.getTime() + 5 * 60 * 1000);
    const response = {
      challenge_id: challengeId,
      proof_bytes: b64url(proofBytes),
      expires_at: iso(expiresAt),
    };
    state.lifecycleChallenges[challengeId] = {
      challengeId,
      action,
      licenseId,
      subscriptionId,
      proofBytes: b64url(proofBytes),
      expiresAt: iso(expiresAt),
      device,
      completed: false,
      response,
      completionResponse: null,
    };
    this.store.save(state);
    return response;
  }

  completeLifecycle(body, now = new Date()) {
    if (Number(body?.api_version) !== 1) {
      throw new AuthorityError(400, 'api_version must be 1.');
    }
    const challengeId = requireUuidLike(body.challenge_id, 'challenge_id');
    const action = requireString(body.action, 'action').toUpperCase();
    const deviceId = requireUuidLike(body.device_id, 'device_id');
    const state = this.store.load();
    const challenge = state.lifecycleChallenges[challengeId];
    if (!challenge || challenge.action !== action) {
      throw new AuthorityError(404, 'Lifecycle challenge not found.');
    }
    if (challenge.completed && challenge.completionResponse) {
      return challenge.completionResponse;
    }
    if (new Date(challenge.expiresAt).getTime() <= now.getTime()) {
      throw new AuthorityError(410, 'Lifecycle challenge expired.');
    }
    if (challenge.device.device_id !== deviceId) {
      throw new AuthorityError(409, 'Lifecycle device mismatch.');
    }
    const proof = body?.proof ?? {};
    if (String(proof.algorithm ?? '').toUpperCase() !== 'ED25519') {
      throw new AuthorityError(400, 'Invalid proof algorithm.');
    }
    const signature = fromB64url(requireString(proof.signature, 'proof.signature'));
    if (signature.length !== 64) {
      throw new AuthorityError(400, 'Invalid lifecycle signature.');
    }
    const deviceKey = devicePublicKey(challenge.device.public_key);
    if (!verifyBytes(deviceKey, fromB64url(challenge.proofBytes), signature)) {
      throw new AuthorityError(403, 'Lifecycle device proof verification failed.');
    }

    const license = state.licenses[challenge.licenseId];
    const subscription = state.subscriptions[license.organizationId];
    if (!license || !subscription) {
      throw new AuthorityError(404, 'License or subscription not found.');
    }
    if (action === 'RENEW') {
      subscription.expiresAt = iso(plusDays(now, 365));
      subscription.entitlementRevision += 1;
      state.subscriptions[license.organizationId] = subscription;
    }

    const operationalStatus =
      subscription.status === 'ACTIVE' ? 'ACTIVE' : subscription.status;
    const payload = this.#licensePayload({
      now,
      licenseId: license.licenseId,
      subscription,
      device: challenge.device,
      operationalStatus,
    });
    const envelope = this.#signEnvelope(payload);
    license.expiresAt = payload.expires_at;
    license.operationalStatus = payload.operational_status;
    license.lastPayload = payload;
    license.updatedAt = iso(now);
    state.licenses[license.licenseId] = license;

    const completionResponse = {
      lifecycle_event_id: randomUUID(),
      server_time: iso(now),
      license_envelope: envelope,
      verification_keyset: this.verificationKeyset(now),
    };
    challenge.completed = true;
    challenge.completionResponse = completionResponse;
    state.lifecycleChallenges[challengeId] = challenge;
    this.store.save(state);
    return completionResponse;
  }

  recordDeletionRequest(data, now = new Date()) {
    const state = this.store.load();
    const request = {
      request_id: randomUUID(),
      created_at: iso(now),
      organization_or_account: String(data.organization_or_account ?? '').trim(),
      contact: String(data.contact ?? '').trim(),
      note: String(data.note ?? '').trim(),
      status: 'RECEIVED',
    };
    state.accountDeletionRequests.push(request);
    this.store.save(state);
    return request;
  }

  #licensePayload({ now, licenseId, subscription, device, operationalStatus }) {
    const validationRequired = plusDays(now, 30);
    const validationGrace = plusDays(now, 37);
    return {
      schema_version: 1,
      issuer: 'yalla-licensing',
      license_id: licenseId,
      organization_id: device.organization_id,
      subscription_id: subscription.subscriptionId,
      device_id: device.device_id,
      installation_id: device.installation_id,
      device_public_key_sha256: device.public_key_sha256,
      issued_at: iso(now),
      not_before: iso(minusMinutes(now, 1)),
      expires_at: subscription.expiresAt,
      entitlement_revision: subscription.entitlementRevision,
      entitlements: {
        ACCOUNTING_CORE: true,
        MAX_USERS: 10,
        MAX_DEVICES: 3,
        WORKSHOP_REPAIRS: true,
        BACKUP: true,
        REPORTS: true,
      },
      operational_status: operationalStatus,
      validation_required_at: iso(validationRequired),
      validation_grace_until: iso(validationGrace),
    };
  }

  #signEnvelope(payload) {
    const canonical = canonicalize(payload);
    const canonicalBytes = Buffer.from(canonical, 'utf8');
    const signature = signBytes(this.keys.privateKey, canonicalBytes);
    return {
      typ: 'YALLA-LICENSE',
      alg: 'EdDSA',
      kid: this.kid,
      payload,
      payload_sha256: sha256Hex(canonicalBytes),
      signature: b64url(signature),
    };
  }
}
