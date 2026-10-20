#!/usr/bin/env bash
# Triage de un APK: identidad, firma, manifiesto, literales de red y la config
# remota embebida. Deja todo en analysis/evidence/ con hashes y fecha.
#
#   analysis/scripts/apk_triage.sh /ruta/a/dramalive.apk
#
# Requisitos: python3 + `pip install androguard`. Opcionales (mejor salida):
# apktool, jadx, aapt/aapt2. Si faltan, el script sigue con lo que hay.
#
# NO ejecuta la app. NO descompila a menos que esté jadx/apktool. NO contacta
# ningún host que aparezca en el binario.
set -euo pipefail

APK="${1:-}"
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
  echo "uso: $0 <ruta-al.apk>" >&2; exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="$(basename "$APK" .apk)"
EV="$ROOT/analysis/evidence/apk-$NAME"
WORK="$(mktemp -d /tmp/dla-apk.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$EV"

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- identidad
log "APK"
SIZE=$(wc -c < "$APK" | tr -d ' ')
SHA=$(sha256sum "$APK" | cut -d' ' -f1)
MD5=$(md5sum "$APK" | cut -d' ' -f1)
echo "  archivo : $APK"
echo "  bytes   : $SIZE"
echo "  sha256  : $SHA"
echo "  md5     : $MD5"
have unzip && unzip -l "$APK" | tail -1 | awk '{print "  entradas: "$2}'

{
  echo "# Artefacto analizado"
  echo
  echo "- **archivo:** \`$(basename "$APK")\`"
  echo "- **bytes:** $SIZE"
  echo "- **sha256:** \`$SHA\`"
  echo "- **md5:** \`$MD5\`"
  echo "- **fecha de triage:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo
  echo "> El binario **no** se versiona (\`.gitignore\`). Solo se guardan los"
  echo "> hallazgos derivados, con credenciales de terceros redactadas."
} > "$EV/00-IDENTIDAD.md"

# ------------------------------------------------------------- descomprimir
log "Descomprimiendo"
if have unzip; then
  unzip -o -q "$APK" -d "$WORK" 2>/dev/null || true
  echo "  -> $WORK"
  {
    echo "# Inventario del APK"
    echo
    echo '```'
    find "$WORK" -maxdepth 1 -mindepth 1 -printf '%y %10s  %P\n' | sort -k3
    echo '```'
    echo
    echo "## Bibliotecas nativas por ABI"
    echo
    for abi in "$WORK"/lib/*/; do
      [ -d "$abi" ] || continue
      echo "### $(basename "$abi")"
      echo
      echo '```'
      ls -l "$abi" 2>/dev/null | awk 'NR>1{printf "%10s  %s\n",$5,$9}'
      echo '```'
      echo
    done
    echo "## DEX"
    echo
    echo '```'
    ls -l "$WORK"/classes*.dex 2>/dev/null | awk '{printf "%10s  %s\n",$5,$9}'
    echo '```'
  } > "$EV/01-INVENTARIO.md"
else
  echo "  ⚠ sin 'unzip'; se omite el inventario"
fi

# ---------------------------------------------------------------- manifiesto
log "Manifiesto + firma (androguard)"
if python3 -c 'import androguard' 2>/dev/null; then
  python3 - "$APK" "$EV/02-MANIFIESTO.md" <<'PY'
import logging, os, re, sys, json
os.environ["LOGURU_LEVEL"] = "ERROR"
logging.disable(logging.CRITICAL)
try:
    from loguru import logger; logger.remove()
except Exception: pass
from androguard.core.apk import APK

apk_path, out_path = sys.argv[1], sys.argv[2]
a = APK(apk_path)
A = "{http://schemas.android.com/apk/res/android}"
ADNET = re.compile(r"(applovin|unity3d|vungle|ironsource|supersonic|startapp|"
                   r"tapjoy|mbridge|maticoo|bigo|yandex|my\.target|mytarget|"
                   r"appnext|inmobi|topon|anythink|chartboost|appmetrica|"
                   r"play-services|firebase_|adservices|androidx\.|"
                   r"com\.google\.android|pangle|bytedance)", re.I)
own_pkg = a.get_package() or ""
root = ".".join(own_pkg.split(".")[:3]) if own_pkg else ""

def own(items):
    return [x for x in items if root and x.startswith(root)]

lines = []
w = lines.append
w("# AndroidManifest.xml")
w("")
w(f"- **package:** `{a.get_package()}`")
w(f"- **app name:** {a.get_app_name()}")
w(f"- **versionName:** {a.get_androidversion_name()}  ·  **versionCode:** {a.get_androidversion_code()}")
w(f"- **minSdk:** {a.get_min_sdk_version()}  ·  **targetSdk:** {a.get_target_sdk_version()}")
w(f"- **main activity:** `{a.get_main_activity()}`")
w(f"- **libraries:** {a.get_libraries()}")
w("")
w("## Firma")
w("")
w(f"- v1 (JAR): {a.is_signed_v1()} · v2: {a.is_signed_v2()} · v3: {a.is_signed_v3()}")
for c in a.get_certificates():
    w(f"- **issuer / subject:** {c.issuer.human_friendly} / {c.subject.human_friendly}")
    w(f"- **serial:** {c.serial_number}")
    w(f"- **validez:** {c.not_valid_before} → {c.not_valid_after}")
    w(f"- **sha256:** `{c.sha256_fingerprint.replace(' ','')}`")
w("")
w(f"## Permisos ({len(a.get_permissions())})")
w("")
for p in sorted(a.get_permissions()):
    w(f"- `{p}`")
w("")
acts, svcs, recvs, provs = (a.get_activities(), a.get_services(),
                            a.get_receivers(), a.get_providers())
w("## Componentes")
w("")
w(f"| tipo | propios | total |")
w(f"|---|---|---|")
w(f"| actividades | {len(own(acts))} | {len(acts)} |")
w(f"| servicios | {len(own(svcs))} | {len(svcs)} |")
w(f"| receivers | {len(own(recvs))} | {len(recvs)} |")
w(f"| providers | {len(own(provs))} | {len(provs)} |")
w("")
for label, items in [("Actividades propias", acts), ("Servicios propios", svcs),
                     ("Receivers propios", recvs), ("Providers propios", provs)]:
    o = own(items)
    if not o: continue
    w(f"### {label}")
    w("")
    for x in o: w(f"- `{x}`")
    w("")
w("## Application")
w("")
for el in a.get_android_manifest_xml().iter():
    if str(el.tag).endswith("application"):
        for k in ("name","allowBackup","debuggable","largeHeap","usesCleartextTraffic",
                  "networkSecurityConfig","hardwareAccelerated","theme","label"):
            v = el.get(A+k)
            if v is not None: w(f"- `{k}` = `{v}`")
        break
w("")
w("## meta-data relevantes")
w("")
for el in a.get_android_manifest_xml().iter():
    if not str(el.tag).endswith("meta-data"): continue
    n = el.get(A+"name")
    if not n or ADNET.search(n): continue
    v = el.get(A+"value") or ("@"+str(el.get(A+"resource")) if el.get(A+"resource") else "")
    w(f"- `{n}` = `{v}`")
w("")
w("---")
w("")
w(f"*Generado por `analysis/scripts/apk_triage.sh`. {len(acts)} actividades en total, "
  f"de las cuales {len(acts)-len(own(acts))} pertenecen a SDKs de terceros.*")
open(out_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("  -> " + out_path)
print(f"  package={a.get_package()} version={a.get_androidversion_name()}({a.get_androidversion_code()}) "
      f"sdk={a.get_min_sdk_version()}/{a.get_target_sdk_version()} actividades={len(acts)}")
PY
else
  echo "  ⚠ androguard no instalado — ejecuta: pip install androguard"
fi

# ------------------------------------------------------- config embebida
log "Config remota embebida (literales del DEX)"
python3 - "$APK" "$WORK" <<'PY'
import json, re, sys, zipfile, os
apk, work = sys.argv[1], sys.argv[2]
found = []
with zipfile.ZipFile(apk) as z:
    for n in z.namelist():
        if not n.endswith(".dex"): continue
        d = z.read(n)
        # La config de la app original es un JSON con "server_url".
        for m in re.finditer(rb'server_url', d):
            s = m.start()
            while s > 0 and 0x20 <= d[s-1] < 0x7f: s -= 1
            e = m.end()
            while e < len(d) and 0x20 <= d[e] < 0x7f: e += 1
            run = d[s:e].decode("latin1", "replace")
            i = run.find("{")
            if i < 0: continue
            found.append((n, s, run[i:]))
if not found:
    print("  (no se encontró ninguna config JSON embebida)")
    sys.exit(0)
found.sort(key=lambda x: -len(x[2]))
dex, off, raw = found[0]
print(f"  encontrada en {dex} @ offset {off} ({len(raw)} B)")
try:
    cfg = json.loads(raw.replace("\\/", "/"))
except Exception as e:
    print(f"  ⚠ no parsea como JSON: {e}")
    open(os.path.join(work, "embedded_config_raw.txt"), "w").write(raw)
    sys.exit(0)

REDACT = ["crash_reporting_login", "crash_reporting_password", "admin_email",
          "admin_email_paid", "support_email"]
IP = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b")
redacted_log = []

def redact(node, path=""):
    if isinstance(node, dict):
        for k, v in list(node.items()):
            p = f"{path}.{k}" if path else k
            if k in REDACT and isinstance(v, str) and v:
                node[k] = f"[[REDACTED — ver docs/07-HALLAZGOS-SEGURIDAD.md]]"
                redacted_log.append(p)
            else:
                redact(v, p)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            redact(v, f"{path}[{i}]")
    elif isinstance(node, str):
        for ip in set(IP.findall(node)):
            # No publicar IPs de infraestructura de terceros.
            node = node.replace(ip, "[[REDACTED-IP]]")
            redacted_log.append(f"{path} (IP {ip})")
        # mutar en el padre no es posible aquí; se hace en el nivel dict/list
redact(cfg)
# segunda pasada para IPs dentro de strings (la anterior no reescribe el padre)
def fix_ips(node):
    if isinstance(node, dict):  return {k: fix_ips(v) for k, v in node.items()}
    if isinstance(node, list):  return [fix_ips(v) for v in node]
    if isinstance(node, str):   return IP.sub("[[REDACTED-IP]]", node)
    return node
cfg = fix_ips(cfg)

open(os.path.join(work, "embedded_config_raw.txt"), "w").write(raw)
print(f"  campos redactados: {len(redacted_log)}")
for r in redacted_log[:12]: print(f"    - {r}")
json.dump(cfg, open(os.path.join(work, "embedded_config_REDACTED.json"), "w"),
          indent=2, ensure_ascii=False)
PY

if [ -f "$WORK/embedded_config_REDACTED.json" ]; then
  cp "$WORK/embedded_config_REDACTED.json" "$EV/03-CONFIG-EMBEDIDA.REDACTED.json"
  echo "  -> $EV/03-CONFIG-EMBEDIDA.REDACTED.json"
fi
# El crudo SIN redactar NO se copia a evidence/: se queda fuera del repo.
mkdir -p "$ROOT/artifacts/apk-config"
[ -f "$WORK/embedded_config_raw.txt" ] && \
  cp "$WORK/embedded_config_raw.txt" "$ROOT/artifacts/apk-config/$NAME.raw.txt" && \
  echo "  (crudo sin redactar → artifacts/, fuera de git)"

# ------------------------------------------------------------------ red
log "Literales de red"
if have python3; then
  python3 "$ROOT/analysis/scripts/extract_endpoints.py" --apk "$APK" \
    --out "$EV/04-ENDPOINTS.json" | tail -40
fi

# ------------------------------------------------------- herramientas opcionales
log "Herramientas opcionales"
for t in apktool jadx aapt aapt2 baksmali; do
  if have "$t"; then echo "  ✓ $t ($(command -v $t))"; else echo "  ✗ $t — no instalado"; fi
done
cat >> "$EV/00-IDENTIDAD.md" <<EOF

## Herramientas

| herramienta | presente |
|---|---|
$(for t in unzip python3 apktool jadx aapt aapt2 baksmali java; do
    if have "$t"; then echo "| \`$t\` | ✓ |"; else echo "| \`$t\` | ✗ |"; fi
  done)

Siguiente paso: análisis con REA — ver \`docs/06-FLUJO-REA.md\` y
\`analysis/rea/REA-TASK.md\`.
EOF

log "Listo"
echo "  evidencia → $EV"
ls -1 "$EV"
