#!/usr/bin/env bash
# Sube este repo a GitHub.
#
#   ./push.sh                       # repo "dramalive-analysis", público
#   ./push.sh mi-nombre             # otro nombre
#   ./push.sh mi-nombre --private   # privado
#
# Autenticación, en orden de preferencia:
#   1. `gh` CLI ya autenticado        (gh auth login)
#   2. GITHUB_TOKEN en el entorno     (export GITHUB_TOKEN=…)   ← nunca lo escribas en un archivo
#   3. credenciales guardadas en git  (git credential / SSH)
#
# El token NO se guarda en ningún archivo del repo ni en la URL del remote:
# se usa solo en memoria y el remote queda con la URL limpia.
#
# ⚠ Si alguna vez pegaste un token en un chat, un issue o un log, está
#   comprometido: revócalo en GitHub → Settings → Developer settings → Tokens.
set -euo pipefail

REPO="${1:-dramalive-analysis}"
PRIVATE=0
[ "${2:-}" = "--private" ] && PRIVATE=1
[ "${1:-}" = "--private" ] && { REPO="dramalive-analysis"; PRIVATE=1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
VIS=$([ "$PRIVATE" = "1" ] && echo "privado" || echo "público")

echo "────────────────────────────────────────────────────────────"
echo " push.sh · repo '$REPO' ($VIS) · rama '$BRANCH'"
echo "────────────────────────────────────────────────────────────"

# ------------------------------------------------- 0. saneado antes de nada
echo
echo "→ saneado (secretos / datos de terceros)"
if ! bash analysis/scripts/sanitize.sh --all; then
  echo
  echo "✗ ABORTADO: hay hallazgos que revisar arriba."
  echo "  Arréglalos, o añade el archivo a ALLOWLIST en analysis/scripts/sanitize.sh"
  echo "  si el patrón es legítimo en ese contexto."
  exit 1
fi

# ------------------------------------------------------ 1. estado del repo
echo
echo "→ git"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  git init -q -b main
  echo "  init (rama main)"
fi
git add -A

if git diff --cached --quiet; then
  echo "  nada nuevo que commitear"
else
  git -c user.name="${GIT_AUTHOR_NAME:-dramalive-analysis}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-noreply@localhost}" \
      commit -q -m "$(cat <<'MSG'
Análisis de Drama Live v13.0.3 + cliente réplica y backend de referencia

Hallazgos del APK (com.sneig.livedrama 13.0.3/187, sha256 a3ab61b5...):
- config remota embebida en classes.dex con todo el mapa de servidores
- backend propio en *.eastgoessouth.online, todo por HTTP plano
- credenciales del colector de crashes en claro (redactadas aquí)
- plantilla white-label: 25 paquetes en banned_apps
- 15 SDKs publicitarios integrados, desactivados por flag remoto
- 7 actividades propias frente a 102 en total

Incluye:
- docs/00..07: alcance legal, recon web, arquitectura, stack, fuentes,
  contrato de API, flujo con REA y hallazgos de seguridad
- backend/: implementación de referencia del contrato Xtream player_api.php
  (Node, sin dependencias) + HLS sintético + suite de contrato
- client/: réplica Flutter (Android/web) con 4 fuentes, reproductor y ajustes
- analysis/: scripts reproducibles + tarea y config para REA

No contiene binarios, contenido ni credenciales de terceros.
MSG
)"
  echo "  commit creado"
fi

git log --oneline | head -3 | sed 's/^/    /'

# ------------------------------------------------------ 2. crear el remoto
echo
OWNER=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "→ gh CLI autenticado"
  OWNER="$(gh api user --jq .login)"
  if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
    echo "  el repo $OWNER/$REPO ya existe — se reutiliza"
  else
    if [ "$PRIVATE" = "1" ]; then gh repo create "$REPO" --private >/dev/null
    else gh repo create "$REPO" --public >/dev/null; fi
    echo "  creado $OWNER/$REPO"
  fi
  REMOTE="https://github.com/$OWNER/$REPO.git"

elif [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "→ GITHUB_TOKEN detectado en el entorno"
  OWNER="$(curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" \
             -H "Accept: application/vnd.github+json" \
             https://api.github.com/user | python3 -c 'import sys,json;print(json.load(sys.stdin)["login"])')"
  [ -z "$OWNER" ] && { echo "✗ el token no identifica a ningún usuario"; exit 1; }

  code="$(curl -sS -o /tmp/repo-create.json -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    https://api.github.com/user/repos \
    -d "{\"name\":\"$REPO\",\"private\":$([ "$PRIVATE" = 1 ] && echo true || echo false),\"auto_init\":false,\"description\":\"Documented reverse engineering of the Drama Live Flutter/IPTV app using REA, plus a reference client and backend.\"}")"

  if [ "$code" = "201" ]; then
    echo "  creado $OWNER/$REPO"
  elif grep -q 'already exists' /tmp/repo-create.json 2>/dev/null; then
    echo "  el repo $OWNER/$REPO ya existe — se reutiliza"
  else
    echo "✗ la creación falló (HTTP $code):"; cat /tmp/repo-create.json; exit 1
  fi
  rm -f /tmp/repo-create.json
  REMOTE="https://github.com/$OWNER/$REPO.git"

else
  echo "→ sin gh ni GITHUB_TOKEN"
  echo "  Crea el repo a mano en https://github.com/new (nombre: $REPO, $VIS, sin README)"
  echo "  y luego:  git remote add origin git@github.com:<TU-USUARIO>/$REPO.git"
  echo "            git push -u origin $BRANCH"
  echo
  echo "  O exporta un token solo para esta ejecución (no queda en ningún archivo):"
  echo "            read -rs GITHUB_TOKEN && export GITHUB_TOKEN && ./push.sh $REPO"
  exit 0
fi

# ------------------------------------------------------------- 3. sincronizar
echo
echo "→ sincronizando con $REMOTE"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
else
  git remote add origin "$REMOTE"
fi
# El remote queda con la URL LIMPIA (sin token). La autenticación para el push
# se pasa por cabecera, no por la URL, para que no quede en .git/config.
git fetch -q origin 2>/dev/null || true
if git rev-parse --verify -q "origin/$BRANCH" >/dev/null; then
  echo "  la rama $BRANCH ya existe en el remoto — rebase local encima"
  git -c user.name="${GIT_AUTHOR_NAME:-dramalive-analysis}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-noreply@localhost}" \
      rebase "origin/$BRANCH" || {
        echo "  ⚠ conflicto en el rebase. Resuélvelo y vuelve a ejecutar."
        exit 1; }
fi

if [ -n "${GITHUB_TOKEN:-}" ] && ! command -v gh >/dev/null 2>&1; then
  # push con el token en la cabecera, sin incrustarlo en la URL
  git -c "http.extraHeader=Authorization: Bearer $GITHUB_TOKEN" \
      push -u origin "$BRANCH"
else
  git push -u origin "$BRANCH"
fi

echo
echo "────────────────────────────────────────────────────────────"
echo " ✓ https://github.com/$OWNER/$REPO"
echo "────────────────────────────────────────────────────────────"
echo
echo "Verifica que el remote no lleva credenciales:"
echo "  git remote -v        # debe salir https://github.com/$OWNER/$REPO.git"
echo "  grep -r token .git/config"
