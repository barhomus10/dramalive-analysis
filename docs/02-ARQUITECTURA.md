# 02 — Arquitectura

Reconstruida a partir del build web público y de la config embebida del APK.
Las dos plataformas **no comparten código**: son dos generaciones del mismo producto.

## 1. Las dos caras del producto

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Drama Live — producto                                                     │
│                                                                            │
│  ┌────────────────────────────┐      ┌──────────────────────────────────┐ │
│  │  GENERACIÓN A · Android    │      │  GENERACIÓN B · Web / PWA        │ │
│  │  com.sneig.livedrama       │      │  web.dramalive.cc                │ │
│  │  v13.0.3 (187)             │      │  v13.0.3 (241)                   │ │
│  │  compilado ≈ ago 2025      │      │  compilado 2026-10-01            │ │
│  │                            │      │                                    │ │
│  │  Kotlin/Java nativo        │      │  Flutter (Dart → JS + APK)         │ │
│  │  8 DEX · 30,5 MB           │      │  main.dart.js · 4,36 MB            │ │
│  │  15 redes de ads           │      │  sin ads visibles                  │ │
│  │  backend: eastgoessouth    │      │  backend: fastconnections.online   │ │
│  │  (HTTP plano)              │      │  (HTTPS, origen Go)                │ │
│  └────────────────────────────┘      └──────────────────────────────────┘ │
│              │                                      │                      │
│              └──────────── ambos ────────────────────┘                      │
│                     XMPP para chat · Xtream/M3U/FG para contenido           │
└──────────────────────────────────────────────────────────────────────────┘
```

Evidencia del desfase: mismo `versionName` (13.0.3) pero `versionCode`/`buildNumber` distinto
(187 vs 241) y **dominios de backend distintos**. La web es la reescritura moderna; el APK
nativo sigue vivo y sirviendo a la base instalada.

> Consecuencia práctica: **analizar solo uno de los dos da una imagen incompleta.** Los
> endpoints de la generación A no sirven para la B y viceversa.

## 2. Topología de backend (generación A — APK)

Un dominio por servicio. Todo en `eastgoessouth.online`, todo HTTP:

```
                        ┌─────────────────────────────┐
                        │  main.eastgoessouth.online  │  API principal
                        │  /api/live/livedrama/v13.0.0│  catálogo, config, auth
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  live.eastgoessouth.online  │  mismo path /api/live/livedrama/v13.0.0
                        │                             │  → dedicado a streams en directo
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  shows.eastgoessouth.online │  /search/v3/   búsqueda "smart"
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  sport.eastgoessouth.online │  /sport/       vertical deportivo
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  chat.eastgoessouth.online  │  /chat/api/    HTTP API del chat
                        │  fire.eastgoessouth.online  │  XMPP (Smack)  socket del chat
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  redirect.eastgoessouth     │  /redirect/    acortador / deeplinks
                        │  .online                    │                (y probablemente afiliación)
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  log.eastgoessouth.online   │  /api/live/livedrama/v9.0.0
                        │                             │  ← ¡API en v9! telemetría no versionada
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  file.twoapistack.work      │  estáticos: logos, imágenes sociales
                        └─────────────────────────────┘
                        ┌─────────────────────────────┐
                        │  crash2.semprotech.online   │  :8080/report  ACRA  ⚠ F-01
                        │  dataflowstation.net        │  distribución de APKs
                        │  download.twoapistack.work  │  CDN de descarga
                        └─────────────────────────────┘

  Respaldo (failover, en orden):
      main.backendcoreapi.com  →  main.swiftapi.org  →  <IP AWS>:8787  →  dramalive.app:8787
                                                              ⚠ F-03
```

Notas de diseño:

- **Partición por subdominio** en vez de por path. Permite escalar y cachear cada servicio
  por separado, y poner CDN/WAF solo donde interesa. Pero multiplica los certificados TLS
  necesarios — lo que probablemente explique que no haya TLS (F-02).
- **El path es idéntico en todos** (`/api/live/livedrama/v<VER>/`): el mismo handler
  desplegado en varios hosts. La versión va **en la URL**, no en una cabecera.
- **`log_url` está en `v9.0.0`** mientras todo lo demás va en `v13.0.0`. La telemetría no se
  versiona al ritmo del producto → o es retrocompatible a la fuerza, o está abandonada.
- `file.twoapistack.work` es el **único** host no `eastgoessouth` en el camino crítico, y es
  el que sirve los APK. Es el punto único de fallo de la distribución.

## 3. Topología de backend (generación B — web)

```
web.dramalive.cc          Cloudflare → Apache/Bitnami (estáticos de la PWA)
                          SPA fallback: cualquier ruta → index.html con 200
main.fastconnections.online/api/live/livedrama/v13.0.0/
                          origen Go net/http (404 con la página por defecto de Go)
                          → los paths concretos no existen en la raíz: se construyen en runtime
images.weserv.nl          proxy de imágenes + conversión a WebP
fgcode.store              servicio de playlists por código
mikkm.xyz/android/androidApi.php   proxy de activación Xtream (tercero)  ⚠ F-02
raw.githubusercontent.com playlists alojadas en repos públicos de GitHub
```

## 4. Modelo de fuentes de contenido

La app **no aloja contenido**: lo resuelve desde una fuente que el usuario activa.
Cuatro mecanismos, unificados en una sola abstracción interna:

```
                 ┌──────────────────────────────────────────────┐
                 │           SourceResolver (app)               │
                 └──────────────────────────────────────────────┘
                    ▲          ▲            ▲            ▲
     ACTIVATE_      │          │            │            │
       XTREAM ──────┘          │            │            │
       M3U   ─────────────────┘            │            │
       FG    ──────────────────────────────┘            │
       GitHub ─────────────────────────────────────────┘

  XTREAM  host + username + password
          → (gen A) http://mikkm.xyz/android/androidApi.php?url=…&mode=live&username=…&password=…
          → emite "ACTIVATE_XTREAM" con  <url>---<name>   (name por defecto: "shai")
          → contrato estándar Xtream Codes: player_api.php, ver catálogo abajo

  M3U     URL arbitraria
          → normalización: si no lleva esquema, se añade "https://"
          → se recorta el "/" final y se vuelve a añadir (para componer paths)
          → parseo #EXTINF / #EXTGRP / tvg-id / tvg-logo / group-title

  FG      código + password  →  fgcode.org (gen A) / fgcode.store (gen B)
          → playlist gestionada por un tercero; la app solo la consume
          → flag global "fg_active": true

  GitHub  github.com/<owner>/<repo>/(blob|raw)/<path>
          → reescrito a raw.githubusercontent.com/<owner>/<repo>/<path>
```

El nombre por defecto `"shai"` y el separador `"---"` son detalles de implementación que
conviene no replicar (frágiles). Ver `docs/04-MODELO-FUENTES.md`.

## 5. Arquitectura de cliente (generación A)

```
MyApplication
   ├── inicialización de 15 SDKs publicitarios vía ContentProvider (androidx.startup)
   ├── ACRA  → crash2.semprotech.online:8080
   ├── Firebase (Messaging + Analytics + Installations)
   ├── AppMetrica (Yandex)
   └── Picasso, Room, WorkManager, DataStore

StartActivity (launcher, también LEANBACK_LAUNCHER → Android TV)
   │   lee la config remota embebida + la refresca
   ├── IntroActivity        onboarding / selección de fuente
   └── HomeActivity         shell principal
        ├── LiveActivity         TV en directo
        ├── MultyPlayerActivity  reproductor multi-ventana  [sic]
        ├── FullScreenActivity   reproductor a pantalla completa
        └── ProfileActivity      cuenta

Servicios:
   ConnectXmpp        conexión persistente XMPP (Smack) para el chat
   MyFcmListenerService  push notifications
   SwipOutService     servicio foreground asociado al swipe-to-dismiss / MediaSession

ActionReceiver       media buttons / notificación de reproducción
```

Reproductor: **ExoPlayer/Media3** (literales `exoplayer.dev`, `updateDrmInitData`,
`LoadControl`, `TrackSelector`, `DefaultMediaSource`, `dashif.org`, `aomedia.org` → soporta
HLS **y** DASH, y tiene hooks de DRM aunque la config no lo active).

## 6. Arquitectura de cliente (generación B)

```
flutter_bootstrap.js  →  _flutter.buildConfig  →  main.dart.js (CanvasKit)
   │
   └─ main()
        env = aRy(baseUrl, "13.0.3", "241", true, "web")     ← entorno
        ├─ detección de plataforma desde userAgent → "web"|"android"|"ios"|"windows"|"macos"|"linux"
        ├─ remote config (mapa) con kill-switches por plataforma, p.ej. "iosImages"
        ├─ ApiClient(baseUrl, env)
        ├─ providers (patrón provider/riverpod: muchos A.cQ(...) = listeners)
        └─ router: /auth /app /live /shows /episodes /sport /source
                   /profile /settings /chat-friends /our_apps /video_player
                   /navigate_screen /page
```

El splash lo pinta **el HTML**, no Flutter: un `div#loading-screen` con CSS propio que se
oculta al recibir el evento `flutter-first-frame` (con fallback de 10 s). Técnica estándar
para evitar el pantallazo en blanco del arranque de Flutter Web.

## 7. Cómo se mapea esto a la réplica de este repo

```
 backend/  (Node, sin dependencias)
    implementa el contrato Xtream Codes estándar + un catálogo propio de ejemplo
    → sustituye a  main.eastgoessouth.online  Y a  mikkm.xyz
    → TODO en HTTP local, sin credenciales de nadie

 client/   (Flutter)
    SourceResolver con 4 providers: mock | xtream | m3u | fg
    ExoPlayer-equivalente = video_player + media_kit
    Sin SDKs publicitarios. Sin ACRA. Sin telemetría.
    → reproduce la ARQUITECTURA, no el contenido ni el branding
```

Ver `docs/05-API.md` para el contrato que implementa `backend/`.
