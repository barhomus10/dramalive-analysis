# 05 — Contrato de API

Es el contrato que implementa `backend/`. Es **el estándar de facto Xtream Codes
`player_api.php`**, que es lo que Drama Live consume cuando el usuario activa una fuente
XTREAM (ver `docs/04-MODELO-FUENTES.md` §2.2).

> No es el API privada de `eastgoessouth.online` / `fastconnections.online`. Esos endpoints
> concretos **no se documentan aquí**: no se han obtenido (la config embebida da los hosts,
> no los paths) y obtenerlos sondeando a ciegas un servicio de terceros está fuera del
> alcance de este proyecto. Ver `docs/00-LEGAL-Y-ALCANCE.md` §4.1.

---

## 1. Convenciones

```
BASE = http://localhost:8080            (backend de este repo)
     = https://<tu-panel>               (un panel Xtream real tuyo)

Autenticación: query string  ?username=<u>&password=<p>
   ← así es el protocolo Xtream. Es inseguro por diseño (las credenciales acaban en logs).
     El backend de este repo acepta además  Authorization: Basic  para desarrollo local.

Content-Type de respuesta: application/json; charset=utf-8
Errores: HTTP 4xx/5xx + { "error": "<código>", "message": "<legible>" }
```

Códigos de error:

| HTTP | `error` | Cuándo |
|---|---|---|
| 401 | `auth_failed` | credenciales ausentes o inválidas |
| 400 | `bad_request` | falta un parámetro obligatorio |
| 404 | `not_found` | `stream_id` / `series_id` / `category_id` inexistente |
| 429 | `rate_limited` | superado el límite (120 req/min por credencial) |
| 500 | `internal` | fallo del backend |

## 2. Endpoints

### `GET /player_api.php`

Sin `action`: devuelve el estado de la cuenta. Es la llamada de **handshake**.

```json
{
  "user_info": {
    "username": "demo",
    "password": "demo",
    "auth": 1,
    "status": "Active",
    "exp_date": "1893456000",
    "is_trial": "0",
    "active_cons": "1",
    "max_connections": "2",
    "allowed_output_formats": ["m3u8", "ts"],
    "created_at": "1704067200"
  },
  "server_info": {
    "url": "localhost",
    "port": 8080,
    "https_port": 8443,
    "server_protocol": "http",
    "rtmp_port": 8001,
    "timezone": "America/Lima",
    "timestamp_now": 1760940000
  }
}
```

`auth` es **entero** (`1`/`0`) y `exp_date` es **string** con epoch en segundos: son rarezas
del protocolo real que muchos clientes dan por supuestas. `"Active"` y `"Expired"` son los
valores de `status`.

### `GET /player_api.php?action=get_live_categories`

```json
[
  { "category_id": "1", "category_name": "Noticias", "parent_id": 0 },
  { "category_id": "2", "category_name": "Deportes", "parent_id": 0 }
]
```

`category_id` es **string** aunque parezca numérico. `parent_id: 0` = raíz.

### `GET /player_api.php?action=get_live_streams[&category_id=1]`

```json
[
  {
    "num": 1,
    "name": "Canal de ejemplo HD",
    "stream_type": "live",
    "stream_id": 1001,
    "stream_icon": "https://…/logo.png",
    "epg_channel_id": "ejemplo.hd",
    "added": "1704067200",
    "category_id": "1",
    "custom_sid": "",
    "tv_archive": 0,
    "direct_source": "",
    "tv_archive_duration": 0
  }
]
```

Aquí `stream_id` sí es **número**. La inconsistencia con `category_id` es del protocolo
original; se respeta a propósito para que la réplica sea intercambiable con un panel real.

`tv_archive: 1` + `tv_archive_duration: <días>` habilita timeshift/catch-up.

### Otras acciones

| `action` | Parámetros | Devuelve |
|---|---|---|
| `get_vod_categories` | — | como `get_live_categories` |
| `get_vod_streams` | `category_id?` | como `get_live_streams` + `container_extension` |
| `get_series_categories` | — | como `get_live_categories` |
| `get_series` | `category_id?` | `series_id`, `name`, `cover`, `plot`, `genre`, `rating` |
| `get_series_info` | `series_id` **obligatorio** | `{ seasons: [...], episodes: { "<temporada>": [...] }, info: {...} }` |
| `get_short_epg` | `stream_id` **obligatorio**, `limit?` (def. 4) | entradas EPG del canal, **base64** en `title`/`description` |
| `get_simple_data_table` | `stream_id`, `date?` (`YYYY-MM-DD`) | `{ epg_listings: [...] }` |

`get_short_epg` codifica en base64 — otra rareza real del protocolo:

```json
{
  "epg_listings": [
    {
      "id": "9001",
      "epg_id": 1,
      "title": "QnVlbm9zIGRpYXM=",
      "description": "TWFnYXppbmUgbWF0aW5hbA==",
      "start_timestamp": "1760940000",
      "stop_timestamp": "1760947200",
      "start": "2026-10-20 06:00:00",
      "stop": "2026-10-20 08:00:00"
    }
  ]
}
```

```python
import base64; base64.b64decode("QnVlbm9zIGRpYXM=").decode()   # 'Buenos días'
```

## 3. URLs de reproducción

```
Directo :  BASE/live/<username>/<password>/<stream_id>.m3u8
VOD     :  BASE/movie/<username>/<password>/<stream_id>.<container_extension>
Serie   :  BASE/series/<username>/<password>/<stream_id>.<container_extension>
```

El backend de este repo sirve HLS en `/live/:id.m3u8` apuntando a **streams de prueba libres**
(Big Buck Bunny / Sintel, dominio público, Blender Foundation), de modo que el reproductor se
puede ejercitar de punta a punta sin contenido de terceros:

```
GET /live/1001.m3u8     →  #EXTM3U con variantes apuntando a /segments/…
GET /segments/…         →  .ts generados en memoria (tono + carta de ajuste)
```

## 4. Endpoints extra (no Xtream) del backend de referencia

Para cubrir lo que la app original resuelve con su backend propio, sin tocar el de ellos:

| Endpoint | Equivalente en Drama Live | Qué devuelve |
|---|---|---|
| `GET /config/remote` | la config embebida en `classes.dex` | flags de la app: ads, billing, fuentes habilitadas, URLs. **Todo desactivado y apuntando a localhost.** |
| `GET /catalog/featured` | catálogo "de la casa" | carruseles para la portada, con contenido libre |
| `GET /catalog/search?q=` | `smart_search_url` (`/search/v3/`) | búsqueda sobre el catálogo local |
| `GET /sources` | lista de fuentes dadas de alta | fuentes configuradas en el backend (solo `mock` por defecto) |
| `GET /health` | — | `{ ok, version, uptime, catalog }` |

`GET /config/remote` devuelve deliberadamente la **misma forma** que la config de Drama Live
(`appVersionModel`, `serverSettingsModel`, `adsModel`, `mainServerModelArraylist`,
`socialModelArraylist`, `modModel`, `fg_active`), para que el cliente pueda parsear una u otra
sin cambios. Con las credenciales fuera y todas las URLs apuntando a `localhost`:

```json
{
  "appVersionModel": { "app_version": "1.0.0", "forceUpdate": false, "update_url": "" },
  "serverSettingsModel": {
    "server_url": "http://localhost:8080/api/",
    "live_url":   "http://localhost:8080/api/",
    "chat_http_url": "",
    "xmpp_ip": "",
    "crash_reporting_url": "",
    "banned_apps": []
  },
  "adsModel": { "home_ban": "nactive", "billing_available": false },
  "fg_active": false
}
```

## 5. Límites y cabeceras

```
Rate limit      : 120 req/min por credencial, 429 + Retry-After
CORS            : Access-Control-Allow-Origin: *  (solo el backend local de desarrollo)
Cache           : Cache-Control: no-store en /player_api.php
                  Cache-Control: public, max-age=3600 en /segments/*
User-Agent      : el cliente se identifica como  dramalive-replica/<version>
Timeout cliente : 10 s connect / 30 s read
Reintentos      : 2, con backoff exponencial 500 ms → 2 s, solo en GET idempotentes
```

## 6. Verificación

```bash
make backend
curl -s 'localhost:8080/health'
curl -s 'localhost:8080/player_api.php?username=demo&password=demo'
curl -s 'localhost:8080/player_api.php?username=demo&password=demo&action=get_live_categories'
curl -s 'localhost:8080/player_api.php?username=demo&password=demo&action=get_live_streams'
curl -s 'localhost:8080/player_api.php?username=demo&password=demo&action=get_short_epg&stream_id=1001'
curl -sI 'localhost:8080/live/1001.m3u8'
```

Suite de contrato: `backend/test.sh` (98 aserciones sobre forma, tipos, cabeceras y resolución de URIs relativas).

---

## 6. Protocolo REAL del APK (generación A) — extraído estáticamente

> **Método y límites.** Todo lo siguiente sale del **pool de cadenas y de los campos de las
> clases de modelo** de `com.sneig.livedrama` v13.0.3/187, con `androguard` sobre
> `classes.dex/4/6/7`. **No se contactó ningún endpoint**, no se ejecutó la app y no se
> descompiló a Java legible. Como el APK usa **Gson sin `@SerializedName`**, el esquema JSON
> coincide con los **nombres de campo** de sus modelos: leerlos es leer el contrato. Solo se
> publican **nombres de campo / claves**, nunca valores de credenciales, hosts o tokens
> (ver `analysis/evidence/apk-schema-genA.json`).

### 6.1 Sobre de configuración remota

`SettingsModel` es la envolvente que la app descarga al arrancar:

```
adsModel · appVersionModel · fg_active · mainServerModelArraylist ·
modModel · serverSettingsModel · socialModelArraylist
```

con claves adicionales leídas vía `optString`: `FG`, `TLS`, `advanced`, `all`, `data`,
`url`, `live_fav`, `show_fav`.

`ServerSettingsModel` es el **mapa completo de servidores** (el mismo que aparece embebido
en el DEX, hallazgo F-03/F-01). Sus nombres de campo *son* las claves JSON del endpoint de
configuración:

```
server_url · live_url · sport_server_url · redirect_url · log_url ·
chat_http_url · xmpp_ip · file_server_url · fgcode_url · smart_search_url ·
business_url · legal_url · privacy_policy_url · faqs_url · tutorial_video ·
support_email · admin_email · admin_email_paid ·
crash_reporting_url · crash_reporting_login · crash_reporting_password · banned_apps
```

(Los tres últimos son el hallazgo **F-01**; aquí figuran solo como esquema.)

### 6.2 Fuente por stream: el mecanismo de cabeceras/SSL

La pieza técnicamente más relevante para entender por qué sus streams "funcionan" detrás de
protecciones:

| Modelo | Campos | Significado |
|---|---|---|
| `AdvancedUrl` | `url, agent, headers, acceptSSL` | Cada URL de stream lleva su propio **User-Agent**, sus **cabeceras HTTP** y su **política SSL**. |
| `LiveModel` | `url, agent, backup, id_live, id_topic, …` | Entrada de canal con UA propio y URL de **respaldo**. |
| `BackupLiveModel` | `url, agent` | Respaldo con UA propio. |
| `XtreamModel` | `url, agent, autoRefresh, acceptSSL` | Fuente Xtream/M3U con UA y refresco. |

Es decir, el cliente inyecta **cabeceras y User-Agent por stream** y puede **aceptar SSL
débil/cleartext por URL** (`acceptSSL`). Eso es, a nivel de app, la base del hotlink-bypass y
de la tolerancia a HTTP plano que documenta **F-02**. Este repo **no** reproduce ese
mecanismo contra servicios ajenos: su backend de referencia y su cliente usan un único
origen propio y TLS-friendly.

### 6.3 Resto del esquema (resumen)

- **Actualización forzada** (`AppVersionModel`): `app_version, forceUpdate, update_url,
  update_url_direct, update_message[_ar|_fr]` → coincide con **F-04** (sideload).
- **Ads/billing** (`AdsModel`): `billing_available, coupon_*, home_nat, live_nat,
  sport_nat, *_ban, all_int, time_int` → los flags que la config pone en off (F-10).
- **Deportes** (`MatchModel`): `id, title, topic, channel, date, url, firstTeam…,
  secondtTeam…`.
- **Topics/favoritos**: `TopicModel{id_topic,name_topic,img_url_topic}`.
- **Chat XMPP** (`MyInfoModel, RoomModel, MessageModel, UserModel`) → objetivo REA
  `09-CHAT-XMPP.md`.
- **Cache local SQLite**: tablas `topics` y `lives` donde cosecha la lista offline.

### 6.4 Cripto y stack HTTP (esquema, no explotación)

- Cifrado de payloads de la API propia: **AES/CBC** con **PKCS5/PKCS7Padding**, vía
  `Cipher` + `SecretKeySpec` + `IvParameterSpec`; digests MD5 y SHA-256. Se documenta el
  esquema; **no** se reproducen claves ni se rompe el cifrado (sería elusión de una medida
  tecnológica, fuera del alcance de este proyecto).
- Stack: **sin Retrofit**; `HttpURLConnection` + `okhttp3`; JSON con `org.json` + **Gson por
  nombre de campo**; XMPP con **Smack**.
