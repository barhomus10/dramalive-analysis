#!/usr/bin/env python3
"""
Extrae URLs, dominios y rutas del bundle público de la PWA (`main.dart.js`)
o de los DEX del APK.

Uso:
    analysis/scripts/extract_endpoints.py artifacts/raw/main.dart.js
    analysis/scripts/extract_endpoints.py --dex /ruta/al/apk/descomprimido
    analysis/scripts/extract_endpoints.py --apk dramalive.apk

Salida: informe a stdout + JSON en analysis/evidence/endpoints-<nombre>.json

No ejecuta nada, no descompila y no contacta ningún host. Solo lee literales.
"""

from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import os
import re
import sys
import zipfile
from datetime import datetime, timezone

URL_RE = re.compile(rb"https?://[A-Za-z0-9._~:/?#@!$&*()+,;=%\-]{6,200}")
DOMAIN_RE = re.compile(
    rb"\b(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+"
    rb"(?:com|net|org|io|xyz|top|app|tv|cc|site|online|store|info|live|me|co|dev|pro|"
    rb"news|cloud|host|link|space|fun|shop|click|download|work|ru|de|es|fr)(?:/[\w.~:/?#@!$&*()+,;=%\-]{0,60})?\b"
)
PATH_RE = re.compile(rb'"(/[a-zA-Z0-9_][a-zA-Z0-9_./{}$\-]{2,70})"')

# Dominios que son ruido: documentación, estándares, SDKs publicitarios.
NOISE = re.compile(
    r"(w3\.org|schema\.org|xml\.org|xmlpull|whatwg|android\.com|google|gstatic|"
    r"apache\.org|jabber\.org|xmpp\.org|jivesoftware|igniterealtime|mozilla|"
    r"adobe\.com|microsoft\.com|apple\.com|aomedia|dashif|exoplayer|tizen|"
    r"json-schema|opengis|unicode|ietf|rfc-editor|example\.com|kotlin|"
    r"jetbrains|github\.io|gradle|maven|oracle|sun\.com|eclipse|osgi|slf4j|"
    r"reactivex|squareup|ch\.acra|"
    # SDKs publicitarios y de analítica: no son el objetivo del análisis
    r"applovin|applvn|applov\.in|unity3d|vungle|ironsource|supersonicads|"
    r"startapp|start\.io|tapjoy|mbridge|mosspf|toponad|maticoo|bigo|"
    r"yandex|mail\.ru|my\.com|appnext|appnxt|inmobi|chartboost|doubleclick|"
    r"2mdn|facebook|fb\.com|appmetrica|firebase|crashlytics|byteoversea|"
    r"pangle|pglstatp|ibytedtos|isnssdk|sgsnssdk|tiktok|funsdata|"
    r"cloudfront|weserv|rustore|huawei|appgallery)",
    re.I,
)

# Lo que SÍ interesa: el producto y su ecosistema.
INTEREST = re.compile(
    r"(dramalive|drama\.live|sneig|semprotech|eastgoessouth|fastconnections|"
    r"twoapistack|dataflowstation|mikkm|fgcode|backendcoreapi|swiftapi|"
    r"shai|otzero|dramatv|kora|yallashoot|shabakty|yasinetv|mopikora|elastoor)",
    re.I,
)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def scan_file(path: str):
    data = open(path, "rb").read()
    urls = collections.Counter()
    domains = collections.Counter()
    paths = collections.Counter()

    for m in URL_RE.finditer(data):
        s = m.group(0).decode("latin1").rstrip('\\.,;)]"\'')
        urls[s] += 1
    for m in DOMAIN_RE.finditer(data):
        s = m.group(0).decode("latin1").rstrip("\\.,;)]\"'")
        domains[s] += 1
    for m in PATH_RE.finditer(data):
        paths[m.group(1).decode("latin1")] += 1

    return urls, domains, paths


def gather(targets: list[str]):
    urls, domains, paths = (collections.Counter() for _ in range(3))
    for t in targets:
        u, d, p = scan_file(t)
        urls.update(u)
        domains.update(d)
        paths.update(p)
    return urls, domains, paths


def resolve_apk(apk: str) -> list[str]:
    """Extrae los DEX a un temporal y devuelve sus rutas."""
    import tempfile

    tmp = tempfile.mkdtemp(prefix="dla-dex-")
    out = []
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if name.endswith(".dex"):
                dest = os.path.join(tmp, os.path.basename(name))
                with z.open(name) as src, open(dest, "wb") as dst:
                    dst.write(src.read())
                out.append(dest)
    if not out:
        sys.exit(f"[!] {apk} no contiene ningún .dex")
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="*", help="archivos a escanear (main.dart.js, *.dex)")
    ap.add_argument("--apk", help="APK: extrae y escanea sus DEX")
    ap.add_argument("--dex", help="directorio con DEX ya extraídos")
    ap.add_argument("--out", default=None, help="JSON de salida (por defecto analysis/evidence/)")
    ap.add_argument("--limit", type=int, default=80)
    args = ap.parse_args()

    targets = list(args.targets)
    if args.apk:
        targets += resolve_apk(args.apk)
    if args.dex:
        targets += sorted(glob.glob(os.path.join(args.dex, "*.dex")))
    if not targets:
        ap.error("indica al menos un archivo, --apk o --dex")

    missing = [t for t in targets if not os.path.isfile(t)]
    if missing:
        ap.error("no existen: " + ", ".join(missing))

    urls, domains, paths = gather(targets)

    def interesting(s: str) -> bool:
        return bool(INTEREST.search(s)) and not NOISE.search(s)

    own_urls = {u: c for u, c in urls.items() if interesting(u)}
    own_domains = {d: c for d, c in domains.items() if interesting(d)}
    other_domains = {
        d: c for d, c in domains.items() if not NOISE.search(d) and not INTEREST.search(d)
    }

    print("=" * 78)
    print("extract_endpoints")
    for t in targets:
        print(f"  · {t}  ({os.path.getsize(t):,} B, sha256 {sha256(t)[:16]})")
    print("=" * 78)

    print(f"\n### URLs del producto ({len(own_urls)}) ###")
    for u, c in sorted(own_urls.items(), key=lambda kv: -kv[1]):
        print(f"  {c:>4}×  {u}")

    print(f"\n### Dominios del producto ({len(own_domains)}) ###")
    for d, c in sorted(own_domains.items(), key=lambda kv: -kv[1]):
        print(f"  {c:>4}×  {d}")

    print(f"\n### Otros dominios no publicitarios ({len(other_domains)}, top {args.limit}) ###")
    for d, c in sorted(other_domains.items(), key=lambda kv: -kv[1])[: args.limit]:
        print(f"  {c:>4}×  {d}")

    app_paths = [p for p in paths if not p.startswith(
        ("/flutter", "/packages", "/assets", "/icons", "/canvaskit"))]
    print(f"\n### Rutas literales ({len(app_paths)}) ###")
    for p in sorted(app_paths)[: args.limit]:
        print(f"  {paths[p]:>4}×  {p}")

    total_urls = sum(urls.values())
    print(f"\n(total bruto: {len(urls)} URLs distintas / {total_urls} apariciones, "
          f"{len(domains)} dominios, {len(paths)} rutas)")

    report = {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "tool": "analysis/scripts/extract_endpoints.py",
        "inputs": [
            {"path": t, "bytes": os.path.getsize(t), "sha256": sha256(t)} for t in targets
        ],
        "product_urls": own_urls,
        "product_domains": own_domains,
        "other_domains": other_domains,
        "path_literals": sorted(app_paths),
        "totals": {
            "distinct_urls": len(urls),
            "url_occurrences": total_urls,
            "distinct_domains": len(domains),
            "distinct_paths": len(paths),
        },
    }

    out = args.out
    if out is None:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        stem = os.path.basename(targets[0]).replace(".", "-")
        out = os.path.join(root, "analysis", "evidence", f"endpoints-{stem}.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    print(f"\n→ {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
