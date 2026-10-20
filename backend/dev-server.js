#!/usr/bin/env node
'use strict';
/**
 * Servidor de desarrollo: sirve el cliente web estático y proxifica /backend
 * hacia la API de referencia.
 *
 *   node backend/dev-server.js
 *   WEB_PORT=5173 API_PORT=8080 node backend/dev-server.js
 *
 * Por qué existe: la vista previa del entorno se sirve bajo un host proxificado
 * (https://<puerto>-<sandbox>.e2b.app), así que el navegador NO puede llamar a
 * localhost:8080 directamente. Este servidor expone ambos bajo el mismo origen:
 *
 *   /client/web/…   → el cliente
 *   /backend/…      → proxy a la API (mismo origen, sin problemas de CORS ni de host)
 *
 * Arranca la API en el mismo proceso, en 127.0.0.1:API_PORT.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WEB_PORT = Number(process.env.WEB_PORT || 5173);
const API_PORT = Number(process.env.API_PORT || 8080);
const HOST = process.env.HOST || '0.0.0.0';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.md': 'text/markdown; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.m3u8': 'application/vnd.apple.mpegurl',
  '.ts': 'video/mp2t',
  '.dart': 'text/plain; charset=utf-8',
  '.yaml': 'text/plain; charset=utf-8',
  '.sh': 'text/plain; charset=utf-8',
};

/* ───────────────────────── arrancar la API en el mismo proceso ─────────── */

process.env.PORT = String(API_PORT);
process.env.HOST = '127.0.0.1';
const api = require('./src/index.js');

const apiServer = http.createServer(api.route);
apiServer.listen(API_PORT, '127.0.0.1', () => {
  console.log(`[dev] api    → http://127.0.0.1:${API_PORT}`);
});

/* ─────────────────────────────────── proxy ─────────────────────────────── */

function proxy(req, res, targetPath) {
  const opts = {
    host: '127.0.0.1',
    port: API_PORT,
    path: targetPath,
    method: req.method,
    headers: Object.assign({}, req.headers),
  };
  // Se conserva el Host ORIGINAL del navegador (no el del proxy) para que
  // cualquier URL absoluta que genere la API apunte al origen público correcto.
  // Aun así las playlists usan URIs relativas — ver src/services/hls.js.
  const originalHost = req.headers.host;
  opts.headers['x-forwarded-host'] = originalHost || '';
  opts.headers['x-forwarded-proto'] = (originalHost && !/^localhost|^127\./.test(originalHost)) ? 'https' : 'http';

  const up = http.request(opts, (r) => {
    res.writeHead(r.statusCode, r.headers);
    r.pipe(res);
  });
  up.on('error', (e) => {
    res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end(`backend caído: ${e.message}\n`);
  });
  up.setTimeout(30000, () => {
    up.destroy();
    res.writeHead(504, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('backend: tiempo de espera agotado\n');
  });
  req.pipe(up);
}

/* ────────────────────────────────── estáticos ──────────────────────────── */

function serveStatic(req, res, pathname) {
  let rel = decodeURIComponent(pathname);
  if (rel === '/' || rel === '') rel = '/client/web/index.html';
  if (rel.endsWith('/')) rel += 'index.html';

  const file = path.join(ROOT, rel);
  // Nunca servir nada fuera del repo.
  if (!file.startsWith(ROOT)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    return res.end('403 fuera del repo\n');
  }
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    return res.end(`404 ${rel}\n`);
  }
  res.writeHead(200, {
    'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    'Cache-Control': 'no-store',
  });
  fs.createReadStream(file).pipe(res);
}

const INDEX_REDIRECT = `<!doctype html><meta charset=utf-8>
<title>dramalive-analysis</title>
<meta http-equiv=refresh content="0;url=/client/web/">
<p>Redirigiendo a <a href="/client/web/">/client/web/</a>…</p>`;

const devServer = http.createServer((req, res) => {
  const u = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const p = u.pathname;

  if (p === '/backend' || p.startsWith('/backend/')) {
    const target = p.replace(/^\/backend/, '') || '/';
    return proxy(req, res, target + (u.search || ''));
  }
  if (p === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(INDEX_REDIRECT);
  }
  return serveStatic(req, res, p);
});

devServer.listen(WEB_PORT, HOST, () => {
  console.log(`[dev] web    → http://${HOST}:${WEB_PORT}/client/web/`);
  console.log(`[dev] proxy  → /backend/*  ⇒  127.0.0.1:${API_PORT}`);
  console.log(`[dev] preview: usa la URL del puerto ${WEB_PORT} y entra en /client/web/`);
});

const shutdown = (sig) => {
  console.log(`\n[dev] ${sig} — cerrando`);
  devServer.close(() => apiServer.close(() => process.exit(0)));
  setTimeout(() => process.exit(0), 3000).unref();
};
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
