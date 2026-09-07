import { randomBytes } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { C06Authority } from './lib/authority.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const secretsDir = path.join(__dirname, 'secrets');
fs.mkdirSync(secretsDir, { recursive: true });
const codePath = path.join(secretsDir, 'C06_ACTIVATION_CODE.txt');
let code = '';
if (fs.existsSync(codePath) && !process.argv.includes('--reset-code')) {
  code = fs.readFileSync(codePath, 'utf8').trim().toUpperCase();
}
if (!code) {
  code = `YALLA-C06-${randomBytes(12).toString('hex').toUpperCase()}`;
  fs.writeFileSync(codePath, `${code}\n`, { mode: 0o600 });
}
const authority = new C06Authority({ rootDir: __dirname });
authority.initializeActivationCode(code);
const info = authority.publicInfo();
fs.writeFileSync(
  path.join(secretsDir, 'C06_TRUSTED_KEY_SHA256.txt'),
  `${info.public_key_sha256}\n`,
  { mode: 0o600 },
);
console.log('C06 TEST AUTHORITY INITIALIZED');
console.log(`Activation code: ${code}`);
console.log(`Trusted key SHA256: ${info.public_key_sha256}`);
console.log('Private signing key stays under runtime/secrets and is git-ignored.');
