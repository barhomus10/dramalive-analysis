# 01 — Reconocimiento del build web público

**Objetivo:** `https://web.dramalive.cc/`
**Fecha:** 2026-10-20
**Método:** peticiones `GET` anónimas (sin auth, sin rate, ~15 requests en total).
**Reproducible con:** `analysis/scripts/fetch_web_artifacts.sh` + `analysis/scripts/extract_endpoints.py`

---

## 1. Identidad del build

`https://web.dramalive.cc/version.json`

```json
{
  "version": "13.0.3",
  "buildNumber": "241",
  "buildTimestamp": "2026-10-01T13:31:20Z",
  "cacheVersion": "13.0.3.241"
}
```

`index.html` confirma que **el mismo código base alimenta web y Android**:

```html
<!-- Populated at runtime from the APP_VERSION constant
     (which deploy.sh keeps in sync with app_version.dart) -->
<div id="loading-version"></div>
...
<script src="flutter_bootstrap.js?v=13.0.3.241" async></script>
```

> **Conclusión útil:** existe `lib/config/app_version.dart` en el proyecto original y un
> `deploy.sh` que sincroniza la versión entre el APK y la PWA. Cuando llegue el APK, la
> comparación `app_version.dart` ↔ `version.json` permite saber si la PWA y el APK van en
> la misma release o si hay *skew* (muy común y fuente de bugs).

## 2. Cabeceras del servidor

```
server: cloudflare
cf-cache-status: DYNAMIC
cache-control: public, max-age=0, must-revalidate
access-control-allow-origin: *
x-content-type-options: nosniff
referrer-policy: strict-origin-when-cross-origin
HTTP/2, alt-svc h3=":443"
```

El HTML incluye, comentada, la configuración **real** de Apache del servidor de origen:

```apache
# /opt/bitnami/apache/htdocs/.htaccess
<IfModule mod_headers.c>
  <FilesMatch "^(index\.html|flutter_bootstrap\.js|flutter_service_worker\.js|version\.json|manifest\.json)$">
    Header set Cache-Control "no-cache, must-revalidate"
  </FilesMatch>
  <FilesMatch "^main\.dart\.js$">
    Header set Cache-Control "public, max-age=31536000"
  </FilesMatch>
</IfModule>
```

Hallazgos de infra:

| Dato | Valor | Comentario |
|---|---|---|
| CDN/WAF | Cloudflare | Ray `…-SEA` en nuestras pruebas → PoP Seattle |
| Origen | **Apache sobre imagen Bitnami** (`/opt/bitnami/apache/htdocs`) | Stack LAMP clásico |
| SPA fallback | Cualquier ruta inexistente devuelve `index.html` con **200** | `robots.txt`, `sitemap.xml`, `sw.js` y `asset-manifest.json` dan 200 → **falsos positivos**, no existen |
| CORS | `access-control-allow-origin: *` | La API web es consumible cross-origin |

> ⚠️ **Cuidado metodológico:** el SPA fallback hace que *todo* parezca existir. Cualquier
> sonda de endpoints sobre `web.dramalive.cc` debe validarse por **tamaño de respuesta y
> content-type**, no por código HTTP. `main.dart.js` sí existe: 4.364.382 bytes, JS real.

## 3. Artefactos descargados

| Artefacto | Bytes | ¿En git? |
|---|---|---|
| `index.html` | 21.383 | no (derivable) |
| `main.dart.js` | 4.364.382 | **no** (`.gitignore`, binario de terceros) |
| `flutter_bootstrap.js` | 8.135 | no |
| `flutter.js` (inlineado en `index.html`) | 7.775 | no |
| `version.json` | 126 | no |
| `manifest.json` | 907 | no |
| `assets/AssetManifest.json` | 4.795 | no |
| `assets/AssetManifest.bin.json` | 7.622 | no |

Regenera todo con `make fetch-web`.

## 4. PWA

`manifest.json`:

```json
{
  "name": "Drama Live", "short_name": "Drama Live",
  "start_url": ".", "display": "standalone",
  "background_color": "#ffffff", "theme_color": "#ffffff",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [ "icons/Icon-192.png", "icons/Icon-512.png",
             "icons/Icon-maskable-192.png", "icons/Icon-maskable-512.png" ]
}
```

Notas:
- `prefer_related_applications: false` → **no** redirige a Play Store; quiere instalación como PWA.
- `theme_color: #ffffff` choca con el splash, que es oscuro (`#1a1a2e → #16213e → #0f3460`,
  acento `#e94560`). Inconsistencia cosmética real del producto.
- **No hay `service-worker` registrado en `index.html`** pese a que el `.htaccess` menciona
  `flutter_service_worker.js`. La caché offline probablemente se gestiona desde Dart.

Paleta extraída del splash (útil para la réplica):

```
fondo    : linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)
acento   : #e94560
texto    : #ffffff / rgba(255,255,255,.6)
```

## 5. URLs externas encontradas en `main.dart.js`

Salida de `analysis/scripts/extract_endpoints.py` (filtrada: se descartan URLs de
documentación de Flutter y namespaces XML de XMPP).

| URL | Rol |
|---|---|
| `https://main.fastconnections.online/api/live/livedrama/v13.0.0/` | **Backend propio** de la app. Constructor `aRy(baseUrl, "13.0.3", "241", true, "web")` |
| `https://mikkm.xyz/android/androidApi.php?url=…&mode=live&username=…&password=…` | Proxy de activación **Xtream Codes** de un tercero (`mikkm.xyz`) |
| `https://fgcode.store/` | Servicio de playlists por código ("FG Code") |
| `https://raw.githubusercontent.com/<owner>/<repo>/<path>` | Reescritura de URLs GitHub `blob`/`raw` → raw |
| `https://images.weserv.nl/?url=<enc>&w=<px>&output=webp` | Proxy/reescalado de imágenes |
| `http://dramalive.tv/privacy/index.html` | Política de privacidad (¡HTTP, no HTTPS!) |
| `http://jabber.org/protocol/{disco#info,disco#items,muc,muc#owner,muc#roomconfig}` | Namespaces XMPP → **chat con salas MUC** |
| `https://wa.me/?text=`, `https://t.me/share/url?url=`, `https://twitter.com/intent/tweet?text=` | Compartir nativo |

### 5.1 El backend propio responde 404 a todo

```
GET https://main.fastconnections.online/api/live/livedrama/v13.0.0/            → 404 text/html 573B
GET …/index.php  …/channels  …/settings  …/config  …/home  …/categories  …/our_apps → 404 (573B)
```

404 de **Go net/http** (`"404 Page Not Found"` con el CSS característico), **no** de Apache.
Dos conclusiones:

1. El backend de la app **no** es el mismo host que la web (Apache/Bitnami). Es un servicio Go
   (o un reverse proxy Go) detrás de otra capa.
2. Los endpoints concretos **no son literales** en el bundle: se construyen en runtime
   (`A.bKU(m.gaYE(), m.gaYG(), m.gaYI())` sobre el objeto de entorno). No aparecen como
   cadenas `/api/…` en el JS.

> **Esto es exactamente el trabajo de REA sobre el APK**: los literales de ruta viven en
> `libapp.so` (código AOT de Dart), no en el bundle web. Ver `docs/06-FLUJO-REA.md`.
> **No** se siguió sondeando el backend: sin el mapa de rutas, sondear a ciegas es ruido y
> podría interpretarse como escaneo no autorizado. Se detuvo deliberadamente aquí.

### 5.2 Construcción de la URL Xtream

Código desminificado a partir del bundle:

```js
// entrada: i = host del panel, d = username, b = password, a = nombre ("code")
if (i.trim().length === 0) return {ok: false, error: "empty url"};
if (!/^https?:\/\//i.test(i)) i = "https://" + i;      // fuerza https por defecto
if (i.endsWith("/")) i = i.slice(0, -1);               // normaliza trailing slash
const url = "https://mikkm.xyz/android/androidApi.php?url=" + encodeURIComponent(i + "/")
          + "&mode=live"
          + "&username=" + encodeURIComponent(username)
          + "&password=" + encodeURIComponent(password);
const name = (code ?? "").trim() || "shai";            // ← default hardcodeado: "shai"
emit("ACTIVATE_XTREAM", url + "---" + name);           // separador "---"
```

Detalles de diseño que vale la pena replicar *correctamente* (y no como lo hacen ellos):

- Las credenciales del usuario viajan en el **query string** a un host de **tercero**.
  Eso las deja en logs de Cloudflare, de Apache y del propio `mikkm.xyz`. **No lo repitas.**
  La réplica de este repo habla directo con el panel Xtream (ver `docs/05-API.md`).
- `mode=live` fijo → solo directo; VOD/series deben ir por otro `mode`.
- Separador `---` entre URL y nombre: frágil si el nombre contiene `---`.

### 5.3 Reescritura GitHub → raw

```js
// regex literal en el bundle
^https?://(?:www\.)?github\.com/([^/]+)/([^/]+)/(?:blob|raw)/(.+)$
→ https://raw.githubusercontent.com/$1/$2/$3
```

Permite cargar una playlist alojada en un repo público. Útil y legítimo: se replica.

### 5.4 Proxy de imágenes

```js
function proxyImage(url, width) {
  if (!url) return url;
  if (url.startsWith("data:") || url.startsWith("assets/") || url.startsWith("https://images.weserv.nl/")) return url;
  return "https://images.weserv.nl/?url=" + encodeURIComponent(url) + "&w=" + width + "&output=webp";
}
```

Y existe un **kill-switch remoto** por plataforma:

```js
// clave "iosImages" del config remoto → "on"|"off"
// en iOS: si iosImages == "on" → NO usar proxy
```

Es decir: el backend entrega flags de feature por plataforma y la app los respeta. Hay un
sistema de **remote config** (getter `gajj()` sobre un mapa). Buscarlo en el APK es prioritario:
ahí estarán las URLs reales y los flags.

## 6. Rutas de navegación detectadas

```
/app            /auth           /live           /shows          /episodes
/sport          /source         /profile        /settings       /chat-friends
/our_apps       /video_player   /navigate_screen                /page
```

Mapa de la app inferido:

```
/auth  ──►  /app (shell)
             ├── /live            TV en directo (fuente activa)
             ├── /shows           VOD / series
             │    └── /episodes
             ├── /sport           vertical deportivo
             ├── /source          alta de fuentes (Xtream / M3U / FG / GitHub)
             ├── /chat-friends    chat XMPP (MUC)
             ├── /our_apps        cross-promo de otras apps del mismo editor
             ├── /profile         cuenta
             └── /settings        ajustes
             /video_player        reproductor (fuera del shell, fullscreen)
```

## 7. Dependencias detectadas (vía `AssetManifest.json` + literales)

Ver detalle en `docs/03-STACK-DEPENDENCIAS.md`.

## 8. Pendientes que resuelve el APK

- [ ] Rutas concretas del backend Go (`libapp.so`, sección de literales de Dart AOT).
- [ ] Esquema del **remote config** (`gajj()`): claves, tipos, defaults, frecuencia de refresco.
- [ ] Cómo se firma/autentica la petición al backend (`device_id`, token, headers).
- [ ] Uso real del stack cripto detectado (AES-CBC/CTR/GCM, RSA-OAEP, PBKDF2, HKDF, Poly1305):
      ¿ofuscación de la config? ¿cache cifrada local? ¿firma de peticiones?
- [ ] Cliente XMPP: servidor, dominio, registro anónimo vs. SASL, persistencia de MUC.
- [ ] Formato exacto de la respuesta de `mikkm.xyz` (Xtream) y de `fgcode.store` (FG).
- [ ] EPG: ¿XMLTV? ¿endpoint propio? ¿caché?
- [ ] `flutter_inappwebview`: ¿qué se carga en WebView (pagos, anuncios, `our_apps`)?
