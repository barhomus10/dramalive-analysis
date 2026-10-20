#!/usr/bin/env bash
# Saneado: comprueba que lo que se va a versionar no filtra secretos,
# credenciales ni datos personales de terceros.
#
#   analysis/scripts/sanitize.sh                 # revisa lo staged (o todo lo versionado)
#   analysis/scripts/sanitize.sh --all           # revisa todos los archivos del repo
#   analysis/scripts/sanitize.sh --install-hook  # instala el hook pre-commit
#   analysis/scripts/sanitize.sh --self-test     # comprueba que el detector funciona
#
# Sale con 1 si encuentra algo. El hook de pre-commit lo usa para bloquear el commit.
#
# NOTA DE IMPLEMENTACIÓN: las reglas son ARRAYS paralelos, no cadenas
# delimitadas. Una versión anterior usaba `|` como separador de campos y varias
# regex contenían `|` (alternancia), así que `%%|*` truncaba la regla y cinco
# detectores —incluidos los de clave privada, Bearer/Basic y credenciales de
# crash reporting— no se evaluaban nunca. `--self-test` existe para que ese
# fallo no vuelva a pasar desapercibido.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="staged"; INSTALL_HOOK=0; SELF_TEST=0
for a in "$@"; do
  case "$a" in
    --install-hook) INSTALL_HOOK=1 ;;
    --all)          MODE="all" ;;
    --self-test)    SELF_TEST=1 ;;
    -h|--help)      sed -n '2,14p' "$0"; exit 0 ;;
    *)              echo "opción desconocida: $a" >&2; exit 2 ;;
  esac
done

# ══════════════════════════════════════════════════════════════════════════
# REGLAS — tres arrays paralelos. Añadir una = una línea en cada array.
# ══════════════════════════════════════════════════════════════════════════
SEV=(
  CRIT  CRIT  CRIT  CRIT  CRIT  CRIT  CRIT  CRIT
  ALTA  ALTA  ALTA  ALTA  ALTA  ALTA
  MEDIA MEDIA MEDIA MEDIA
)
RX=(
  'github_pat_[A-Za-z0-9_]{20,}'
  'ghp_[A-Za-z0-9]{30,}'
  'gho_[A-Za-z0-9]{30,}'
  'github_pat_[A-Za-z0-9_]{10,}'
  '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY( BLOCK)?-----'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  '(sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})'

  'crash_reporting_(login|password)[[:space:]]*"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9+/=_-]{8,}'
  '"[A-Za-z0-9_]*password[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*"[^"]{6,}"'
  '(password|passwd|pwd|passkey|secret|api_key|apikey|token)=[A-Za-z0-9._%+/-]{8,}'
  'Authorization:[[:space:]]*(Basic|Bearer)[[:space:]]+[A-Za-z0-9._+/=-]{16,}'
  '\b([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{2,5}\b'
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'

  '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'
  'admin_email[a-z_]*"?[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9._@+-]{6,}'
  '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
  '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\b'
)
DESC=(
  'token de GitHub (fine-grained PAT)'
  'token clásico de GitHub'
  'token OAuth de GitHub'
  'token de GitHub (parcial)'
  'clave privada'
  'AWS access key id'
  'token de Slack'
  'clave de API (OpenAI / Google)'

  'credenciales del colector de crashes (hallazgo F-01)'
  'contraseña en un JSON'
  'secreto en un query string o asignación'
  'cabecera de autenticación real'
  'IP con puerto (infraestructura de terceros, F-03)'
  'JWT'

  'dirección de correo (no pública)'
  'identificador de cuenta de administración'
  'UUID (¿device_id / installation id?)'
  'posible número de tarjeta'
)

if [ "${#SEV[@]}" -ne "${#RX[@]}" ] || [ "${#SEV[@]}" -ne "${#DESC[@]}" ]; then
  echo "✗ sanitize.sh: los arrays SEV/RX/DESC no tienen la misma longitud" >&2
  echo "  SEV=${#SEV[@]} RX=${#RX[@]} DESC=${#DESC[@]}" >&2
  exit 3
fi

# Archivos donde los patrones son esperables y legítimos (tests, fixtures,
# el propio script, la doc que los explica).
ALLOWLIST=(
  'analysis/scripts/sanitize.sh'
  'backend/test.sh'
  'backend/src/data/catalog.json'
  'client/web/index.html'
  'client/lib/features/playlist/source_screen.dart'
  'client/lib/data/repositories/settings_repository.dart'
  'docs/07-HALLAZGOS-SEGURIDAD.md'
  'docs/05-API.md'
)

# Correos PÚBLICOS: el canal de contacto lo publica la propia app en su config
# embebida y es el destinatario de la divulgación responsable. No son PII.
PUBLIC_MAIL='support@dramalive\.org|noreply@localhost|example\.(com|org)|@localhost|schemas\.|git@github\.com'

is_allowed() {
  local f="${1#./}" a                       # normaliza el prefijo ./ de `find`
  for a in "${ALLOWLIST[@]}"; do
    [ "$f" = "$a" ] && return 0
    [ "$f" = "${a#./}" ] && return 0
  done
  return 1
}

# ══════════════════════════════════════════════════════════════════════════
# Instalación del hook
# ══════════════════════════════════════════════════════════════════════════
if [ "$INSTALL_HOOK" = "1" ]; then
  mkdir -p .git/hooks
  cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Instalado por `make hooks`. Bloquea commits que filtren secretos.
if ! bash analysis/scripts/sanitize.sh; then
  echo
  echo "commit BLOQUEADO por analysis/scripts/sanitize.sh"
  echo "Revisa los hallazgos de arriba. Si es un falso positivo legítimo,"
  echo "añade el archivo a ALLOWLIST en el script, justificándolo en el commit."
  echo "Saltarlo (no recomendado):  git commit --no-verify"
  exit 1
fi
HOOK
  chmod +x .git/hooks/pre-commit
  echo "✓ hook instalado en .git/hooks/pre-commit"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════
# Escaneo
# ══════════════════════════════════════════════════════════════════════════
hits=0; crit=0; alta=0; media=0
declare -A seen

scan_one() {
  local f="$1"
  case "$f" in *.apk|*.aab|*.dex|*.so|*.png|*.jpg|*.jpeg|*.webp|*.gif|*.gz|*.zip|*.jar|*.aar|*.ttf|*.woff*|*.ico|*.pdf) return ;; esac
  [ -f "$f" ] || return
  is_allowed "$f" && return

  local i sev rx desc line ln text key color
  for i in "${!RX[@]}"; do
    sev="${SEV[$i]}"; rx="${RX[$i]}"; desc="${DESC[$i]}"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      ln="${line%%:*}"; text="${line#*:}"

      # ── excepciones: placeholders y valores vacíos/de demo ──────────────
      case "$text" in
        *REDACTED*|*'[[REDACTED'*|*'<password>'*|*'<TU-USUARIO>'*|*'your-token'*|*'example.com'*|*'…'*) continue ;;
      esac
      # clave vacía o de demostración
      grep -qE '"[A-Za-z0-9_]*password[A-Za-z0-9_]*"[[:space:]]*:[[:space:]]*""' <<<"$text" && continue
      grep -qE '(^|[^A-Za-z0-9_])(demo|changeme|placeholder|xxx+|null|undefined)([^A-Za-z0-9_]|$)' <<<"$text" \
        && ! grep -qE '(github_pat_|ghp_|AKIA|xox[baprs]-|BEGIN [A-Z ]*PRIVATE KEY)' <<<"$text" && continue
      # correos públicos / plantillas
      grep -qE "$PUBLIC_MAIL" <<<"$text" && ! grep -qE '[A-Za-z0-9._%+-]+@(gmail|hotmail|outlook|yahoo|icloud|proton)' <<<"$text" && continue
      # línea de comentario que describe el patrón
      grep -qE '^[[:space:]]*[#*/-].*(patrón|pattern|regex|ejemplo|placeholder)' <<<"$text" && continue
      # documentado como hallazgo sin el valor real
      grep -qE '(16 caracteres|REDACTADO|<[A-Za-z][A-Za-z0-9_ -]{2,}>)' <<<"$text" && continue

      key="$f|$i"
      [ -n "${seen[$key]:-}" ] && continue
      seen[$key]=1
      hits=$((hits+1))
      case "$sev" in
        CRIT)  crit=$((crit+1));  color=$'\033[31m' ;;
        ALTA)  alta=$((alta+1));  color=$'\033[33m' ;;
        MEDIA) media=$((media+1)); color=$'\033[36m' ;;
        *)     color=$'\033[0m' ;;
      esac
      printf '  %s%-5s\033[0m %-52s %s:%s\n' "$color" "$sev" "$desc" "$f" "$ln"
      printf '         %s\n' "$(sed 's/^[[:space:]]*//' <<<"$text" | cut -c1-150)"
    done < <(grep -nE -- "$rx" "$f" 2>/dev/null)
  done
}

# ── self-test real (usa scan_one, así que valida el detector de verdad) ──
if [ "$SELF_TEST" = "1" ]; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  cat > "$tmp/leak.md" <<'EOF'
crash_reporting_login: "aNzxD8k2nrurTgth"
crash_reporting_password: "4Ca2hSkz38FtAb0p"
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def
token=ghp_16C4yH3Fk9Zm2Qx7Lp0Rb8Wv4Nj6Td1A
-----BEGIN RSA PRIVATE KEY-----
AKIAIOSFODNN7EXAMPLE
url: http://18.194.81.219:8787/api
contacto: juan.perez@gmail.com
sk-proj-abcdefghijklmnopqrstuvwxyz1234
xoxb-1234567890-abcdefghijkl
EOF
  cat > "$tmp/clean.md" <<'EOF'
# Documento limpio
crash_reporting_login: "[[REDACTED — ver docs/07-HALLAZGOS-SEGURIDAD.md]]"
url: http://main.eastgoessouth.online/api/live/livedrama/v13.0.0/
contacto público: support@dramalive.org
password: ""
cuenta demo / demo
EOF
  echo "self-test · el detector DEBE marcar leak.md y NO marcar clean.md"
  echo
  hits=0; crit=0; alta=0; media=0; seen=()
  scan_one "$tmp/leak.md"
  leak=$hits
  hits=0; crit=0; alta=0; media=0; seen=()
  scan_one "$tmp/clean.md"
  clean=$hits
  echo
  printf '  leak.md  → %d hallazgo(s)   %s\n' "$leak"  "$([ "$leak" -ge 10 ] && echo '✓' || echo '✗ esperaba >= 10')"
  printf '  clean.md → %d hallazgo(s)   %s\n' "$clean" "$([ "$clean" -eq 0 ] && echo '✓' || echo '✗ esperaba 0')"
  echo
  if [ "$leak" -ge 10 ] && [ "$clean" -eq 0 ]; then
    echo "✓ self-test OK"; exit 0
  else
    echo "✗ self-test FALLA — el detector no es fiable, no commitees nada"; exit 1
  fi
fi

# ── selección de archivos ─────────────────────────────────────────────────
files=()
if [ "$MODE" = "staged" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && files+=("$f"); done \
    < <(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)
  if [ "${#files[@]}" -eq 0 ]; then
    while IFS= read -r f; do files+=("$f"); done < <(git ls-files 2>/dev/null)
  fi
fi
if [ "${#files[@]}" -eq 0 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(
    find . -type f \
      -not -path './.git/*' -not -path './artifacts/*' -not -path './node_modules/*' \
      -not -path '*/__pycache__/*' -not -path './client/build/*' -not -path './client/.dart_tool/*' \
      2>/dev/null)
fi

if [ "${#files[@]}" -eq 0 ]; then echo "sanitize: nada que revisar"; exit 0; fi

echo "sanitize · ${#files[@]} archivo(s) · modo '$MODE'"
for f in "${files[@]}"; do scan_one "$f"; done

echo
if [ "$hits" -eq 0 ]; then
  echo "✓ limpio: ningún secreto ni dato personal de terceros en ${#files[@]} archivo(s)"
  exit 0
fi

printf '⚠ %d hallazgo(s): %d crítico(s), %d alto(s), %d medio(s)\n' "$hits" "$crit" "$alta" "$media"
echo
echo "Qué hacer:"
echo "  • credenciales de terceros → redactar como [[REDACTED — ver docs/07-…]]"
echo "  • IPs de infraestructura   → sustituir por [[REDACTED-IP]]"
echo "  • correos no públicos      → sustituir por [[REDACTED-PII]]"
echo "  • tokens propios           → revocar YA y sacarlos del historial (git filter-repo)"
echo
echo "Exentos: ${ALLOWLIST[*]}"
echo "Comprueba que el detector funciona con:  $0 --self-test"
exit 1
