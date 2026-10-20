#!/usr/bin/env bash
# Descarga el build web público de web.dramalive.cc y deja constancia de ello.
#
# Solo peticiones GET anónimas, sin autenticación y sin carga. Son ~8 requests.
# Los artefactos NO se versionan (artifacts/ está en .gitignore): son binarios
# de terceros. Regenera esto en local cuando haga falta.
#
#   analysis/scripts/fetch_web_artifacts.sh
#   BASE=https://web.dramalive.cc OUT=artifacts/raw analysis/scripts/fetch_web_artifacts.sh
set -euo pipefail

BASE="${BASE:-https://web.dramalive.cc}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${OUT:-$ROOT/artifacts/raw}"
mkdir -p "$OUT"

PATHS=(
  "index.html"
  "manifest.json"
  "version.json"
  "flutter_bootstrap.js"
  "main.dart.js"
  "assets/AssetManifest.json"
  "assets/AssetManifest.bin.json"
  "icons/Icon-192.png"
)

echo "fetch_web_artifacts · BASE=$BASE"
echo "                    · OUT=$OUT"
echo

fail=0
for p in "${PATHS[@]}"; do
  mkdir -p "$OUT/$(dirname "$p")"
  dest="$OUT/$p"
  # -f: falla en 4xx/5xx. Importante porque el sitio tiene SPA fallback y
  # devuelve index.html con 200 para cualquier ruta inexistente (docs/01 §2).
  code=$(curl -sSfL -m 120 -o "$dest" -w '%{http_code}' "$BASE/$p" 2>/dev/null || echo "ERR")
  if [ "$code" = "ERR" ]; then
    printf '  \033[31mFAIL\033[0m  %-34s (no descargable)\n' "$p"; fail=$((fail+1)); rm -f "$dest"; continue
  fi
  size=$(wc -c < "$dest" | tr -d ' ')
  # Detección de falsos positivos del SPA fallback.
  if [ "$p" != "index.html" ] && head -c 64 "$dest" | grep -q '<!DOCTYPE html'; then
    printf '  \033[33mFAKE\033[0m  %-34s (devolvió index.html — no existe)\n' "$p"
    rm -f "$dest"; continue
  fi
  sha=$(sha256sum "$dest" | cut -c1-16)
  printf '  \033[32mok\033[0m    %-34s %10s B  sha256:%s\n' "$p" "$size" "$sha"
done

cat > "$OUT/FETCHED.md" <<EOF
# Artefactos descargados

- **Origen:** \`$BASE\`
- **Fecha:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')
- **Método:** \`GET\` anónimos (sin auth, sin carga). $((${#PATHS[@]} - fail)) de ${#PATHS[@]} rutas.

| archivo | bytes | sha256 |
|---|---|---|
$(for p in "${PATHS[@]}"; do
  [ -f "$OUT/$p" ] || continue
  printf '| `%s` | %s | `%s` |\n' "$p" "$(wc -c < "$OUT/$p" | tr -d ' ')" "$(sha256sum "$OUT/$p" | cut -d' ' -f1)"
done)

> Estos archivos **no se versionan** (\`.gitignore\`). Son binarios de terceros:
> reproducibles con este script, y su redistribución no es el objetivo del repo.

## version.json

\`\`\`json
$(cat "$OUT/version.json" 2>/dev/null || echo '(no descargado)')
\`\`\`
EOF

echo
echo "→ $OUT/FETCHED.md"
[ "$fail" -eq 0 ] || echo "⚠ $fail artefacto(s) no disponibles"
