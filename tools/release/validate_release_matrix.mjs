import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const argv = process.argv.slice(2);
const valueOf = name => {
  const i = argv.indexOf(name);
  return i >= 0 ? argv[i + 1] : null;
};
const root = path.resolve(valueOf('--accounts-root') ?? process.cwd());
const controlRoot = valueOf('--control-root');
const serverRoot = valueOf('--server-root');
const fail = message => { throw new Error(`RELEASE_MATRIX_FAIL: ${message}`); };
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const matrixPath = path.join(root, 'release', 'version_matrix.json');
const matrixRaw = fs.readFileSync(matrixPath, 'utf8');
const matrix = JSON.parse(matrixRaw);
const required = [
  'matrix_schema','release_train','accounts_version','control_version',
  'server_version','commercial_contract_version','sync_contract_version',
  'accounts_db_schema_version',
];
for (const key of required) if (!(key in matrix)) fail(`missing ${key}`);
if (matrix.matrix_schema !== 1) fail('matrix_schema must be 1');
const pubspec = read('pubspec.yaml');
const accountsVersion = /^version:\s*([^\r\n]+)$/m.exec(pubspec)?.[1]?.trim();
if (accountsVersion !== matrix.accounts_version) {
  fail(`Accounts version ${accountsVersion} != ${matrix.accounts_version}`);
}
const constants = read('lib/core/services/db/database_constants.dart');
const dbVersion = Number(/static const int dbVersion = (\d+);/.exec(constants)?.[1]);
if (dbVersion !== matrix.accounts_db_schema_version) {
  fail(`Accounts DB ${dbVersion} != ${matrix.accounts_db_schema_version}`);
}
const sync = read('lib/core/services/sync/sync_contract_v3.dart');
const syncVersion = Number(/static const int version = (\d+);/.exec(sync)?.[1]);
if (syncVersion !== matrix.sync_contract_version) {
  fail(`Accounts sync contract ${syncVersion} != ${matrix.sync_contract_version}`);
}
const activation = read('lib/core/licensing/activation/activation_transport.dart');
const commercial = matrix.commercial_contract_version;
if (!activation.includes(`'contract_version': ${commercial}`) ||
    !activation.includes(`'x-yalla-contract-version', '${commercial}'`)) {
  fail(`Accounts commercial contract is not v${commercial}`);
}
const canonical = value => JSON.stringify(value);
const matrixHash = crypto.createHash('sha256').update(matrixRaw).digest('hex');
if (controlRoot) {
  const cRoot = path.resolve(controlRoot);
  const cMatrix = JSON.parse(fs.readFileSync(path.join(cRoot, 'release', 'version_matrix.json'), 'utf8'));
  if (canonical(cMatrix) !== canonical(matrix)) fail('Control matrix differs');
  const cPubspec = fs.readFileSync(path.join(cRoot, 'pubspec.yaml'), 'utf8');
  const cVersion = /^version:\s*([^\r\n]+)$/m.exec(cPubspec)?.[1]?.trim();
  if (cVersion !== matrix.control_version) {
    fail(`Control version ${cVersion} != ${matrix.control_version}`);
  }
}
if (serverRoot) {
  const sRoot = path.resolve(serverRoot);
  const sMatrix = JSON.parse(fs.readFileSync(path.join(sRoot, 'release', 'version_matrix.json'), 'utf8'));
  if (canonical(sMatrix) !== canonical(matrix)) fail('Server matrix differs');
  const pkg = JSON.parse(fs.readFileSync(path.join(sRoot, 'package.json'), 'utf8'));
  if (pkg.version !== matrix.server_version) {
    fail(`Server version ${pkg.version} != ${matrix.server_version}`);
  }
  const sSync = fs.readFileSync(path.join(sRoot, 'src', 'sync-contract-v3.mjs'), 'utf8');
  const sSyncVersion = Number(/SYNC_CONTRACT_VERSION = (\d+);/.exec(sSync)?.[1]);
  if (sSyncVersion !== matrix.sync_contract_version) fail('Server sync contract mismatch');
  const integration = fs.readFileSync(path.join(sRoot, 'src', 'accounts-integration-v2.mjs'), 'utf8');
  if (!integration.includes(`body.contract_version === ${commercial}`) ||
      !integration.includes(`'x-yalla-contract-version'] === '${commercial}'`)) {
    fail('Server commercial contract mismatch');
  }
}
if ((controlRoot && !serverRoot) || (!controlRoot && serverRoot)) {
  fail('cross-repository validation requires both --control-root and --server-root');
}
console.log(`RELEASE_MATRIX_PASS train=${matrix.release_train} sha256=${matrixHash}`);
console.log(`Accounts=${matrix.accounts_version} Control=${matrix.control_version} Server=${matrix.server_version}`);
console.log(`CommercialContract=v${commercial} SyncContract=v${matrix.sync_contract_version} DB=${dbVersion}`);
