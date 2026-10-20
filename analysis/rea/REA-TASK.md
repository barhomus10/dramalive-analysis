# Tarea para REA — `com.sneig.livedrama` v13.0.3 (187)

Copia este documento entero en tu sesión de [REA](https://github.com/morluto/rea).
Está escrito para que REA pueda trabajar sin contexto adicional.

---

## Contexto

Analizo una app Android de terceros con fines de investigación e interoperabilidad,
documentados en el repo `dramalive-analysis`. **Ya está hecho** el triage estático
superficial; lo que sigue es el trabajo de fondo.

**Artefacto:** `dramalive.apk`
**SHA-256:** `a3ab61b5aaa6adf028358db75415158484500eee9ea36461d0605368e8f78d55`
**Package:** `com.sneig.livedrama` · **versionName** 13.0.3 · **versionCode** 187
**minSdk** 16 · **targetSdk** 34 · 8 DEX (~58 MB) · 4.106 archivos · 30,5 MB
**Firma:** v1+v2, `CN=Sneig, O=Sneig`, autofirmado, validez 2020→2119

**Naturaleza:** reproductor IPTV estilo *bring-your-own-source* (Xtream Codes / M3U /
FG Code / playlists en GitHub) con chat XMPP (Smack) y 15 SDKs publicitarios
integrados pero desactivados por config remota.

## Lo que YA se sabe (no repetir)

Config remota embebida como literal JSON en `classes.dex` (offset ≈ 7587537, 3.391 B),
ya extraída en `analysis/evidence/embedded-remote-config.REDACTED.json`:

```
server_url        http://main.eastgoessouth.online/api/live/livedrama/v13.0.0/
live_url          http://live.eastgoessouth.online/api/live/livedrama/v13.0.0/
sport_server_url  http://sport.eastgoessouth.online/sport/
smart_search_url  http://shows.eastgoessouth.online/search/v3/
redirect_url      http://redirect.eastgoessouth.online/redirect/
log_url           http://log.eastgoessouth.online/api/live/livedrama/v9.0.0/
chat_http_url     http://chat.eastgoessouth.online/chat/api/
xmpp_ip           fire.eastgoessouth.online
file_server_url   http://file.twoapistack.work/
fgcode_url        fgcode.org
crash_reporting   http://crash2.semprotech.online:8080/report   ← credenciales REDACTADAS
update_url        https://dataflowstation.net/download/g/dramalive
failover          main.backendcoreapi.com, main.swiftapi.org, <IP AWS>:8787, dramalive.app:8787
banned_apps       25 packageIds
```

Componentes propios (7 actividades, 3 servicios, 1 receiver):

```
activities.StartActivity (launcher + LEANBACK_LAUNCHER)
activities.IntroActivity      activities.HomeActivity
activities.LiveActivity       activities.MultyPlayerActivity
activities.FullScreenActivity activities.ProfileActivity
chat.services.ConnectXmpp     services.MyFcmListenerService
services.SwipOutService       services.ActionReceiver
MyApplication
```

Acciones de activación de fuente: `ACTIVATE_XTREAM`, `ACTIVATE_M3U`, `ACTIVATE_FG`.
Xtream se resuelve vía `http://mikkm.xyz/android/androidApi.php?url=<host>&mode=live&username=<u>&password=<p>`,
emitiendo `<url>---<name>` con `name` por defecto `"shai"`.

## Objetivo del análisis

**El mapa de hosts ya está. Falta el protocolo.** Necesito, en este orden:

### 1. Cliente HTTP de `com.sneig.livedrama` (prioridad máxima)

Localizar la clase que construye las peticiones al backend propio (probablemente
OkHttp + Retrofit o OkHttp + Gson a mano, dada la presencia de `okhttp3/` y de
`.proto` filtrados en la raíz del APK).

Extraer:

- **Paths concretos** que se concatenan a `server_url` / `live_url`
  (`/api/live/livedrama/v13.0.0/…`). Los literales de ruta **no** aparecen como
  cadenas completas en el DEX: se construyen. Hay que seguir el flujo.
- **Cabeceras**: `User-Agent`, cualquier token/`device_id`/firma, `Accept`.
- **Parámetros de query** obligatorios (¿`package`? ¿`version`? ¿`device`?).
- **Esquema JSON** de respuesta de cada path → modelos Gson/`@SerializedName`.
- **Lógica de failover** sobre `mainServerModelArraylist`: ¿en qué orden, con qué
  timeout, qué condición marca un servidor como caído, se persiste el elegido?
- Cómo se compone la URL de **reproducción** final a partir de la respuesta.

Entregable: una tabla `path → método → parámetros → modelo de respuesta` y, para
cada modelo, los campos con su tipo y su nombre JSON.

### 2. Remote config y kill-switches

La config embebida es solo el **valor por defecto**. Existe un refresco remoto.

- ¿Desde qué URL se refresca? ¿Con qué frecuencia? ¿Se cachea en `SharedPreferences`
  o en Room? (buscar `app_settings_json`, `app_settings_last_update_ms` — ya
  aparecen como literales en el DEX).
- Semántica exacta de cada flag de `adsModel` (`home_ban`, `live_ban`, `all_int`,
  `time_int`, `home_nat`, `live_nat`, `sport_nat`) y del valor `"nactive"`.
- `billing_available`, `coupon_available`, `coupon_active`, `coupon_end_date`:
  ¿qué desbloquean y dónde se comprueban?
- `modModel` (`mod_ar`, `mod_en`, `mod_url`): ¿qué es un "mod"? ¿Es un modo
  alternativo de la app? ¿Se descarga algo desde `mod_url`?
- `fg_active`: ¿qué desactiva exactamente cuando es `false`?

### 3. `banned_apps` — mecanismo de control de canal

25 packageIds prohibidos. Determinar:

- ¿Dónde se compara? ¿Contra `BuildConfig.APPLICATION_ID`, contra
  `PackageManager.getInstalledPackages()` (detectando clones instalados), o ambos?
- ¿Qué hace la app al coincidir? ¿Se niega a arrancar, se limita, o solo reporta
  al backend?
- ¿La lista se actualiza en remoto?

### 4. Autoupdate

Literales relevantes ya localizados: `apk_download_start`, `apk_download_end`,
`apk_start_install`, `apk_verify`, `apk_sign`, `apkHash`, `apk_sig`,
`apk_allow_install_in_bg`, `apk_redownload`, `update_url_direct`.

- ¿Cómo se **verifica** el APK descargado? ¿Contra el certificado de firma de la
  app instalada, contra un hash embebido, contra un hash que viene en la respuesta?
- ¿Se puede forzar la descarga desde remoto (`forceUpdate`)?
- `update_url` vs `update_url_direct`: ¿cuándo se usa cada una?
- ¿Se descarga en segundo plano sin interacción? (`apk_allow_install_in_bg`)

### 5. Chat XMPP

`chat.services.ConnectXmpp` + Smack.

- ¿Cómo se construye el JID? ¿Registro anónimo, SASL PLAIN, o token vía
  `chat_http_url`?
- ¿Puerto 5222 con STARTTLS obligatorio u opcional?
- ¿Qué se persiste localmente de los mensajes? ¿Cifrado?
- `chat_http_url` (`/chat/api/`): ¿qué endpoints tiene y para qué
  (amigos, historial, presencia)?

### 6. Uso del stack cripto

El build **web** (Flutter) incluye `pointycastle` con AES-CBC/CTR/GCM/IGE,
RSA-OAEP/PSS, HMAC, PBKDF2, HKDF y Poly1305. En el APK nativo **no** hay cripto
propia visible. Confirmar:

- ¿El APK cifra algo en reposo (credenciales del panel, caché de playlist)?
- Si no, confirmar que las credenciales Xtream del usuario se guardan en claro
  (buscar escrituras a `SharedPreferences` / DataStore / Room con `password`).

### 7. `SwipOutService` y comportamiento en segundo plano

Un servicio foreground en un reproductor se justifica por la `MediaSession`. Pero
combinado con `RECEIVE_BOOT_COMPLETED`, `REQUEST_DELETE_PACKAGES` y el
`BackgroundService` de StartApp hay que determinar:

- ¿Se relanza al arrancar el dispositivo? ¿Para qué?
- ¿Usa `REQUEST_DELETE_PACKAGES` para desinstalar algo? ¿El qué y bajo qué
  condición? (sospecha: limpieza de clones, relacionado con `banned_apps`)

## Restricciones del análisis

Obligatorias, no negociables:

1. **Solo análisis estático.** No ejecutar la app, ni en emulador ni en dispositivo.
2. **No contactar ninguno de los hosts** que aparezcan. Nada de peticiones a
   `eastgoessouth.online`, `mikkm.xyz`, `twoapistack.work`, `semprotech.online`,
   `dataflowstation.net`, `backendcoreapi.com`, `swiftapi.org` ni la IP de AWS.
   El objetivo es **leer el código**, no sondear un servicio de terceros.
3. **No usar las credenciales embebidas** (`crash_reporting_login` /
   `crash_reporting_password`) para nada. Están redactadas en la evidencia y deben
   seguir estándolo en cualquier salida.
4. **Redactar** en los entregables: credenciales, tokens, IPs literales de
   infraestructura, correos y cualquier dato personal. Los nombres de dominio
   públicos sí se pueden incluir.
5. Si aparece una **vulnerabilidad explotable** (no un fallo de higiene), no
   escribir un PoC funcional: describir el mecanismo y el impacto, y marcarlo
   para divulgación responsable al titular (`support@dramalive.org`).

## Formato de los entregables

Markdown, en `analysis/evidence/`, un archivo por objetivo:

```
analysis/evidence/
├── 05-CLIENTE-HTTP.md        ← paths, cabeceras, modelos JSON, failover
├── 06-REMOTE-CONFIG.md       ← flags, semántica, frecuencia de refresco
├── 07-BANNED-APPS.md         ← mecanismo de control de canal
├── 08-AUTOUPDATE.md          ← verificación de integridad del APK
├── 09-CHAT-XMPP.md           ← JID, auth, TLS, persistencia
├── 10-CRIPTO.md              ← qué se cifra y qué no
└── 11-BACKGROUND.md          ← servicios, boot, REQUEST_DELETE_PACKAGES
```

Cada hallazgo debe llevar:

- **clase y método** donde está (`com.sneig.livedrama.x.y#z`),
- el **fragmento de código** relevante (descompilado, no inventado),
- **qué dex** y, si aplica, offset,
- nivel de **confianza** (confirmado en código / inferido / especulación),
- si es especulación, **qué lo refutaría**.

Sin conjeturas presentadas como hechos. Si algo no se puede determinar con
análisis estático, decirlo explícitamente y proponer qué haría falta.

## Herramientas

Disponibles en el entorno: `unzip`, `python3` + `androguard 4.1.4`, `java`.
Faltan y conviene instalar: `apktool`, `jadx`, `aapt2`.

Ya ejecutado: `analysis/scripts/apk_triage.sh dramalive.apk` →
`analysis/evidence/apk-dramalive/`.

Config de la sesión: `analysis/rea/rea.config.json`.

---

## Estado (actualizado 2026-10-20) — avance estático sin REA/Ghidra

Se adelantó parte del objetivo de protocolo **solo con análisis estático** (androguard sobre
el pool de cadenas y los campos de los modelos), sin descompilador y **sin tocar la red**:

- **Hecho:** esquema JSON real de la config remota y de las fuentes por stream
  (`docs/05-API.md` §6 y `analysis/evidence/apk-schema-genA.json`): sobre `SettingsModel`,
  claves de `ServerSettingsModel`, el mecanismo `AdvancedUrl{url,agent,headers,acceptSSL}` /
  `LiveModel{agent,backup,url}` / `XtreamModel`, esquema de update-forzada, ads/billing,
  deportes, topics, chat XMPP y cache SQLite. Stack confirmado: sin Retrofit,
  HttpURLConnection + okhttp3, Gson por nombre de campo, Smack.
- **Hecho:** esquema de cifrado de la API propia: AES/CBC + PKCS5/PKCS7Padding
  (`SecretKeySpec` + `IvParameterSpec`). Solo esquema; no se rompe ni se reproducen claves.
- **Pendiente (requiere descompilador tipo jadx/Ghidra, ausente en este entorno):** la
  construcción *exacta* de cada request en runtime (qué cabeceras se fijan por llamada, cómo
  se deriva la clave/IV de AES, el orden de los pasos glt→glbr→advanced). Eso es lo que
  justifican los objetivos 1 y 2 con REA; el esquema de arriba ya cubre la mayor parte del
  valor de documentación.

Se mantienen intactas las restricciones: estático, cero tráfico a los hosts prohibidos,
nunca usar credenciales embebidas, redactar, sin PoC funcional.
