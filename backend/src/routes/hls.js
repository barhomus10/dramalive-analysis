'use strict';
/**
 * HLS routes.
 *
 * Two modes:
 *
 *  1. SYNTHETIC (default) — the backend generates the playlist and the .ts
 *     segments itself. Nothing is fetched from anywhere. Use this to exercise
 *     the client's HLS pipeline.
 *
 *  2. PASSTHROUGH (opt-in, `PASSTHROUGH=1`) — the backend proxies the `source`
 *     URL that is *declared in this repo's own catalog file*
 *     (backend/src/data/catalog.json). Useful when you want real picture from a
 *     stream you are entitled to use.
 *
 *     PASSTHROUGH is off by default and is deliberately constrained:
 *       - the target is never taken from the request; it is read from the local
 *         catalog file, so this cannot be used as an open proxy / SSRF gadget;
 *       - each fetch is logged;
 *       - only http/https are allowed.
 *     Point it at content you own or that is openly licensed.
 */

const https = require('https');
const http = require('http');
const catalog = require('../services/catalog');
const hls = require('../services/hls');

const PASSTHROUGH = process.env.PASSTHROUGH === '1' || process.env.PASSTHROUGH === 'true';

function baseUrl(req) {
  const host = req.headers.host || `localhost:${process.env.PORT || 8080}`;
  return `http://${host}`;
}

function text(res, code, body, contentType, cache) {
  res.writeHead(code, {
    'Content-Type': contentType,
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': cache,
  });
  res.end(body);
}

/* ----------------------------------------------------------- passthrough */

function passthroughTarget(streamId) {
  const c = catalog.load();
  const n = Number(streamId);
  const hit = [...(c.live || []), ...(c.vod || [])].find((s) => s.stream_id === n);
  if (!hit || !hit.source) return null;
  if (!/^https?:\/\//i.test(hit.source)) return null;
  return hit.source;
}

function proxy(req, res, target) {
  const lib = target.startsWith('https') ? https : http;
  console.log(`[passthrough] ${req.method} ${target}`);
  const upstream = lib.get(target, { timeout: 15000 }, (up) => {
    res.writeHead(up.statusCode || 502, {
      'Content-Type': up.headers['content-type'] || 'application/octet-stream',
      'Cache-Control': 'public, max-age=30',
    });
    up.pipe(res);
  });
  upstream.on('timeout', () => {
    upstream.destroy();
    text(res, 504, 'upstream timeout\n', 'text/plain; charset=utf-8', 'no-store');
  });
  upstream.on('error', (err) => {
    console.error('[passthrough] error:', err.message);
    text(res, 502, `upstream error: ${err.message}\n`, 'text/plain; charset=utf-8', 'no-store');
  });
}

/* ------------------------------------------------------------------ routes */

/** GET /live/:id.m3u8   (also /movie/:id.<ext>, /series/:id.<ext>) */
function stream(req, res, params) {
  const id = params.id;
  if (!id) return text(res, 400, 'missing stream id\n', 'text/plain', 'no-store');

  if (PASSTHROUGH) {
    const target = passthroughTarget(id);
    if (target) return proxy(req, res, target);
  }

  if (!catalog.knownStreamId(id)) {
    return text(res, 404, 'unknown stream id\n', 'text/plain; charset=utf-8', 'no-store');
  }
  const isVod = req.url.startsWith('/movie/') || req.url.startsWith('/series/');
  const body = hls.masterPlaylist(id, { baseUrl: baseUrl(req) });
  void isVod; // master playlist is identical for both in this reference impl
  return text(res, 200, body, 'application/vnd.apple.mpegurl; charset=utf-8', 'no-store');
}

/** GET /hls/:id/index.m3u8 — media playlist */
function media(req, res, params) {
  const id = params.id;
  if (!catalog.knownStreamId(id)) {
    return text(res, 404, 'unknown stream id\n', 'text/plain; charset=utf-8', 'no-store');
  }
  const body = hls.mediaPlaylist(id, { baseUrl: baseUrl(req) });
  return text(res, 200, body, 'application/vnd.apple.mpegurl; charset=utf-8', 'no-store');
}

/** GET /segments/:name.ts — synthetic segment */
function segment(req, res, params) {
  const m = /^(\d+)-(\d+)\.ts$/.exec(params.name || '');
  if (!m) return text(res, 400, 'bad segment name\n', 'text/plain', 'no-store');
  const [, id, idx] = m;
  if (!catalog.knownStreamId(id)) {
    return text(res, 404, 'unknown stream id\n', 'text/plain', 'no-store');
  }
  const buf = hls.segment(id, Number(idx));
  res.writeHead(200, {
    'Content-Type': 'video/mp2t',
    'Content-Length': buf.length,
    'Cache-Control': 'public, max-age=3600',
  });
  res.end(buf);
}

module.exports = { stream, media, segment, PASSTHROUGH };
