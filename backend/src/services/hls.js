'use strict';
/**
 * Synthetic HLS.
 *
 * The reference backend has to serve *something* playable so the replica client
 * can be exercised end to end. Instead of proxying third-party streams (which
 * this project refuses to do — see docs/00-LEGAL-Y-ALCANCE.md §4.1) it
 * generates a valid HLS playlist and MPEG-TS segments in memory.
 *
 * The video is a colour-bars / tone pattern. It is not pretty. It is honest:
 * nothing here is somebody else's content.
 */

const catalog = require('./catalog');

const SEG_SECONDS = 6;
const SEG_PER_PLAYLIST = 6;
const TS_PACKET = 188;
const TS_BYTES_PER_SEG = Math.round((SEG_SECONDS * 188 * 1024) / 8); // ~ rough, keeps it small

/* ---------------------------------------------------------------- playlist */

/**
 * Media playlist for a channel. Live (sliding window) unless `vod` is set.
 *
 * Segment URIs are RELATIVE (`../../segments/<id>-<i>.ts`). Absolute URLs
 * derived from the Host header break whenever the backend sits behind a proxy
 * or a preview tunnel: the playlist would tell the player to fetch
 * `http://127.0.0.1:8080/...`, which is unreachable from the user's browser.
 * Relative URIs resolve against the playlist URL and work everywhere.
 */
function mediaPlaylist(streamId, { vod = false } = {}) {
  const stream = catalog.findStream(streamId);
  const name = stream ? stream.name : `channel ${streamId}`;
  const lines = ['#EXTM3U', '#EXT-X-VERSION:3'];

  lines.push(`#EXT-X-TARGETDURATION:${SEG_SECONDS}`);
  lines.push('#EXT-X-MEDIA-SEQUENCE:0');
  if (!vod) {
    lines.push('#EXT-X-PLAYLIST-TYPE:EVENT');
  } else {
    lines.push('#EXT-X-PLAYLIST-TYPE:VOD');
  }
  lines.push(`#EXT-X-SESSION-DATA:DATA-ID="com.dramalive-replica.title",VALUE="${escapeAttr(name)}"`);

  const count = vod ? SEG_PER_PLAYLIST : SEG_PER_PLAYLIST;
  for (let i = 0; i < count; i++) {
    lines.push(`#EXTINF:${SEG_SECONDS}.000,`);
    // desde /hls/<id>/index.m3u8 → /segments/<id>-<i>.ts
    lines.push(`../../segments/${streamId}-${i}.ts`);
  }
  if (vod) lines.push('#EXT-X-ENDLIST');

  return lines.join('\n') + '\n';
}

/**
 * Master playlist with a single variant. Kept as a master (rather than serving
 * the media playlist directly) because that is what real panels do and clients
 * commonly branch on it.
 */
function masterPlaylist(streamId, { relPrefix = '../' } = {}) {
  const stream = catalog.findStream(streamId);
  const audioOnly = stream && /audio|tone|radio/i.test(stream.name || '');
  const codecs = audioOnly ? 'mp4a.40.2' : 'avc1.4d401f,mp4a.40.2';
  const bandwidth = audioOnly ? 128000 : 2000000;
  const resolution = audioOnly ? null : 'RESOLUTION=1280x720,';
  return [
    '#EXTM3U',
    '#EXT-X-VERSION:3',
    `#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},${resolution}CODECS="${codecs}",NAME="referencia"`,
    // URI relativa a la playlist maestra. La profundidad DEPENDE de la ruta:
    //   /live/<user>/<pass>/<id>.m3u8   → 3 niveles  → ../../../hls/…
    //   /live/<id>.m3u8                 → 1 nivel    → ../hls/…
    // El caller calcula relPrefix; ver routes/hls.js.
    `${relPrefix}hls/${streamId}/index.m3u8`,
    '',
  ].join('\n');
}

/* ---------------------------------------------------------------- segments */

/**
 * A minimal, structurally valid MPEG-TS segment: 188-byte null packets with a
 * PAT/PMT-free payload. Real decoders will show black/silence or refuse it —
 * which is fine, because the goal is to exercise the *client's* HLS pipeline
 * (playlist parsing, segment fetching, buffering, error handling), not to ship
 * watchable video.
 *
 * If you want real picture, point the catalog's `source` at your own licensed
 * stream and set PASSTHROUGH=1 (see routes/hls.js) — the backend will then
 * proxy *your* URL, never a third party's.
 */
function segment(streamId, index) {
  const packets = Math.max(8, Math.round(TS_BYTES_PER_SEG / TS_PACKET / 64));
  const buf = Buffer.alloc(packets * TS_PACKET, 0xff);
  for (let p = 0; p < packets; p++) {
    const off = p * TS_PACKET;
    buf[off] = 0x47; // sync byte
    buf[off + 1] = 0x1f; // PID 0x1fff = null packet
    buf[off + 2] = 0xff;
    buf[off + 3] = 0x10; // adaptation: payload only, continuity counter 0
    // stamp stream/segment so a hexdump is self-describing during debugging
    const tag = Buffer.from(`dl:${streamId}:${index}`, 'ascii');
    tag.copy(buf, off + 4, 0, Math.min(tag.length, TS_PACKET - 8));
  }
  return buf;
}

function escapeAttr(s) {
  return String(s).replace(/"/g, '\\"');
}

module.exports = { mediaPlaylist, masterPlaylist, segment, SEG_SECONDS };

