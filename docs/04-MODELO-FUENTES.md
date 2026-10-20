# 04 — Modelo de fuentes de contenido

Drama Live es un **reproductor**, no un editor. El contenido lo aporta una *fuente* que el
usuario activa. Este documento describe los cuatro mecanismos detectados y cómo se implementan
en la réplica.

---

## 1. Las cuatro fuentes

```
┌────────────┬──────────────────────────────────────────────────────────────┐
│ Fuente     │ Entrada del usuario                                            │
├────────────┼──────────────────────────────────────────────────────────────┤
│ XTREAM     │ host del panel + username + password                           │
│ M3U        │ una URL                                                        │
│ FG         │ código + password                                              │
│ GITHUB     │ URL de un archivo en un repo público                           │
└────────────┴──────────────────────────────────────────────────────────────┘
       ↓  todas se normalizan a
   Playlist { categories: [ Category { channels: [ Channel ] } ], epg? }
```

El evento interno de activación es una cadena con prefijo:

```
ACTIVATE_XTREAM   ACTIVATE_M3U   ACTIVATE_FG
```

## 2. XTREAM CODES

### 2.1 Lo que hace Drama Live (generación A y B, idéntico)

```js
// reconstruido desde main.dart.js
function activateXtream(host, username, password, code) {
  if (!host?.trim()) return { ok: false, error: "empty url" };
  if (!/^https?:\/\//i.test(host)) host = "https://" + host;   // https por defecto
  if (host.endsWith("/")) host = host.slice(0, -1);
  const url = "https://mikkm.xyz/android/androidApi.php"
            + "?url="      + encodeURIComponent(host + "/")
            + "&mode=live"
            + "&username=" + encodeURIComponent(username)
            + "&password=" + encodeURIComponent(password);
  const name = code?.trim() || "shai";                          // ← default hardcodeado
  emit("ACTIVATE_XTREAM", url + "---" + name);
}
```

Cuatro problemas, en orden de gravedad:

1. **Las credenciales del usuario viajan en el query string a un dominio de un tercero**
   (`mikkm.xyz`). Quedan en: logs de Cloudflare, logs de Apache, logs del propio `mikkm.xyz`,
   historial del WebView, y `Referer` de cualquier recurso que se cargue después. Ver F-02.
2. **HTTP plano** → además cualquiera en la red las lee.
3. `mode=live` fijo → VOD y series deben ir por otro `mode` que no se ve en el bundle.
4. Separador `"---"` y nombre por defecto `"shai"`: si el nombre de la fuente contiene `---`
   el parseo se rompe; y `"shai"` es un valor mágico sin documentar.

### 2.2 El contrato estándar (lo que implementa este repo)

Xtream Codes es un formato **de facto**, estable desde hace una década. La réplica habla
directo con el panel — sin proxy intermedio:

```
BASE = https://<panel-del-usuario>
Auth = { username, password }          ← los aporta el usuario, se guardan en el device

GET  BASE/player_api.php?username=U&password=P
     → { user_info: {...}, server_info: {...} }

GET  BASE/player_api.php?username=U&password=P&action=get_live_categories
     → [ { category_id, category_name, parent_id } ]

GET  BASE/player_api.php?username=U&password=P&action=get_live_streams[&category_id=N]
     → [ { stream_id, name, stream_icon, epg_channel_id, category_id, num, ... } ]

GET  BASE/player_api.php?username=U&password=P&action=get_vod_streams
GET  BASE/player_api.php?username=U&password=P&action=get_series
GET  BASE/player_api.php?username=U&password=P&action=get_series_info&series_id=N
GET  BASE/player_api.php?username=U&password=P&action=get_short_epg&stream_id=N
GET  BASE/player_api.php?username=U&password=P&action=get_live_streams&category_id=N

Stream:  BASE/live/U/P/<stream_id>.m3u8     (o .ts)
VOD:     BASE/movie/U/P/<stream_id>.<ext>
Series:  BASE/series/U/P/<stream_id>.<ext>
```

Contrato completo y respuestas de ejemplo: **`docs/05-API.md`** (es lo que sirve `backend/`).

### 2.3 Diferencias con Drama Live que la réplica introduce a propósito

| Drama Live | Réplica |
|---|---|
| Credenciales → query string a `mikkm.xyz` | Credenciales → solo al panel del usuario, en POST cuando el panel lo admite |
| HTTP | HTTPS exigido por defecto; HTTP solo con confirmación explícita del usuario y aviso en pantalla |
| `"shai"` como nombre por defecto | nombre obligatorio, validado, sin separadores mágicos |
| `mode=live` fijo | live / vod / series como parámetro |
| SSL configurable por UI (`xtream_accept_ssl_checkBox`) | validación de certificado siempre activa; excepción solo por perfil de debug explícito |

> Los literales `xtream_accept_ssl_checkBox`, `xtream_auto_refresh_checkBox`,
> `xtream_url_status_TextView`, `xtream_agent_status_TextView` y `xtream_logout_FrameLayout`
> del APK confirman que hay una pantalla de ajustes Xtream con: aceptar SSL inválido,
> autorefresco, estado de la URL, estado del "agente" y logout. La réplica reproduce la
> pantalla **menos** el toggle de SSL inválido.

## 3. M3U / M3U8

Formato abierto. La normalización que aplica Drama Live:

```js
url = url.trim();
if (!url) return { ok: false, error: "empty url" };
if (!/^https?:\/\//i.test(url)) url = "https://" + url;   // asume https
if (url.endsWith("/")) url = url.slice(0, -1);
url = url + "/";                                           // deja exactamente un "/" final
```

Gramática soportada (parser de la réplica en `client/lib/data/providers/m3u_source.dart`):

```
#EXTM3U
#EXTINF:-1 tvg-id="canal.es" tvg-name="Canal" tvg-logo="https://…/logo.png" group-title="News",Canal HD
https://…/stream.m3u8
#EXTGRP:News
```

Reglas:
- `-1` en `#EXTINF` = duración desconocida (directo). Un valor > 0 = VOD con duración.
- `tvg-id` enlaza con el EPG (XMLTV). `group-title` clasifica; `#EXTGRP` es la forma antigua.
- El nombre visible va **después** de la coma.
- Líneas que no empiezan por `#` ni por `http` se ignoran (comentarios `#` sueltos).
- `#EXTVLCOPT:http-user-agent=…` y `#EXTVLCOPT:http-referrer=…` se respetan (cabeceras por
  entrada). La réplica las aplica; Drama Live probablemente también (ExoPlayer lo permite).

## 4. FG CODE

Servicio de terceros: **`fgcode.org`** (generación A) / **`fgcode.store`** (generación B).

Según el texto de ayuda **incluido en el propio bundle** (localizado a EN/FR/AR):

> "FG code is a free service that allows you to organize and group your content links in one
> playlist represented by a simple code, and then watch your content by simply inputting the
> FG Code in any supported player.
> 1. Go to the website 'https://fgcode.store/'
> 2. Click on 'Create FG Code' and choose a code and a password.
> 3. Start adding your content links.
> 4. Now you can watch your content on DramaLive by entering your code in the FG Code field.
> 5. Every time you add or remove content from your playlist, the changes will appear
>    automatically on the app."
>
> "FG code is a content management service only and does not include any content, broadcast
> or rebroadcast."

Modelo: **código + password** → playlist. Es conceptualmente un Xtream simplificado donde el
"host" es fijo y solo cambia el código. Flag global en la config: `"fg_active": true`.

Pendiente de confirmar con REA: el path exacto (`fgcode.org/<code>`? `?code=&pass=`?) y el
formato de respuesta (¿devuelve M3U? ¿JSON?).

> La réplica implementa el provider con el path **documentado públicamente** por `fgcode.store`
> y lo deja deshabilitado por defecto (`FG_ENABLED=false`), porque depender de un tercero sin
> contrato publicado es frágil. Aporta tu propia M3U en su lugar.

## 5. GITHUB

```js
// regex literal en main.dart.js
^https?://(?:www\.)?github\.com\/([^/]+)\/([^/]+)\/(?:blob|raw)\/(.+)$
   →  https://raw.githubusercontent.com/$1/$2/$3
```

Convierte un enlace "copiable desde el navegador" en un enlace descargable. Después se trata
como M3U. Es un mecanismo legítimo y elegante para distribuir playlists públicas versionadas.

La réplica lo implementa tal cual (`client/lib/data/providers/github_source.dart`) ampliándolo:

- acepta también `gist.github.com/<user>/<id>` → `gist.githubusercontent.com/<user>/<id>/raw`
  (los literales del APK contienen `gist.github.com`, así que la generación A ya lo soporta);
- permite fijar un `ref` (`/blob/<branch>/…`) y lo preserva.

## 6. Backend propio (catálogo "de la casa")

Independiente de la fuente del usuario, la app consulta su backend para:

- config remota (la que está embebida en el APK como valor por defecto),
- `our_apps` / cross-promo (los 25 paquetes de `banned_apps` son la otra cara de esto),
- `redirect_url` (deeplinks/afiliación),
- `smart_search_url` (`/search/v3/` — búsqueda federada sobre varias fuentes),
- `sport_server_url` (vertical deportivo),
- `log_url` (telemetría, en `v9.0.0`).

**La réplica no consume ninguno.** `backend/` reimplementa solo el contrato Xtream estándar
más un catálogo de ejemplo con contenido libre, para que la app sea usable y testeable sin
tocar infraestructura ajena. Ver `docs/00-LEGAL-Y-ALCANCE.md` §4.
