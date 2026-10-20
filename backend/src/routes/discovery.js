'use strict';
/**
 * Non-Xtream endpoints: remote config, catalog discovery, search, health.
 * These stand in for what the real app gets from its own backend
 * (`*.eastgoessouth.online` / `main.fastconnections.online`) — reimplemented
 * here against local, licensed-free data instead of pointed at theirs.
 * See docs/05-API.md §4.
 */

const catalog = require('../services/catalog');

const STARTED = Date.now();
const VERSION = process.env.npm_package_version || '1.0.0';

function json(res, code, body, cache = 'no-store') {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': cache,
  });
  res.end(payload);
}

function publicBase(req) {
  return `http://${req.headers.host || `localhost:${process.env.PORT || 8080}`}`;
}

/**
 * Same JSON shape as the config embedded in the real app's classes.dex, with
 * every third-party integration emptied out. A client that parses one parses
 * the other. See docs/07-HALLAZGOS-SEGURIDAD.md for why the real one is a
 * problem (F-01: credentials shipped in the binary).
 */
function remoteConfig(req, res) {
  json(res, 200, catalog.remoteConfig(publicBase(req)), 'public, max-age=60');
}

function featured(req, res) {
  json(res, 200, { blocks: catalog.featured() }, 'public, max-age=60');
}

function search(req, res, query) {
  const q = query.q ? String(query.q) : '';
  if (!q.trim()) {
    return json(res, 400, { error: 'bad_request', message: 'q is required' });
  }
  const r = catalog.search(q);
  json(res, 200, {
    query: q,
    counts: { live: r.live.length, vod: r.vod.length, series: r.series.length },
    results: r,
  });
}

/**
 * The source registry. Only `mock` is enabled: this reference backend never
 * dials a third party on the client's behalf. Xtream/M3U/FG sources are
 * configured *client-side*, against panels the user owns.
 */
function sources(req, res) {
  json(res, 200, {
    sources: [
      {
        id: 'mock',
        kind: 'xtream',
        label: 'Backend de referencia (local)',
        enabled: true,
        base_url: `${publicBase(req)}/player_api.php`,
        credentials: { username: 'demo', password: 'demo' },
        note: 'Cuenta de demostración. Catálogo con contenido libre.',
      },
      {
        id: 'xtream-user',
        kind: 'xtream',
        label: 'Tu panel Xtream Codes',
        enabled: false,
        base_url: null,
        credentials: null,
        note: 'Se configura desde la app. Solo paneles de los que tengas credenciales legítimas.',
      },
      {
        id: 'm3u-user',
        kind: 'm3u',
        label: 'Tu URL M3U/M3U8',
        enabled: false,
        base_url: null,
        note: 'Se configura desde la app.',
      },
      {
        id: 'fg',
        kind: 'fg',
        label: 'FG Code (fgcode.store)',
        enabled: false,
        base_url: null,
        note: 'Deshabilitado por defecto: depende de un tercero sin contrato publicado. Ver docs/04.',
      },
      {
        id: 'github',
        kind: 'm3u',
        label: 'Playlist en un repo público de GitHub',
        enabled: false,
        base_url: null,
        note: 'github.com/<o>/<r>/blob/<path> → raw.githubusercontent.com/<o>/<r>/<path>',
      },
    ],
  });
}

function health(req, res) {
  json(res, 200, {
    ok: true,
    service: 'dramalive-analysis reference backend',
    version: VERSION,
    uptime_seconds: Math.round((Date.now() - STARTED) / 1000),
    catalog: catalog.stats(),
    passthrough: require('./hls').PASSTHROUGH,
    node: process.version,
  });
}

module.exports = { remoteConfig, featured, search, sources, health };
