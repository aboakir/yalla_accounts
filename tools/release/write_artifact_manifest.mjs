import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

const argv = process.argv.slice(2);
const valueOf = name => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
};
const component = valueOf('--component');
const out = valueOf('--out') ?? 'dist/release-manifest.json';
const artifacts = [];
for (let i = 0; i < argv.length; i += 1) {
  if (argv[i] === '--artifact') artifacts.push(argv[i + 1]);
}
if (!component || artifacts.length === 0) {
  throw new Error('usage: --component NAME --artifact FILE [--artifact FILE] [--out FILE]');
}
const matrixRaw = fs.readFileSync('release/version_matrix.json', 'utf8');
const matrix = JSON.parse(matrixRaw);
const matrixSha256 = crypto.createHash('sha256').update(matrixRaw).digest('hex');
const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const files = artifacts.map(file => {
  const data = fs.readFileSync(file);
  return {
    path: file.replaceAll('\\', '/'),
    bytes: data.length,
    sha256: crypto.createHash('sha256').update(data).digest('hex'),
  };
});
const manifest = {
  manifest_schema: 1,
  component,
  release_train: matrix.release_train,
  matrix_sha256: matrixSha256,
  source_commit: sourceCommit,
  versions: matrix,
  toolchain: {
    flutter: process.env.FLUTTER_VERSION ?? null,
    node: process.version,
  },
  artifacts: files,
};
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
console.log(`RELEASE_MANIFEST_PASS ${out}`);
for (const file of files) console.log(`${file.sha256}  ${file.path}`);
