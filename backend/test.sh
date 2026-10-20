#!/usr/bin/env bash
# Contract test suite for the reference backend.
#
#   bash backend/test.sh                      # against localhost:8080
#   BASE=http://localhost:9000 bash backend/test.sh
#
# Starts the server itself if nothing is listening. Exits non-zero on the first
# failure and prints a summary.

set -uo pipefail

BASE="${BASE:-http://localhost:8080}"
PORT="${PORT:-8080}"
AUTH="username=demo&password=demo"
API="$BASE/player_api.php?$AUTH"

pass=0; fail=0; started=""
FAILED_NAMES=()

cleanup() {
  if [ -n "$started" ]; then
    kill "$started" 2>/dev/null || true
    wait "$started" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- bootstrap
if ! curl -sS -m 2 -o /dev/null "$BASE/health" 2>/dev/null; then
  echo "[test] nothing on $BASE — starting the backend"
  ( cd "$(dirname "$0")" && PORT="$PORT" node src/index.js >/tmp/dla-backend-test.log 2>&1 ) &
  started=$!
  for _ in $(seq 1 40); do
    curl -sS -m 1 -o /dev/null "$BASE/health" 2>/dev/null && break
    sleep 0.25
  done
  if ! curl -sS -m 2 -o /dev/null "$BASE/health" 2>/dev/null; then
    echo "[test] FATAL: backend did not come up. Log:"; cat /tmp/dla-backend-test.log; exit 1
  fi
fi

# ------------------------------------------------------------------ helpers
check() { # name  expected  actual
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    pass=$((pass+1)); printf '  \033[32mok\033[0m   %-56s %s\n' "$name" "$got"
  else
    fail=$((fail+1)); FAILED_NAMES+=("$name")
    printf '  \033[31mFAIL\033[0m %-56s want=%s got=%s\n' "$name" "$want" "$got"
  fi
}

status() { curl -sS -m 10 -o /dev/null -w '%{http_code}' "$1"; }

jqpy() { # <python-expr on d>
  python3 -c "
import sys,json
d=json.load(sys.stdin)
print($1)
" 2>/dev/null || echo "PARSE_ERROR"
}

echo
echo "dramalive-analysis · contract tests"
echo "BASE=$BASE"
echo

# ------------------------------------------------------------------ health
check "GET /health -> 200"            "200"  "$(status "$BASE/health")"
check "health.ok is true"             "True" "$(curl -sS "$BASE/health" | jqpy "d['ok']")"
check "health reports passthrough"    "False" "$(curl -sS "$BASE/health" | jqpy "d['passthrough']")"
check "catalog has 5 live streams"    "5"    "$(curl -sS "$BASE/health" | jqpy "d['catalog']['live']")"

# ------------------------------------------------------------------- auth
check "no credentials -> 401"         "401"  "$(status "$BASE/player_api.php")"
check "wrong password -> 401"         "401"  "$(status "$BASE/player_api.php?username=demo&password=nope")"
check "unknown user -> 401"           "401"  "$(status "$BASE/player_api.php?username=nobody&password=x")"
check "Basic auth accepted -> 200"    "200"  "$(curl -sS -m 10 -o /dev/null -w '%{http_code}' -u demo:demo "$BASE/player_api.php")"

# --------------------------------------------------------------- handshake
check "handshake -> 200"              "200"  "$(status "$API")"
check "user_info.auth == 1 (int)"     "1"    "$(curl -sS "$API" | jqpy "d['user_info']['auth']")"
check "user_info.status Active"       "Active" "$(curl -sS "$API" | jqpy "d['user_info']['status']")"
check "exp_date is a string"          "str"  "$(curl -sS "$API" | jqpy "type(d['user_info']['exp_date']).__name__")"
check "server_info present"           "True" "$(curl -sS "$API" | jqpy "'server_info' in d")"
check "allowed_output_formats has m3u8" "True" "$(curl -sS "$API" | jqpy "'m3u8' in d['user_info']['allowed_output_formats']")"

# ------------------------------------------------------------- categories
check "live_categories -> 200"        "200"  "$(status "$API&action=get_live_categories")"
check "3 live categories"             "3"    "$(curl -sS "$API&action=get_live_categories" | jqpy "len(d)")"
check "category_id is a STRING"       "str"  "$(curl -sS "$API&action=get_live_categories" | jqpy "type(d[0]['category_id']).__name__")"
check "category has category_name"    "True" "$(curl -sS "$API&action=get_live_categories" | jqpy "'category_name' in d[0]")"
check "vod_categories -> 200"         "200"  "$(status "$API&action=get_vod_categories")"
check "series_categories -> 200"      "200"  "$(status "$API&action=get_series_categories")"

# ---------------------------------------------------------------- streams
check "live_streams -> 200"           "200"  "$(status "$API&action=get_live_streams")"
check "5 live streams"                "5"    "$(curl -sS "$API&action=get_live_streams" | jqpy "len(d)")"
check "stream_id is an INT"           "int"  "$(curl -sS "$API&action=get_live_streams" | jqpy "type(d[0]['stream_id']).__name__")"
check "filter by category_id=2 -> 2"  "2"    "$(curl -sS "$API&action=get_live_streams&category_id=2" | jqpy "len(d)")"
check "filter unknown cat -> 0"       "0"    "$(curl -sS "$API&action=get_live_streams&category_id=999" | jqpy "len(d)")"
check "vod_streams -> 4"              "4"    "$(curl -sS "$API&action=get_vod_streams" | jqpy "len(d)")"
check "vod has container_extension"   "mp4"  "$(curl -sS "$API&action=get_vod_streams" | jqpy "d[0]['container_extension']")"
check "get_series -> 1"               "1"    "$(curl -sS "$API&action=get_series" | jqpy "len(d)")"

# ------------------------------------------------------------------ series
check "series_info -> 200"            "200"  "$(status "$API&action=get_series_info&series_id=3001")"
check "series_info has 2 seasons"     "2"    "$(curl -sS "$API&action=get_series_info&series_id=3001" | jqpy "len(d['seasons'])")"
check "season 1 has 3 episodes"       "3"    "$(curl -sS "$API&action=get_series_info&series_id=3001" | jqpy "len(d['episodes']['1'])")"
check "series_info missing id -> 400" "400"  "$(status "$API&action=get_series_info")"
check "series_info unknown -> 404"    "404"  "$(status "$API&action=get_series_info&series_id=9999")"

# --------------------------------------------------------------------- EPG
check "short_epg -> 200"              "200"  "$(status "$API&action=get_short_epg&stream_id=1001")"
check "short_epg default limit 4"     "4"    "$(curl -sS "$API&action=get_short_epg&stream_id=1001" | jqpy "len(d['epg_listings'])")"
check "short_epg limit=2 honoured"    "2"    "$(curl -sS "$API&action=get_short_epg&stream_id=1001&limit=2" | jqpy "len(d['epg_listings'])")"
check "EPG title is base64"           "True" "$(curl -sS "$API&action=get_short_epg&stream_id=1001&limit=1" | jqpy "__import__('base64').b64decode(d['epg_listings'][0]['title']).decode() != ''")"
check "EPG start_timestamp is str"    "str"  "$(curl -sS "$API&action=get_short_epg&stream_id=1001&limit=1" | jqpy "type(d['epg_listings'][0]['start_timestamp']).__name__")"
check "EPG stop > start"              "True" "$(curl -sS "$API&action=get_short_epg&stream_id=1001&limit=1" | jqpy "int(d['epg_listings'][0]['stop_timestamp']) > int(d['epg_listings'][0]['start_timestamp'])")"
check "short_epg no stream_id -> 400" "400"  "$(status "$API&action=get_short_epg")"
check "short_epg unknown -> 404"      "404"  "$(status "$API&action=get_short_epg&stream_id=999999")"
check "simple_data_table -> 200"      "200"  "$(status "$API&action=get_simple_data_table&stream_id=1001")"
check "simple_data_table bad date -> 400" "400" "$(status "$API&action=get_simple_data_table&stream_id=1001&date=not-a-date")"

# ---------------------------------------------------------------- playback
check "/live/1001.m3u8 -> 200"        "200"  "$(status "$BASE/live/1001.m3u8")"
check "master playlist is #EXTM3U"    "#EXTM3U" "$(curl -sS "$BASE/live/1001.m3u8" | head -1)"
check "master has STREAM-INF"         "1"    "$(curl -sS "$BASE/live/1001.m3u8" | grep -c 'EXT-X-STREAM-INF')"
check "/hls/1001/index.m3u8 -> 200"   "200"  "$(status "$BASE/hls/1001/index.m3u8")"
check "media playlist has 6 segments" "6"    "$(curl -sS "$BASE/hls/1001/index.m3u8" | grep -c '\.ts$')"
check "TARGETDURATION present"        "1"    "$(curl -sS "$BASE/hls/1001/index.m3u8" | grep -c 'EXT-X-TARGETDURATION')"
check "playlist content-type"         "application/vnd.apple.mpegurl; charset=utf-8" "$(curl -sS -m 10 -o /dev/null -w '%{content_type}' "$BASE/hls/1001/index.m3u8")"
check "/segments/1001-0.ts -> 200"    "200"  "$(status "$BASE/segments/1001-0.ts")"
check "segment content-type mp2t"     "video/mp2t" "$(curl -sS -m 10 -o /dev/null -w '%{content_type}' "$BASE/segments/1001-0.ts")"
check "segment starts with TS sync 0x47" "71" "$(curl -sS "$BASE/segments/1001-0.ts" | head -c1 | python3 -c 'import sys;print(sys.stdin.buffer.read(1)[0])')"
check "segment size is N*188"         "0"    "$(curl -sS "$BASE/segments/1001-0.ts" | wc -c | python3 -c 'import sys;print(int(sys.stdin.read())%188)')"
check "/live/9999.m3u8 -> 404"        "404"  "$(status "$BASE/live/9999.m3u8")"
check "/segments/bogus.ts -> 400"     "400"  "$(status "$BASE/segments/bogus.ts")"
check "/movie/2001.mp4 -> 200"        "200"  "$(status "$BASE/movie/2001.mp4")"

# URIs relativas: si la API emite URLs absolutas derivadas del Host, el cliente
# falla detrás de cualquier proxy o túnel de preview (regresión real encontrada
# durante el desarrollo). Las playlists deben usar SOLO URIs relativas.
check "master: ninguna URI absoluta"  "0"    "$(curl -sS "$BASE/live/1001.m3u8" | grep -cE '^https?://')"
check "media: ninguna URI absoluta"   "0"    "$(curl -sS "$BASE/hls/1001/index.m3u8" | grep -cE '^https?://')"
check "master 1 nivel -> ../hls/"     "../hls/1001/index.m3u8" "$(curl -sS "$BASE/live/1001.m3u8" | grep -v '^#' | head -1)"
check "master 3 niveles (Xtream) -> ../../../hls/" "../../../hls/1001/index.m3u8" "$(curl -sS "$BASE/live/demo/demo/1001.m3u8" | grep -v '^#' | head -1)"
check "media segments -> ../../segments/" "../../segments/1001-0.ts" "$(curl -sS "$BASE/hls/1001/index.m3u8" | grep -v '^#' | head -1)"
check "ruta Xtream con user/pass -> 200" "200" "$(status "$BASE/live/demo/demo/1001.m3u8")"

# ------------------------------------------------------------- discovery
check "/config/remote -> 200"         "200"  "$(status "$BASE/config/remote")"
check "config has serverSettingsModel" "True" "$(curl -sS "$BASE/config/remote" | jqpy "'serverSettingsModel' in d")"
check "config has adsModel"           "True" "$(curl -sS "$BASE/config/remote" | jqpy "'adsModel' in d")"
check "config ships NO credentials"   "True" "$(curl -sS "$BASE/config/remote" | jqpy "d['serverSettingsModel']['crash_reporting_password'] == ''")"
check "config has empty banned_apps"  "0"    "$(curl -sS "$BASE/config/remote" | jqpy "len(d['serverSettingsModel']['banned_apps'])")"
check "config fg_active is false"     "False" "$(curl -sS "$BASE/config/remote" | jqpy "d['fg_active']")"
check "/catalog/featured -> 200"      "200"  "$(status "$BASE/catalog/featured")"
check "featured has 4 blocks"         "4"    "$(curl -sS "$BASE/catalog/featured" | jqpy "len(d['blocks'])")"
check "featured row resolved items"   "5"    "$(curl -sS "$BASE/catalog/featured" | jqpy "len([b for b in d['blocks'] if b['id']=='row-live'][0]['items'])")"
check "/catalog/search -> 200"        "200"  "$(status "$BASE/catalog/search?q=bunny")"
check "search finds bunny"            "1"    "$(curl -sS "$BASE/catalog/search?q=bunny" | jqpy "d['counts']['live']")"
check "search without q -> 400"       "400"  "$(status "$BASE/catalog/search")"
check "/sources -> 200"               "200"  "$(status "$BASE/sources")"
check "only mock source enabled"      "1"    "$(curl -sS "$BASE/sources" | jqpy "len([s for s in d['sources'] if s['enabled']])")"

# ------------------------------------------------------------- hardening
check "unknown action -> 400"         "400"  "$(status "$API&action=delete_everything")"
check "unknown route -> 404"          "404"  "$(status "$BASE/nope/nope")"
check "POST -> 405"                   "405"  "$(curl -sS -m 10 -X POST -o /dev/null -w '%{http_code}' "$BASE/health")"
check "CORS preflight -> 204"         "204"  "$(curl -sS -m 10 -X OPTIONS -o /dev/null -w '%{http_code}' "$BASE/health")"
check "ACAO header is *"              "*"    "$(curl -sS -m 10 -D - -o /dev/null "$BASE/health" | tr -d '\r' | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')"
check "nosniff header set"            "nosniff" "$(curl -sS -m 10 -D - -o /dev/null "$BASE/health" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-content-type-options"{print $2}')"
check "player_api is no-store"        "no-store" "$(curl -sS -m 10 -D - -o /dev/null "$API" | tr -d '\r' | awk -F': ' 'tolower($1)=="cache-control"{print $2}')"
check "no Server header leak"         "dramalive-reference-backend" "$(curl -sS -m 10 -D - -o /dev/null "$BASE/health" | tr -d '\r' | awk -F': ' 'tolower($1)=="server"{print $2}')"

# ---------------------------------------------------------------- summary
echo
echo "──────────────────────────────────────────────────────────"
printf '  %d passed, %d failed  (total %d)\n' "$pass" "$fail" "$((pass+fail))"
if [ "$fail" -gt 0 ]; then
  echo "  failed:"; for n in "${FAILED_NAMES[@]}"; do echo "    - $n"; done
  echo "──────────────────────────────────────────────────────────"
  exit 1
fi
echo "──────────────────────────────────────────────────────────"
