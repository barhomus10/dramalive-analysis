# dramalive-analysis

Ingeniería inversa documentada de **Drama Live** (`com.sneig.livedrama`, v13.0.3 build 187)
y de su PWA (`https://web.dramalive.cc/`, v13.0.3 build 241), más un **cliente réplica**
(Flutter) y un **backend de referencia** (Node) que implementa el mismo contrato de API.

Preparado para continuar el análisis con
[REA — *Reverse engineer anything with agents*](https://github.com/morluto/rea):
la tarea y la configuración están escritas en [`analysis/rea/`](analysis/rea/REA-TASK.md).

> ⚠️ **Lee [`docs/00-LEGAL-Y-ALCANCE.md`](docs/00-LEGAL-Y-ALCANCE.md) antes de usar nada de
> este repo.** Es investigación e interoperabilidad. No incluye, redistribuye ni facilita
> contenido audiovisual de terceros, no usa credenciales ajenas y no elude pagos, DRM ni
> controles de acceso. Los binarios analizados **no** se versionan.

---

## 1. Resumen ejecutivo

**Drama Live no es una app de "short dramas".** Pese al nombre, es un **reproductor IPTV de
tipo *bring-your-own-source*** — en la familia de TiviMate o IPTV Smarters — con chat social
XMPP y una plantilla que se ha reempaquetado decenas de veces.

Y hay **dos productos**, no uno:

| | Generación A — APK | Generación B — PWA |
|---|---|---|
| Package / host | `com.sneig.livedrama` | `web.dramalive.cc` |
| Versión | 13.0.3 **(187)**, compilado ago 2025 | 13.0.3 **(241)**, compilado 2026-10-01 |
| Tecnología | **Kotlin/Java nativo** · 8 DEX · 30,5 MB | **Flutter** · `main.dart.js` 4,36 MB |
| Backend | `*.eastgoessouth.online` — **HTTP plano** | `main.fastconnections.online` — HTTPS |
| Ads | **15 redes** integradas (apagadas por flag remoto) | ninguna visible |
| Chat | Smack (XMPP completo, MUC) | `flutter_chat_ui` |
| Cripto propia | ✗ | ✓ `pointycastle` |

Mismo `versionName`, distinto build y **distinto backend**: la web es la reescritura moderna,
el APK nativo sigue vivo para la base instalada. Ver [`docs/02-ARQUITECTURA.md`](docs/02-ARQUITECTURA.md).

### Lo que se encontró

- **Config remota embebida en claro en `classes.dex`** (offset ≈ 7.587.537, 3.391 B) con el
  mapa completo de servidores: `main` / `live` / `shows` / `sport` / `chat` / `log` /
  `redirect` `.eastgoessouth.online`, más `file.twoapistack.work`, `xmpp_ip`, cuatro
  servidores de failover y una lista de **25 paquetes prohibidos**.
- **Credenciales del colector de crashes en el binario** (`crash_reporting_login` /
  `crash_reporting_password` → `crash2.semprotech.online:8080`). Estáticas, compartidas por
  todas las instalaciones, y el APK se distribuye públicamente. → **F-01**
- **Todo el backend en HTTP plano**, y las credenciales del panel IPTV del usuario viajando
  en el query string a un proxy de un tercero (`mikkm.xyz`). → **F-02**
- **Una IP literal de AWS** como servidor de respaldo, con puerto no estándar y failover
  automático: si esa IP se libera, todas las instalaciones enviarán su tráfico a otro
  cliente de AWS. → **F-03**
- **Plantilla white-label**: `banned_apps` lista 25 clones (`dramalive2022.app`,
  `yallashootelive`, `qata22022rfifa2022`, `shabaktytv`…) → el control de canal se hace
  desde el cliente. → **F-09**
- **15 SDKs publicitarios** (AppLovin MAX, ironSource, Unity, Vungle, Tapjoy, StartApp,
  InMobi, Mintegral, Pangle, Maticoo, Bigo, Yandex, myTarget, AppNext, Chartboost, orquestados
  por TopOn) ocupando la mayor parte de los 30,5 MB… y **todos desactivados** por config
  remota (`"nactive"`, sic). Se encienden sin pasar por Play Store. → **F-10**
- **7 actividades propias frente a 102 en total.** Toda la app son 7 pantallas.

Diez hallazgos detallados, con impacto y remediación, en
[`docs/07-HALLAZGOS-SEGURIDAD.md`](docs/07-HALLAZGOS-SEGURIDAD.md).

### Las 4 fuentes de contenido

```
XTREAM   host + usuario + contraseña  → panel Xtream Codes (contrato player_api.php)
M3U      una URL                      → #EXTINF / tvg-id / group-title / #EXTVLCOPT
FG       código + contraseña          → fgcode.org (APK) / fgcode.store (web)
GITHUB   URL de un repo público       → reescrita a raw.githubusercontent.com
```

La app **no aloja contenido**: lo aporta el usuario, o viene del catálogo del backend.
Eso define el enfoque de la réplica (§4). Detalle en
[`docs/04-MODELO-FUENTES.md`](docs/04-MODELO-FUENTES.md).

---

## 2. Estructura

```
dramalive-analysis/
├── README.md
├── docs/
│   ├── 00-LEGAL-Y-ALCANCE.md      alcance, riesgos legales, reglas duras del repo
│   ├── 01-RECON-WEB.md            recon del build web público (main.dart.js)
│   ├── 02-ARQUITECTURA.md         las dos generaciones, topología de backend, flujos
│   ├── 03-STACK-DEPENDENCIAS.md   cada SDK detectado y su evidencia
│   ├── 04-MODELO-FUENTES.md       Xtream / M3U / FG / GitHub, con el código original
│   ├── 05-API.md                  contrato implementado por backend/
│   ├── 06-FLUJO-REA.md            cómo continuar el análisis con REA
│   └── 07-HALLAZGOS-SEGURIDAD.md  F-01 … F-10, con impacto y remediación
├── analysis/
│   ├── scripts/
│   │   ├── fetch_web_artifacts.sh   descarga el build web público (GET anónimos)
│   │   ├── extract_endpoints.py     mina URLs/dominios/rutas de JS o DEX
│   │   ├── apk_triage.sh            identidad + manifiesto + firma + config embebida
│   │   └── sanitize.sh              bloquea commits que filtren secretos
│   ├── rea/
│   │   ├── REA-TASK.md              tarea completa para pegar en REA
│   │   └── rea.config.json          objetivos, restricciones y formato de salida
│   └── evidence/
│       └── embedded-remote-config.REDACTED.json   ← la config embebida, saneada
├── backend/                         API de referencia (Node ≥18, cero dependencias)
│   ├── src/index.js                 routing, CORS, rate limit
│   ├── src/routes/                  player_api.js · hls.js · discovery.js
│   ├── src/services/                catalog.js · hls.js (sintéticos + media real local)
│   ├── src/data/catalog.json        catálogo con contenido libre (Blender Foundation)
│   └── test.sh                      suite de contrato, ~60 aserciones
├── client/                          réplica Flutter (Android + web)
│   ├── pubspec.yaml                 10 dependencias (vs. 15 SDKs de ads en el original)
│   ├── lib/core/                    env · theme · router
│   ├── lib/data/                    api_client · models · providers · repositories
│   ├── lib/features/                splash · home · live · player · playlist · profile · settings
│   └── web/index.html               cliente web standalone para probar el contrato
├── Makefile
├── push.sh
└── LICENSE
```

`artifacts/` (el APK, `main.dart.js`, lo descomprimido) está en `.gitignore`: son binarios
de terceros, reproducibles con los scripts.

---

## 3. Arranque rápido

```bash
make help                # todo lo que hay

# 1. backend de referencia (contrato Xtream player_api.php + HLS sintético)
make backend             # → http://localhost:8080

# 2. probarlo
make test                # 98 aserciones sobre forma, tipos y cabeceras
curl -s 'localhost:8080/player_api.php?username=demo&password=demo&action=get_live_streams'

# 3. cliente web (backend + UI juntos, proxy en /backend)
make client-web          # → http://localhost:5173/client/web/
#    Ahí, el canal 9001 «Canal de prueba REAL» se REPRODUCE de verdad: barras
#    SMPTE + tono codificados en H.264/AAC por este propio repo (ffmpeg),
#    servidos como HLS y reproducidos con hls.js + MSE. Los canales 1001-1005
#    siguen siendo sintéticos (sin imagen) a propósito, para ejercitar el
#    pipeline sin redistribuir contenido de nadie.

# 4. cliente Flutter
cd client && flutter pub get && flutter run -d chrome

# 5. reproducir el análisis
make fetch-web                          # build web público → artifacts/raw/
make triage APK=artifacts/apk/x.apk     # triage → analysis/evidence/apk-x/
make deps-analysis                      # instala androguard
```

---

## 4. Enfoque de la réplica (y por qué es así)

La réplica **no** es un scraper del servicio comercial. Es un reproductor completo con la
misma arquitectura, que acepta **las fuentes que tú aportes**:

1. **`mock`** — el backend de este repo. Desarrolla y prueba la app entera sin tocar
   infraestructura ajena. Catálogo con contenido libre (Blender Foundation, CC-BY).
2. **`xtream`** — cualquier panel Xtream Codes del que **tú tengas credenciales**, hablando
   **directo** con él. Se implementa el contrato estándar `player_api.php`.
3. **`m3u`** — cualquier URL M3U/M3U8 tuya o con licencia.
4. **`github`** — playlist en un repo o gist público.

Y reproduce las 7 pantallas de la app original, el reproductor, el filtrado por grupo, la
búsqueda, la EPG y el aviso de tráfico sin cifrar.

**Diferencias deliberadas con el original:**

| Drama Live | Réplica |
|---|---|
| Credenciales del panel → query string a `mikkm.xyz` | → solo al panel del usuario, por `Authorization: Basic` |
| HTTP plano en todo el backend | HTTPS por defecto; HTTP exige activarlo a mano y muestra aviso permanente |
| 15 SDKs publicitarios + 4 de analítica + ACRA | ninguno |
| Config remota que fija los flags desde el servidor | Ajustes locales, visibles y editables |
| Nombre de fuente por defecto `"shai"`, separador `---` | nombre obligatorio validado |
| Toggle "aceptar SSL inválido" | no existe |
| 30,5 MB | ~10 dependencias |

**Lo que no se implementa y no se implementará aquí:**

- ❌ Usar `eastgoessouth.online`, `fastconnections.online`, `mikkm.xyz` o `fgcode.store` como fuente de contenido.
- ❌ Extraer, cachear, proxear o redistribuir streams, EPG o catálogo de terceros.
- ❌ Eludir autenticación, firmas de petición, licencias, DRM, rate limits o geobloqueo.
- ❌ Copiar branding, iconos, logotipo ni textos localizados de Drama Live.
- ❌ Usar las credenciales embebidas encontradas (F-01) para nada.

Si tu objetivo es otro — auditar la seguridad de **tu propia** app, o migrar **tu propio**
catálogo — dilo y se ajusta el alcance.

---

## 5. Ética y divulgación

- El análisis usó **solo** material servido públicamente y sin autenticación (el build web)
  y el APK facilitado por el propietario de este repo. Un puñado de `GET` de lectura: sin
  fuzzing, sin fuerza bruta, sin explotación, sin carga.
- **No se ejecutó la app**, ni en emulador ni en dispositivo.
- **No se contactó ningún endpoint** del backend una vez identificado: sondear a ciegas un
  servicio de terceros es escaneo no autorizado. Se paró deliberadamente ahí.
- Las **credenciales encontradas están redactadas** en todo lo versionado. Publicarlas
  facilitaría el abuso; el hallazgo se documenta sin el dato que permite explotarlo.
- Los hallazgos F-01 a F-05 se enviarán a `support@dramalive.org` (canal que la propia app
  publica en su config) **antes** de darles difusión, con plazo de 90 días.
- Si encuentras una vulnerabilidad explotable, sigue el mismo camino: describir mecanismo e
  impacto, sin PoC funcional, y divulgar responsablemente.

---

## 6. Estado

- [x] Recon del build web público — URLs, rutas, modelo de fuentes, stack, paleta
- [x] Triage del APK — manifiesto, firma, permisos, 102 componentes, inventario de SDKs
- [x] Extracción de la config remota embebida (11 hosts, failover, `banned_apps`, ads, flags)
- [x] 10 hallazgos de seguridad documentados con impacto y remediación
- [x] Backend de referencia Xtream-compatible + HLS sintético + suite de contrato (98 aserciones, en verde)
- [x] Canal de prueba **REAL** (id 9001) que se reproduce de verdad en el navegador
      (HLS → hls.js → MSE), con barras SMPTE + tono generados por este repo — sin
      contenido de terceros
- [x] Cliente réplica Flutter: 7 pantallas, 4 fuentes, reproductor, ajustes, aviso de cleartext
- [x] Cliente web standalone para probar el contrato sin toolchain de Flutter
- [x] Tarea y configuración listas para REA
- [ ] **Análisis profundo con REA** — paths concretos del backend, esquema JSON, remote config,
      `banned_apps`, autoupdate, XMPP, cripto → [`analysis/rea/REA-TASK.md`](analysis/rea/REA-TASK.md)
- [ ] Chat XMPP en la réplica (módulo pendiente)
- [ ] EPG XMLTV y timeshift/catch-up
- [ ] VOD y series en la réplica (pantallas esbozadas)
- [ ] Cifrar credenciales en reposo con Keystore/Keychain
- [ ] Divulgación responsable a `support@dramalive.org`

## 7. Licencia

Código y textos propios: **MIT** (`LICENSE`), con una nota explícita sobre lo que **no**
cubre. Los artefactos de terceros no se versionan.
