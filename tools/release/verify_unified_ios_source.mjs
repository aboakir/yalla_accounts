import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const expected = JSON.parse(fs.readFileSync('release/CODEMAGIC_OWNER_SOURCE.json', 'utf8'));
const git = (...args) => execFileSync('git', args, {encoding:'utf8'}).trim();
for (const [file, hash] of Object.entries(expected.trees)) {
  if (git('rev-parse', `HEAD:${file}`) !== hash) throw new Error(`Wrong source tree: ${file}`);
}
const version = fs.readFileSync('pubspec.yaml','utf8').match(/^version:\s*(.+)$/m)?.[1].trim();
const schema = Number(fs.readFileSync('lib/core/services/db/database_constants.dart','utf8').match(/dbVersion\s*=\s*(\d+)/)?.[1]);
if (version !== expected.appVersion || schema !== expected.databaseSchema) throw new Error('Release identity mismatch');
git('diff', '--exit-code', '--', 'lib', 'assets', 'pubspec.yaml', 'pubspec.lock');
const out = path.join('build','ios','unified_evidence');
fs.mkdirSync(out,{recursive:true});
const record = {...expected, buildCommit:git('rev-parse','HEAD'), checkedAt:new Date().toISOString(),
  codemagicBuildId:process.env.CM_BUILD_ID ?? null,
  lockfileSha256:createHash('sha256').update(fs.readFileSync('pubspec.lock')).digest('hex')};
fs.writeFileSync(path.join(out,'SOURCE_PROVENANCE.json'),JSON.stringify(record,null,2)+'\n');
console.log(`Verified ${version}, DB${schema}, base ${expected.baseCommit}, build ${record.buildCommit}`);
