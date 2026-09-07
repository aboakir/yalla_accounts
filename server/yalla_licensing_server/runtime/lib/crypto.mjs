import {
  createHash,
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  randomBytes,
  sign,
  verify,
} from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

export const b64url = (bytes) => Buffer.from(bytes).toString('base64url');
export const fromB64url = (value) => Buffer.from(value, 'base64url');
export const sha256Hex = (bytes) =>
  createHash('sha256').update(Buffer.from(bytes)).digest('hex');

export function ensureAuthority(secretDir) {
  fs.mkdirSync(secretDir, { recursive: true });
  const privatePath = path.join(secretDir, 'c06-signing-private.pem');
  const publicPath = path.join(secretDir, 'c06-signing-public.pem');
  if (!fs.existsSync(privatePath) || !fs.existsSync(publicPath)) {
    const { privateKey, publicKey } = generateKeyPairSync('ed25519');
    fs.writeFileSync(
      privatePath,
      privateKey.export({ format: 'pem', type: 'pkcs8' }),
      { mode: 0o600 },
    );
    fs.writeFileSync(
      publicPath,
      publicKey.export({ format: 'pem', type: 'spki' }),
      { mode: 0o644 },
    );
  }
  const privateKey = createPrivateKey(fs.readFileSync(privatePath));
  const publicKey = createPublicKey(fs.readFileSync(publicPath));
  const der = publicKey.export({ format: 'der', type: 'spki' });
  const raw = Buffer.from(der).subarray(der.length - 32);
  if (raw.length !== 32) throw new Error('Unexpected Ed25519 public key size.');
  return {
    privateKey,
    publicKey,
    publicRaw: raw,
    publicKeyBase64Url: b64url(raw),
    publicKeySha256: sha256Hex(raw),
    privatePath,
    publicPath,
  };
}

export function devicePublicKey(rawBase64Url) {
  const raw = fromB64url(rawBase64Url);
  if (raw.length !== 32) throw new Error('Invalid device Ed25519 public key.');
  return createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
    format: 'der',
    type: 'spki',
  });
}

export function signBytes(privateKey, bytes) {
  return sign(null, Buffer.from(bytes), privateKey);
}

export function verifyBytes(publicKey, bytes, signature) {
  return verify(null, Buffer.from(bytes), publicKey, Buffer.from(signature));
}

export function randomProofBytes(size = 32) {
  return randomBytes(size);
}
