#!/usr/bin/env node
'use strict';
/**
 * dramalive-analysis — reference backend.
 *
 * Dependency-free Node HTTP server implementing the Xtream Codes
 * `player_api.php` contract plus the discovery endpoints described in
 * docs/05-API.md.
 *
 *   node src/index.js
 *   PORT=9000 node src/index.js
 *   PASSTHROUGH=1 node src/index.js     # proxy the catalog's own `source` URLs
 *
 * Binds 0.0.0.0 so it works behind the sandbox preview proxy.
 */

const http = require('http');
const playerApi = require('./routes/player_api');
const discovery = require('./routes/discovery');
const hlsRoutes = require('./routes/hls');

const HOST = process.env.HOST || '0.0.0.0';
const PORT = Number(process.env.PORT || 8080);
const RATE_LIMIT = Number(process.env.RATE_LIMIT || 120); // req/min per credential
const RATE_WINDOW_MS = 60_000;

/* ------------------------------------------------------------- rate limit */

const buckets = new Map();

function rateKey(req, query) {
  const cred = query.username ? `${query.username}` : null;
  return cred || req.socket.remoteAddress || 'unknown';
}

function allow(key) {
  const now = Date.now();
  const b = buckets.get(key);
  if (!b || now - b.start > RATE_WINDOW_MS) {
    buckets.set(key, { start: now, count: 1 });
    return { ok: true, remaining: RATE_LIMIT - 1 };
  }
  b.count += 1;
  if (b.count > RATE_LIMIT) {
    return { ok: false, retryAfter: Math.ceil((b.start + RATE_WINDOW_MS - now) / 1000) };
  }
  return { ok: true, remaining: RATE_LIMIT - b.count };
}

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of buckets) if (now - v.start > RATE_WINDOW_MS * 2) buckets.delete(k);
}, RATE_WINDOW_MS).unref();

/* ----------------------------------------------------------------- routing */

function parseUrl(req) {
  const u = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const query = Object.fromEntries(u.searchParams.entries());
  return { pathname: u.pathname.replace(/\/+$/, '') || '/', query };
}

/** Trailing path segment, e.g. /segments/1001-0.ts -> "1001-0.ts" */
function lastSegment(pathname) {
  const parts = pathname.split('/').filter(Boolean);
  return parts[parts.length - 1] || '';
}

function sendError(res, code, message) {
  const body = JSON.stringify({ error: code, message }, null, 2);
  res.writeHead(code === 429 ? 429 : code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function sendText(res, code, text) {
  res.writeHead(code, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
  });
  res.end(text);
}

function route(req, res) {
  const { pathname, query } = parseUrl(req);

  // CORS preflight + permissive CORS: this is a local development reference
  // server. The real one sets `access-control-allow-origin: *` too.
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Server', 'dramalive-reference-backend');
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return sendError(res, 405, `method ${req.method} not allowed (this API is read-only)`);
  }

  const rl = allow(rateKey(req, query));
  if (!rl.ok) {
    res.setHeader('Retry-After', String(rl.retryAfter));
    return sendError(res, 429, `rate limited: ${RATE_LIMIT} req/min exceeded`);
  }
  res.setHeader('X-RateLimit-Remaining', String(rl.remaining == null ? 0 : rl.remaining));

  try {
    /* --- Xtream contract ------------------------------------------------ */
    if (pathname === '/player_api.php' || pathname === '/api/player_api.php') {
      return playerApi.handle(req, res, query);
    }

    /* --- discovery / config -------------------------------------------- */
    if (pathname === '/health') return discovery.health(req, res);
    if (pathname === '/config/remote') return discovery.remoteConfig(req, res);
    if (pathname === '/catalog/featured') return discovery.featured(req, res);
    if (pathname === '/catalog/search') return discovery.search(req, res, query);
    if (pathname === '/sources') return discovery.sources(req, res);

    /* --- playback ------------------------------------------------------ */
    if (/^\/(live|movie|series)\//.test(pathname)) {
      const seg = lastSegment(pathname);
      const id = seg.split('.')[0];
      return hlsRoutes.stream(req, res, { id });
    }
    if (/^\/hls\/[^/]+\/index\.m3u8$/.test(pathname)) {
      const id = pathname.split('/')[2];
      return hlsRoutes.media(req, res, { id });
    }
    if (pathname.startsWith('/segments/')) {
      return hlsRoutes.segment(req, res, { name: lastSegment(pathname) });
    }

    /* --- index --------------------------------------------------------- */
    if (pathname === '/' || pathname === '/index.html') {
      return sendText(res, 200, INDEX_TEXT);
    }

    return sendError(res, 404, `no route for ${pathname}`);
  } catch (err) {
    console.error('[error]', err && err.stack ? err.stack : err);
    return sendError(res, 500, err && err.message ? err.message : 'internal error');
  }
}

const INDEX_TEXT = `dramalive-analysis — reference backend

Xtream Codes contract (credentials: demo / demo)
  GET /player_api.php?username=demo&password=demo
  GET /player_api.php?username=demo&password=demo&action=get_live_categories
  GET /player_api.php?username=demo&password=demo&action=get_live_streams
  GET /player_api.php?username=demo&password=demo&action=get_vod_streams
  GET /player_api.php?username=demo&password=demo&action=get_series
  GET /player_api.php?username=demo&password=demo&action=get_series_info&series_id=3001
  GET /player_api.php?username=demo&password=demo&action=get_short_epg&stream_id=1001
  GET /player_api.php?username=demo&password=demo&action=get_simple_data_table&stream_id=1001&date=2026-10-20

Playback (synthetic HLS, generated in memory)
  GET /live/1001.m3u8
  GET /hls/1001/index.m3u8
  GET /segments/1001-0.ts

Discovery
  GET /config/remote        same shape as the app's embedded remote config
  GET /catalog/featured
  GET /catalog/search?q=bunny
  GET /sources
  GET /health

This server never dials a third party. PASSTHROUGH=1 enables proxying of the
'source' URLs declared in backend/src/data/catalog.json (openly licensed test
streams). See docs/05-API.md and docs/00-LEGAL-Y-ALCANCE.md.
`;

/* ------------------------------------------------------------------ server */

function main() {
  const server = http.createServer(route);
  server.headersTimeout = 35_000;
  server.requestTimeout = 40_000;
  server.listen(PORT, HOST, () => {
    console.log(`[backend] listening on http://${HOST}:${PORT}`);
    console.log(`[backend] passthrough=${hlsRoutes.PASSTHROUGH} rateLimit=${RATE_LIMIT}/min`);
    console.log(`[backend] try: curl -s 'http://localhost:${PORT}/health'`);
  });

  const shutdown = (signal) => {
    console.log(`\n[backend] ${signal} — closing`);
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  };
  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
}

if (require.main === module) main();

module.exports = { route, INDEX_TEXT };
