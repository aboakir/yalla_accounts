import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { AuthorityError, C06Authority } from './lib/authority.mjs';
import { SyncAuthority, SyncAuthorityError } from './lib/sync_authority.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const host = process.env.YALLA_C06_HOST || '127.0.0.1';
const port = Number(process.env.YALLA_C06_PORT || '8787');
const authority = new C06Authority({ rootDir: __dirname });
const syncAuthority = new SyncAuthority({ rootDir: __dirname });
const publicDir = path.join(__dirname, 'public');

function json(res, status, body) {
  const raw = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': raw.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(raw);
}

function html(res, status, raw) {
  const body = Buffer.from(raw, 'utf8');
  res.writeHead(status, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': body.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'content-security-policy':
      "default-src 'self'; style-src 'self' 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'",
  });
  res.end(body);
}

async function bodyBytes(req, limit = 384 * 1024) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > limit) throw new AuthorityError(413, 'Request body too large.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function parseBody(req) {
  const bytes = await bodyBytes(req);
  const contentType = String(req.headers['content-type'] || '').toLowerCase();
  if (contentType.includes('application/json')) {
    if (bytes.length === 0) return {};
    try {
      return JSON.parse(bytes.toString('utf8'));
    } catch {
      throw new AuthorityError(400, 'Invalid JSON request.');
    }
  }
  if (contentType.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(bytes.toString('utf8')).entries());
  }
  return {};
}

function legalPage(name) {
  return fs.readFileSync(path.join(publicDir, name), 'utf8');
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, {
        ok: true,
        service: 'yalla-c06-licensing-test-authority',
        mode: 'C06_TEST_ONLY',
        time: new Date().toISOString(),
        authority: authority.publicInfo(),
      });
    }
    if (req.method === 'GET' && url.pathname === '/.well-known/yalla-c06.json') {
      return json(res, 200, authority.publicInfo());
    }
    if (req.method === 'GET' && url.pathname === '/privacy') {
      return html(res, 200, legalPage('privacy.html'));
    }
    if (req.method === 'GET' && url.pathname === '/terms') {
      return html(res, 200, legalPage('terms.html'));
    }
    if (req.method === 'GET' && url.pathname === '/account-deletion') {
      return html(res, 200, legalPage('account-deletion.html'));
    }

    if (req.method === 'POST' && url.pathname === '/v1/activations/challenge') {
      return json(res, 200, authority.beginActivation(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/activations/complete') {
      return json(res, 200, authority.completeActivation(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/license-lifecycle/challenge') {
      return json(res, 200, authority.beginLifecycle(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/license-lifecycle/complete') {
      return json(res, 200, authority.completeLifecycle(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/sync/challenge') {
      return json(res, 200, await syncAuthority.begin(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/sync/complete') {
      return json(res, 200, await syncAuthority.complete(await parseBody(req)));
    }
    if (req.method === 'POST' && url.pathname === '/v1/account-deletion-requests') {
      const item = authority.recordDeletionRequest(await parseBody(req));
      if (String(req.headers['content-type'] || '').includes('application/json')) {
        return json(res, 202, item);
      }
      return html(
        res,
        202,
        `<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>&#1578;&#1605; &#1575;&#1587;&#1578;&#1604;&#1575;&#1605; &#1575;&#1604;&#1591;&#1604;&#1576;</title><body style="font-family:Arial,sans-serif;max-width:700px;margin:50px auto;padding:20px"><h1>&#1578;&#1605; &#1575;&#1587;&#1578;&#1604;&#1575;&#1605; &#1591;&#1604;&#1576;&#1603;</h1><p>&#1585;&#1602;&#1605; &#1575;&#1604;&#1591;&#1604;&#1576;: <strong>${item.request_id}</strong></p><p>&#1587;&#1610;&#1578;&#1605; &#1575;&#1604;&#1578;&#1593;&#1575;&#1605;&#1604; &#1605;&#1593;&#1607; &#1608;&#1601;&#1602; &#1587;&#1610;&#1575;&#1587;&#1577; &#1575;&#1604;&#1575;&#1581;&#1578;&#1601;&#1575;&#1592; &#1576;&#1575;&#1604;&#1576;&#1610;&#1575;&#1606;&#1575;&#1578;.</p></body></html>`,
      );
    }

    return json(res, 404, { message: 'Not found.' });
  } catch (error) {
    const known = error instanceof AuthorityError || error instanceof SyncAuthorityError;
    const status = known ? error.status : 500;
    const message = known ? error.message : 'Internal server error.';
    if (status >= 500) console.error(error);
    return json(res, status, { message });
  }
});

server.listen(port, host, () => {
  console.log(`Yalla C06 licensing test authority listening on http://${host}:${port}`);
  console.log(`Trusted key SHA256: ${authority.publicInfo().public_key_sha256}`);
});





