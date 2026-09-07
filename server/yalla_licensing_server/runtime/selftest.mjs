import {
  generateKeyPairSync,
  randomUUID,
  createHash,
  createPublicKey,
  sign,
  verify,
} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

import { C06Authority } from './lib/authority.mjs';
import { canonicalize } from './lib/canonical.mjs';

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'yalla-c06-authority-'));
const authority = new C06Authority({ rootDir: root });
const code = 'YALLA-C06-SELFTEST-0001';
authority.initializeActivationCode(code);

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const der = publicKey.export({ format: 'der', type: 'spki' });
const raw = Buffer.from(der).subarray(der.length - 32);
const b64 = raw.toString('base64url');
const hash = createHash('sha256').update(raw).digest('hex');
const device = {
  organization_id: randomUUID(),
  installation_id: randomUUID(),
  device_id: randomUUID(),
  public_key: b64,
  public_key_algorithm: 'ED25519',
  public_key_sha256: hash,
  fingerprint_hash: createHash('sha256').update('selftest-device').digest('hex'),
  platform: 'ios',
  platform_version: '26.0',
  app_version: '1.0.0+18',
  identity_generation: 1,
};

const challenge = authority.beginActivation({
  api_version: 2,
  activation_code: code,
  idempotency_key: randomUUID(),
  device,
});
const proof = sign(null, Buffer.from(challenge.proof_bytes, 'base64url'), privateKey);
const completion = authority.completeActivation({
  api_version: 2,
  challenge_id: challenge.challenge_id,
  idempotency_key: challenge.idempotency_key,
  device_id: device.device_id,
  proof: { algorithm: 'ED25519', signature: proof.toString('base64url') },
});
if (completion.license_envelope?.payload?.device_id !== device.device_id) {
  throw new Error('Activation selftest failed.');
}
if (completion.license_envelope?.signature?.length !== 86) {
  throw new Error('Unexpected Ed25519 license signature.');
}
const signedCanonical = Buffer.from(
  canonicalize(completion.license_envelope.payload),
  'utf8',
);
const authorityPublic = createPublicKey(
  fs.readFileSync(path.join(root, 'secrets', 'c06-signing-public.pem')),
);
if (!verify(
  null,
  signedCanonical,
  authorityPublic,
  Buffer.from(completion.license_envelope.signature, 'base64url'),
)) {
  throw new Error('Signed license verification selftest failed.');
}
const expectedPayloadHash = createHash('sha256').update(signedCanonical).digest('hex');
if (expectedPayloadHash !== completion.license_envelope.payload_sha256) {
  throw new Error('Signed license payload hash selftest failed.');
}

const payload = completion.license_envelope.payload;
const lc = authority.beginLifecycle({
  api_version: 1,
  action: 'VALIDATE',
  license_id: payload.license_id,
  subscription_id: payload.subscription_id,
  device,
});
const lcProof = sign(null, Buffer.from(lc.proof_bytes, 'base64url'), privateKey);
const lcDone = authority.completeLifecycle({
  api_version: 1,
  challenge_id: lc.challenge_id,
  action: 'VALIDATE',
  device_id: device.device_id,
  proof: { algorithm: 'ED25519', signature: lcProof.toString('base64url') },
});
if (lcDone.license_envelope?.payload?.operational_status !== 'ACTIVE') {
  throw new Error('Lifecycle selftest failed.');
}

console.log('C06 LICENSING RUNTIME SELFTEST: PASS');
console.log(`Trusted key SHA256: ${authority.publicInfo().public_key_sha256}`);
fs.rmSync(root, { recursive: true, force: true });
