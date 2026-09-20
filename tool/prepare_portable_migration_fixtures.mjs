// Prepare only the two synthetic migration fixtures, never application data.
// A standalone read-only SQLite artifact must not depend on absent WAL sidecars.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {gunzipSync, gzipSync} from 'node:zlib';
import {DatabaseSync} from 'node:sqlite';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = path.join(root, 'test', 'fixtures', 'migration');
const provenancePath = path.join(fixtures, 'PROVENANCE.json');
const provenance = JSON.parse(fs.readFileSync(provenancePath, 'utf8'));
if (!provenance.synthetic || provenance.containsCustomerData) throw Error('Synthetic fixtures only');
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
const quote = identifier => '"' + identifier.replaceAll('"', '""') + '"';
function facts(db) {
  const schema = db.prepare('SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name').all();
  const rows = {};
  for (const {name} of schema.filter(r => r.type === 'table')) {
    rows[name] = db.prepare(`SELECT * FROM ${quote(name)}`).all().map(r => JSON.stringify(r)).sort();
  }
  return {hash:digest(JSON.stringify({schema, rows})), tableCount:Object.keys(rows).length};
}
for (const item of provenance.fixtures) {
  if (!['commercial83', 'owner78'].includes(item.name)) throw Error('Unknown fixture');
  const gzipPath = path.join(fixtures, item.name + '.db.gz');
  const original = gunzipSync(fs.readFileSync(gzipPath));
  if (digest(original) !== item.sha256) throw Error('Fixture hash mismatch');
  if (original[18] === 1 && original[19] === 1) continue;
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'yallah_fixture_packaging_'));
  const file = path.join(scratch, item.name + '.db');
  fs.writeFileSync(file, original, {flag:'wx'});
  const db = new DatabaseSync(file);
  let before;
  try {
    if (db.prepare('PRAGMA user_version').get().user_version !== item.schema) throw Error('Schema mismatch');
    before = facts(db);
    const checkpoint = db.prepare('PRAGMA wal_checkpoint(TRUNCATE)').get();
    if (checkpoint.busy !== 0) throw Error('Fixture checkpoint is busy');
    const mode = db.prepare('PRAGMA journal_mode=DELETE').get().journal_mode;
    if (mode !== 'delete') throw Error('Fixture was not made standalone');
    if (db.prepare('PRAGMA integrity_check').get().integrity_check !== 'ok') throw Error('Fixture corruption');
    if (db.prepare('PRAGMA foreign_key_check').all().length) throw Error('Foreign key violation');
    if (facts(db).hash !== before.hash) throw Error('Schema or row data changed');
  } finally { db.close(); }
  const portable = fs.readFileSync(file);
  if (portable[18] !== 1 || portable[19] !== 1) throw Error('WAL header remains');
  const readonly = new DatabaseSync(file, {readOnly:true});
  try {
    if (readonly.prepare('PRAGMA user_version').get().user_version !== item.schema) throw Error('Readonly reopen failed');
    if (facts(readonly).hash !== before.hash) throw Error('Readonly data mismatch');
  } finally { readonly.close(); }
  item.originalWalSha256 ??= item.sha256;
  item.sha256 = digest(portable);
  item.packaging = {journalMode:'DELETE', logicalSchemaAndRowsUnchanged:true,
    logicalSha256:before.hash, tablesVerified:before.tableCount};
  fs.writeFileSync(gzipPath, gzipSync(portable));
  console.log(`${item.name}: schema ${item.schema}, ${before.tableCount} tables unchanged, standalone read-only fixture verified`);
  fs.rmSync(scratch, {recursive:true});
}
provenance.portablePackagingReference = 'https://sqlite.org/wal.html#read_only_databases';
fs.writeFileSync(provenancePath, JSON.stringify(provenance, null, 2) + '\n');
