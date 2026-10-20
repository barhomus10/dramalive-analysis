'use strict';
/**
 * Catalog service — read-only access to data/catalog.json plus derived views.
 *
 * Deliberately tiny and dependency-free: the point of this backend is to be a
 * readable reference implementation of the Xtream Codes `player_api.php`
 * contract, not a production service.
 */

const fs = require('fs');
const path = require('path');

const CATALOG_PATH = path.join(__dirname, '..', 'data', 'catalog.json');

let cache = null;
let cacheMtime = 0;

function load() {
  try {
    const st = fs.statSync(CATALOG_PATH);
    if (!cache || st.mtimeMs !== cacheMtime) {
      cache = JSON.parse(fs.readFileSync(CATALOG_PATH, 'utf8'));
      cacheMtime = st.mtimeMs;
    }
  } catch (err) {
    throw new Error(`cannot read catalog at ${CATALOG_PATH}: ${err.message}`);
  }
  return cache;
}

/* ---------------------------------------------------------------- accounts */

function account(username) {
  const c = load();
  const acc = (c.accounts || {})[username];
  if (!acc) return null;
  return Object.assign({ username }, acc);
}

function verify(username, password) {
  const acc = account(username);
  if (!acc) return null;
  if (String(acc.password) !== String(password)) return null;
  return acc;
}

/* -------------------------------------------------------------- categories */

function categories(kind) {
  const c = load();
  return (c.categories || {})[kind] || [];
}

/* ----------------------------------------------------------------- streams */

function live(categoryId) {
  const c = load();
  const all = c.live || [];
  return categoryId == null || categoryId === ''
    ? all
    : all.filter((s) => String(s.category_id) === String(categoryId));
}

function vod(categoryId) {
  const c = load();
  const all = c.vod || [];
  return categoryId == null || categoryId === ''
    ? all
    : all.filter((s) => String(s.category_id) === String(categoryId));
}

function series(categoryId) {
  const c = load();
  const all = c.series || [];
  return categoryId == null || categoryId === ''
    ? all
    : all.filter((s) => String(s.category_id) === String(categoryId));
}

function seriesInfo(seriesId) {
  const c = load();
  const s = (c.series || []).find((x) => String(x.series_id) === String(seriesId));
  if (!s) return null;
  const episodes = (c.series_episodes || {})[String(seriesId)] || {};
  return {
    seasons: s.seasons || [],
    episodes,
    info: {
      name: s.name,
      plot: s.plot || '',
      genre: s.genre || '',
      rating: s.rating || '',
      releaseDate: s.releaseDate || '',
      cover: s.cover || '',
      category_id: String(s.category_id),
    },
  };
}

/** Every stream id known to the catalog, across live/vod/series-episodes. */
function knownStreamId(id) {
  const c = load();
  const n = Number(id);
  if (!Number.isFinite(n)) return false;
  if ((c.live || []).some((s) => s.stream_id === n)) return true;
  if ((c.vod || []).some((s) => s.stream_id === n)) return true;
  for (const eps of Object.values(c.series_episodes || {})) {
    for (const season of Object.values(eps)) {
      if (season.some((e) => e.stream_id === n)) return true;
    }
  }
  return false;
}

function findStream(id) {
  const c = load();
  const n = Number(id);
  return (
    (c.live || []).find((s) => s.stream_id === n) ||
    (c.vod || []).find((s) => s.stream_id === n) ||
    null
  );
}

/* --------------------------------------------------------------------- EPG */

const SLOT_SECONDS = 2 * 60 * 60; // 2h slots, like a real grid

function b64(s) {
  return Buffer.from(String(s == null ? '' : s), 'utf8').toString('base64');
}

/**
 * EPG entries for a channel. Titles/descriptions are base64 — that is what the
 * real Xtream protocol does, so the replica keeps it (clients expect it).
 */
function epgFor(streamId, { limit = 4, date = null } = {}) {
  const c = load();
  const programs = (c.epg || {})[String(streamId)] || [];
  if (!programs.length) return [];

  const dayStart = date ? Date.parse(`${date}T00:00:00Z`) : Date.now();
  const anchor = Number.isFinite(dayStart) ? dayStart : Date.now();
  const firstSlot = Math.floor(anchor / 1000 / SLOT_SECONDS) * SLOT_SECONDS;

  const out = [];
  for (let i = 0; i < Math.max(1, Math.min(limit, 24)); i++) {
    const p = programs[i % programs.length];
    const start = firstSlot + i * SLOT_SECONDS;
    const stop = start + SLOT_SECONDS;
    out.push({
      id: String(9000 + Number(streamId) * 10 + i),
      epg_id: 1,
      title: b64(p.title),
      description: b64(p.description || ''),
      channel_id: String(streamId),
      start_timestamp: String(start),
      stop_timestamp: String(stop),
      start: fmt(start),
      stop: fmt(stop),
    });
  }
  return out;
}

function fmt(epochSeconds) {
  const d = new Date(epochSeconds * 1000);
  const p = (n) => String(n).padStart(2, '0');
  return (
    `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ` +
    `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`
  );
}

/* --------------------------------------------------------------- discovery */

function featured() {
  return (load().featured || []).map((block) => {
    if (block.type !== 'row') return block;
    const pool = { live: live(), vod: vod(), series: series() }[block.kind] || [];
    const key = block.kind === 'series' ? 'series_id' : 'stream_id';
    return Object.assign({}, block, {
      items: (block.items || [])
        .map((id) => pool.find((x) => x[key] === id))
        .filter(Boolean),
    });
  });
}

function search(q) {
  const needle = String(q || '').trim().toLowerCase();
  if (!needle) return { live: [], vod: [], series: [] };
  const has = (s) => JSON.stringify(s).toLowerCase().includes(needle);
  return {
    live: live().filter(has),
    vod: vod().filter(has),
    series: series().filter(has),
  };
}

/**
 * Same *shape* as the remote config embedded in the real app's classes.dex, so
 * a client can parse either. Everything points at localhost and every third
 * party integration is empty — see docs/05-API.md §4.
 */
function remoteConfig(publicBase) {
  return {
    appVersionModel: {
      app_version: '1.0.0',
      androidAppVersion: '1.0.0',
      iosAppVersion: '1.0.0',
      forceUpdate: false,
      update_url: '',
      update_url_direct: '',
      update_message: '',
    },
    serverSettingsModel: {
      server_url: `${publicBase}/api/`,
      sport_server_url: '',
      file_server_url: `${publicBase}/`,
      xmpp_ip: '',
      tutorial_video: '',
      fgcode_url: '',
      admin_email: '',
      admin_email_paid: '',
      smart_search_url: `${publicBase}/catalog/search`,
      redirect_url: '',
      live_url: `${publicBase}/api/`,
      log_url: '',
      banned_apps: [],
      chat_http_url: '',
      crash_reporting_url: '',
      crash_reporting_login: '',
      crash_reporting_password: '',
      privacy_policy_url: '',
      legal_url: '',
      faqs_url: '',
      business_url: '',
      support_email: '',
    },
    mainServerModelArraylist: [{ url: `${publicBase}/api/`, checked: true }],
    socialModelArraylist: [],
    adsModel: {
      home_ban: 'nactive',
      live_ban: 'nactive',
      all_int: 'nactive',
      time_int: '0',
      home_nat: 'nactive',
      live_nat: 'nactive',
      sport_nat: 'nactive',
      billing_available: false,
      coupon_available: false,
      coupon_active: false,
      coupon_end_date: '',
    },
    modModel: { mod_ar: '', mod_en: '', mod_url: null },
    fg_active: false,
  };
}

function stats() {
  const c = load();
  return {
    live: (c.live || []).length,
    vod: (c.vod || []).length,
    series: (c.series || []).length,
    categories: Object.values(c.categories || {}).reduce((a, b) => a + b.length, 0),
    epg_channels: Object.keys(c.epg || {}).length,
  };
}

module.exports = {
  load,
  account,
  verify,
  categories,
  live,
  vod,
  series,
  seriesInfo,
  knownStreamId,
  findStream,
  epgFor,
  featured,
  search,
  remoteConfig,
  stats,
  SLOT_SECONDS,
};
