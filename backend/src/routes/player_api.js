'use strict';
/**
 * Xtream Codes `player_api.php` — reference implementation.
 *
 * Contract documented in docs/05-API.md. Quirks of the real protocol are
 * reproduced on purpose (category_id as string, stream_id as number, auth as
 * int, exp_date as string, EPG fields base64-encoded) so a client written
 * against this backend also works against a real panel.
 */

const catalog = require('../services/catalog');

function json(res, code, body) {
  const payload = JSON.stringify(body);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(payload),
    'Cache-Control': 'no-store',
  });
  res.end(payload);
}

/**
 * Credentials come from the query string because that is what the Xtream
 * protocol does. `Authorization: Basic` is also accepted, because putting
 * passwords in a URL is a bad habit even in a local reference server.
 */
function credentials(query, req) {
  if (query.username && query.password) {
    return { username: String(query.username), password: String(query.password) };
  }
  const h = req.headers['authorization'];
  if (h && /^Basic /i.test(h)) {
    try {
      const decoded = Buffer.from(h.slice(6).trim(), 'base64').toString('utf8');
      const i = decoded.indexOf(':');
      if (i > 0) return { username: decoded.slice(0, i), password: decoded.slice(i + 1) };
    } catch (_) {
      /* fall through */
    }
  }
  return null;
}

function handle(req, res, query) {
  const creds = credentials(query, req);
  if (!creds) {
    return json(res, 401, { error: 'auth_failed', message: 'username and password are required' });
  }
  const acc = catalog.verify(creds.username, creds.password);
  if (!acc) {
    return json(res, 401, { error: 'auth_failed', message: 'invalid credentials' });
  }

  const action = query.action ? String(query.action) : null;
  const catId = query.category_id != null ? String(query.category_id) : null;

  switch (action) {
    case null:
      return json(res, 200, {
        user_info: {
          username: acc.username,
          password: acc.password,
          auth: 1,
          status: acc.status || 'Active',
          exp_date: String(acc.exp_date || ''),
          is_trial: String(acc.is_trial || '0'),
          active_cons: '1',
          max_connections: String(acc.max_connections || '1'),
          allowed_output_formats: acc.allowed_output_formats || ['m3u8', 'ts'],
          created_at: '1704067200',
        },
        server_info: {
          url: req.headers.host ? req.headers.host.split(':')[0] : 'localhost',
          port: Number((req.headers.host || '').split(':')[1] || 80),
          https_port: 443,
          server_protocol: 'http',
          rtmp_port: 8001,
          timezone: process.env.TZ || 'UTC',
          timestamp_now: String(Math.floor(Date.now() / 1000)),
        },
      });

    case 'get_live_categories':
      return json(res, 200, catalog.categories('live'));
    case 'get_vod_categories':
      return json(res, 200, catalog.categories('vod'));
    case 'get_series_categories':
      return json(res, 200, catalog.categories('series'));

    case 'get_live_streams':
      return json(res, 200, catalog.live(catId));
    case 'get_vod_streams':
      return json(res, 200, catalog.vod(catId));
    case 'get_series':
      return json(res, 200, catalog.series(catId));

    case 'get_series_info': {
      if (!query.series_id) {
        return json(res, 400, { error: 'bad_request', message: 'series_id is required' });
      }
      const info = catalog.seriesInfo(query.series_id);
      if (!info) return json(res, 404, { error: 'not_found', message: 'unknown series_id' });
      return json(res, 200, info);
    }

    case 'get_short_epg': {
      if (!query.stream_id) {
        return json(res, 400, { error: 'bad_request', message: 'stream_id is required' });
      }
      if (!catalog.knownStreamId(query.stream_id)) {
        return json(res, 404, { error: 'not_found', message: 'unknown stream_id' });
      }
      const limit = Number(query.limit || 4);
      return json(res, 200, { epg_listings: catalog.epgFor(query.stream_id, { limit }) });
    }

    case 'get_simple_data_table': {
      if (!query.stream_id) {
        return json(res, 400, { error: 'bad_request', message: 'stream_id is required' });
      }
      if (!catalog.knownStreamId(query.stream_id)) {
        return json(res, 404, { error: 'not_found', message: 'unknown stream_id' });
      }
      const date = query.date ? String(query.date) : null;
      if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        return json(res, 400, { error: 'bad_request', message: 'date must be YYYY-MM-DD' });
      }
      return json(res, 200, {
        epg_listings: catalog.epgFor(query.stream_id, { limit: 12, date }),
      });
    }

    default:
      return json(res, 400, { error: 'bad_request', message: `unsupported action: ${action}` });
  }
}

module.exports = { handle };
