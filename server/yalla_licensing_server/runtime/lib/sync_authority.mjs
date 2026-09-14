import { randomUUID } from 'node:crypto';
import path from 'node:path';

import {
  devicePublicKey,
  fromB64url,
  randomProofBytes,
  sha256Hex,
  verifyBytes,
} from './crypto.mjs';
import { JsonStore } from './store.mjs';
import { SupabaseBridge, SupabaseBridgeError } from './supabase_bridge.mjs';

const iso = (value = new Date()) => value.toISOString();

function required(value, name) {
  const text = String(value ?? '').trim();
  if (!text) throw new SyncAuthorityError(400, `Missing field: ${name}.`);
  return text;
}

function uuid(value, name) {
  const text = required(value, name);
  if (!/^[0-9a-fA-F-]{32,36}$/.test(text)) {
    throw new SyncAuthorityError(400, `Invalid UUID field: ${name}.`);
  }
  return text;
}

function cleanDevice(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new SyncAuthorityError(400, 'Device payload is required.');
  }
  const device = {
    organization_id: uuid(input.organization_id, 'device.organization_id'),
    installation_id: uuid(input.installation_id, 'device.installation_id'),
    device_id: uuid(input.device_id, 'device.device_id'),
    public_key: required(input.public_key, 'device.public_key'),
    public_key_algorithm: required(
      input.public_key_algorithm,
      'device.public_key_algorithm',
    ).toUpperCase(),
    public_key_sha256: required(
      input.public_key_sha256,
      'device.public_key_sha256',
    ).toLowerCase(),
    fingerprint_hash: required(input.fingerprint_hash, 'device.fingerprint_hash'),
    platform: required(input.platform, 'device.platform'),
    platform_version: input.platform_version == null ? null : String(input.platform_version),
    app_version: required(input.app_version, 'device.app_version'),
    identity_generation: Number(input.identity_generation ?? 0),
  };
  if (device.public_key_algorithm !== 'ED25519') {
    throw new SyncAuthorityError(400, 'Only ED25519 device keys are supported.');
  }
  const raw = fromB64url(device.public_key);
  if (raw.length !== 32 || sha256Hex(raw) !== device.public_key_sha256) {
    throw new SyncAuthorityError(400, 'Device public key hash mismatch.');
  }
  if (!Number.isInteger(device.identity_generation) || device.identity_generation < 1) {
    throw new SyncAuthorityError(400, 'Invalid device identity generation.');
  }
  return device;
}

function cleanMessage(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new SyncAuthorityError(400, 'Sync message is required.');
  }
  const message = {
    message_id: required(input.message_id, 'message.message_id'),
    channel: required(input.channel, 'message.channel'),
    operation: required(input.operation, 'message.operation').toUpperCase(),
    entity_type: required(input.entity_type, 'message.entity_type'),
    entity_id: required(input.entity_id, 'message.entity_id'),
    idempotency_key: required(input.idempotency_key, 'message.idempotency_key'),
    payload_json: String(input.payload_json ?? ''),
    payload_sha256: required(
      input.payload_sha256,
      'message.payload_sha256',
    ).toLowerCase(),
    attempt_count: Number(input.attempt_count ?? 0),
  };
  if (message.channel !== 'sync') {
    throw new SyncAuthorityError(400, 'Sync channel must be sync.');
  }
  if (!['UPSERT', 'DELETE'].includes(message.operation)) {
    throw new SyncAuthorityError(400, 'Unsupported sync operation.');
  }
  if (!/^[0-9a-f]{64}$/.test(message.payload_sha256)) {
    throw new SyncAuthorityError(400, 'Invalid sync payload hash.');
  }
  if (!Number.isInteger(message.attempt_count) || message.attempt_count < 0) {
    throw new SyncAuthorityError(400, 'Invalid sync attempt count.');
  }
  if (Buffer.byteLength(message.payload_json, 'utf8') > 262144) {
    throw new SyncAuthorityError(413, 'Sync payload is too large.');
  }
  const actualHash = sha256Hex(Buffer.from(message.payload_json, 'utf8'));
  if (actualHash !== message.payload_sha256) {
    throw new SyncAuthorityError(400, 'Sync payload hash mismatch.');
  }
  let payload;
  try {
    payload = JSON.parse(message.payload_json);
  } catch {
    throw new SyncAuthorityError(400, 'Sync payload JSON is invalid.');
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new SyncAuthorityError(400, 'Sync payload must be a JSON object.');
  }
  if (message.message_id.length > 300 ||
      message.entity_type.length > 80 ||
      message.entity_id.length > 160 ||
      message.idempotency_key.length > 300) {
    throw new SyncAuthorityError(400, 'Sync message field is too long.');
  }
  return message;
}

export class SyncAuthorityError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export class SyncAuthority {
  constructor({ rootDir, bridge = null }) {
    this.bridge = bridge ?? new SupabaseBridge();
    this.store = new JsonStore(path.join(rootDir, 'data', 'sync-challenges.json'));
  }

  get isConfigured() {
    return this.bridge.isConfigured;
  }

  _mapBridgeError(error) {
    if (error instanceof SupabaseBridgeError) {
      return new SyncAuthorityError(error.status || 500, String(error.message || 'Sync bridge failure.'));
    }
    return error;
  }

  async begin(body, now = new Date()) {
    if (Number(body?.api_version) !== 1) {
      throw new SyncAuthorityError(400, 'api_version must be 1.');
    }
    const licenseId = uuid(body.license_id, 'license_id');
    const subscriptionId = uuid(body.subscription_id, 'subscription_id');
    const device = cleanDevice(body.device);
    const message = cleanMessage(body.message);

    let context;
    try {
      context = await this.bridge.prepareLifecycle({
        licenseId,
        subscriptionId,
        device,
        action: 'VALIDATE',
      });
    } catch (error) {
      throw this._mapBridgeError(error);
    }

    const operational = String(context?.operational_status || '').toUpperCase();
    if (!['ACTIVE', 'TRIAL', 'GRACE'].includes(operational)) {
      throw new SyncAuthorityError(403, `Sync is not allowed in ${operational || 'UNKNOWN'} state.`);
    }

    const challengeId = randomUUID();
    const proofBytes = randomProofBytes(32);
    const expiresAt = new Date(now.getTime() + 5 * 60 * 1000);
    const response = {
      challenge_id: challengeId,
      proof_bytes: proofBytes.toString('base64url'),
      expires_at: iso(expiresAt),
    };

    const state = this.store.load();
    state.syncChallenges ??= {};
    state.syncChallenges[challengeId] = {
      challengeId,
      licenseId,
      subscriptionId,
      device,
      message,
      proofBytes: proofBytes.toString('base64url'),
      expiresAt: iso(expiresAt),
      completed: false,
      response,
      completionResponse: null,
    };
    this.store.save(state);
    return response;
  }

  async complete(body, now = new Date()) {
    if (Number(body?.api_version) !== 1) {
      throw new SyncAuthorityError(400, 'api_version must be 1.');
    }
    const challengeId = uuid(body.challenge_id, 'challenge_id');
    const deviceId = uuid(body.device_id, 'device_id');
    const state = this.store.load();
    state.syncChallenges ??= {};
    const challenge = state.syncChallenges[challengeId];
    if (!challenge) {
      throw new SyncAuthorityError(404, 'Sync challenge not found.');
    }
    if (challenge.completed && challenge.completionResponse) {
      return challenge.completionResponse;
    }
    if (new Date(challenge.expiresAt).getTime() <= now.getTime()) {
      throw new SyncAuthorityError(410, 'Sync challenge expired.');
    }
    if (challenge.device.device_id !== deviceId) {
      throw new SyncAuthorityError(409, 'Sync device mismatch.');
    }

    const proof = body?.proof ?? {};
    if (String(proof.algorithm ?? '').toUpperCase() !== 'ED25519') {
      throw new SyncAuthorityError(400, 'Invalid proof algorithm.');
    }
    const signature = fromB64url(required(proof.signature, 'proof.signature'));
    if (signature.length !== 64) {
      throw new SyncAuthorityError(400, 'Invalid sync proof signature.');
    }
    const publicKey = devicePublicKey(challenge.device.public_key);
    if (!verifyBytes(publicKey, fromB64url(challenge.proofBytes), signature)) {
      throw new SyncAuthorityError(403, 'Sync device proof verification failed.');
    }

    let recorded;
    try {
      recorded = await this.bridge.recordSyncMutation({
        licenseId: challenge.licenseId,
        subscriptionId: challenge.subscriptionId,
        device: challenge.device,
        message: challenge.message,
      });
    } catch (error) {
      throw this._mapBridgeError(error);
    }

    const completionResponse = {
      accepted: recorded?.accepted === true,
      duplicate: recorded?.duplicate === true,
      remote_id: recorded?.remote_id ?? null,
      idempotency_key: String(recorded?.idempotency_key || challenge.message.idempotency_key),
      accepted_at: recorded?.accepted_at ?? null,
      server_time: iso(now),
    };
    if (!completionResponse.accepted) {
      throw new SyncAuthorityError(502, 'Sync mutation was not accepted.');
    }

    challenge.completed = true;
    challenge.completionResponse = completionResponse;
    state.syncChallenges[challengeId] = challenge;
    this.store.save(state);
    return completionResponse;
  }
}
