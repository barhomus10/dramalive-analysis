# 07 — Hallazgos de seguridad

**Artefacto:** `dramalive.apk` — `com.sneig.livedrama` v13.0.3 (187)
**SHA-256:** `a3ab61b5aaa6adf028358db75415158484500eee9ea36461d0605368e8f78d55`
**Origen:** `https://dataflowstation.net/download/g/dramalive_site` → 302 → `https://download.twoapistack.work/download/g/dl/dramalive.apk` (30.524.011 bytes, `Last-Modified: 2025-08-09`)
**Fecha del análisis:** 2026-10-20

> 🔒 **Política de este documento.** Los hallazgos se publican **sin los datos que permiten
> explotarlos**: las credenciales de terceros están redactadas en
> `analysis/evidence/embedded-remote-config.REDACTED.json` y no aparecen en ningún archivo
> versionado. El objetivo es la **divulgación responsable**, no la explotación.
> Ver `docs/00-LEGAL-Y-ALCANCE.md` §4.4.

---

## Resumen

| ID | Severidad | Hallazgo | Estado |
|---|---|---|---|
| [F-01](#f-01) | 🔴 **Alta** | Credenciales del servidor de crash reporting embebidas en claro en `classes.dex` | abierto |
| [F-02](#f-02) | 🔴 **Alta** | Todo el backend va por **HTTP plano**, incluyendo el flujo de activación con usuario/contraseña del panel IPTV | abierto |
| [F-03](#f-03) | 🟠 Media | IP pública de AWS hardcodeada como servidor de respaldo, con puerto no estándar | abierto |
| [F-04](#f-04) | 🟠 Media | Autoupdate por `REQUEST_DELETE_PACKAGES` + HTTP → cadena de instalación remota de APK | abierto |
| [F-05](#f-05) | 🟠 Media | Reporte ACRA con datos de dispositivo a un dominio de tercero por HTTP | abierto |
| [F-06](#f-06) | 🟡 Baja | `minSdkVersion 16` con `targetSdkVersion 34` | abierto |
| [F-07](#f-07) | 🟡 Baja | Firma v1+v2 sin v3; certificado autofirmado con validez de 99 años | abierto |
| [F-08](#f-08) | 🟡 Baja | Superficie de componentes desproporcionada (102 actividades, 95 de SDKs publicitarios) | abierto |
| [F-09](#f-09) | ℹ️ Info | Lista `banned_apps` de 25 paquetes → la plantilla se redistribuye sin control | abierto |
| [F-10](#f-10) | ℹ️ Info | Contradicciones del modelo de monetización (15 redes de ads integradas, todas desactivadas por config) | abierto |

---

<a name="f-01"></a>
## F-01 · Credenciales embebidas en claro — 🔴 Alta

### Qué

La app lleva **un JSON de configuración remota embebido como literal en `classes.dex`**
(offset ≈ `7587537`, longitud 3.391 bytes). Dentro de `serverSettingsModel`:

```json
"crash_reporting_url":      "http://crash2.semprotech.online:8080/report",
"crash_reporting_login":    "<16 caracteres — REDACTADO>",
"crash_reporting_password": "<16 caracteres — REDACTADO>"
```

Es el par usuario/contraseña de **ACRA** (Application Crash Reports for Android) contra el
colector `crash2.semprotech.online:8080`. Las credenciales son **estáticas y compartidas por
todas las instalaciones** de la app — no hay rotación ni credenciales por dispositivo.

### Cómo se reproduce

```bash
unzip -o dramalive.apk classes.dex -d /tmp/x
strings -n 8 /tmp/x/classes.dex | grep -A2 crash_reporting
# o, con la herramienta del repo:
analysis/scripts/apk_triage.sh dramalive.apk
```

No hace falta descompilar ni ejecutar nada: son literales en la tabla de cadenas del DEX.

### Impacto

Quien tenga el APK (es público, se distribuye por `dataflowstation.net`) puede:

1. **Enviar reportes falsos** → envenenar la telemetría de crashes, inutilizando el
   monitoring del desarrollador, o saturar el colector (DoS barato).
2. **Leer reportes ajenos** si el endpoint permite `GET` con Basic Auth → los reportes ACRA
   incluyen `Build.MODEL`, `Build.VERSION`, `Settings.Secure.ANDROID_ID`, stacktraces y, con
   `logcat` habilitado, **fragmentos de log que pueden contener tokens de sesión o URLs con
   credenciales**.
3. **Reutilización**: si `semprotech` usa esas credenciales en otros servicios (es el patrón
   típico en estudios pequeños), el alcance se amplía.

### Remediación

- Rotar **ya** esas credenciales: están en un APK público desde al menos agosto de 2025.
- No enviar credenciales en el binario. El flujo correcto para ACRA:
  - registrar el dispositivo en el backend propio y obtener un **token de corta vida por
    instalación**, o
  - usar un endpoint de ingesta **write-only con token de escritura** y lectura autenticada
    por separado, o
  - migrar a Firebase Crashlytics (¡que **ya está integrado** en este APK!) y eliminar ACRA.
- Quitar el `:8080` y servir detrás de TLS con un reverse proxy.

> **Nota de divulgación:** se avisará a `support@dramalive.org` (canal que la propia app
> publica en su config) antes de hacer público este informe. No se ha intentado acceder al
> endpoint: verificar la exploitabilidad con credenciales ajenas sería acceso no autorizado.

---

<a name="f-02"></a>
## F-02 · HTTP plano en todo el backend, incluidas credenciales de usuario — 🔴 Alta

### Qué

Todas las URLs de la config embebida usan `http://`, no `https://`:

```
server_url          http://main.eastgoessouth.online/api/live/livedrama/v13.0.0/
live_url            http://live.eastgoessouth.online/api/live/livedrama/v13.0.0/
sport_server_url    http://sport.eastgoessouth.online/sport/
smart_search_url    http://shows.eastgoessouth.online/search/v3/
redirect_url        http://redirect.eastgoessouth.online/redirect/
log_url             http://log.eastgoessouth.online/api/live/livedrama/v9.0.0/
chat_http_url       http://chat.eastgoessouth.online/chat/api/
file_server_url     http://file.twoapistack.work/
```

Y la XMPP apunta a un host sin esquema (`xmpp_ip: fire.eastgoessouth.online`), que con
Smack por defecto negocia en claro con STARTTLS **opcional**.

A eso se suma que `networkSecurityConfig` está declarado (`@7f160003`), lo que indica que se
configuró explícitamente para **permitir tráfico en claro** — en `targetSdk 34` el cleartext
viene deshabilitado por defecto.

### Lo que agrava el hallazgo

El flujo de activación Xtream (idéntico al del build web) envía **las credenciales del panel
IPTV del usuario**:

```
http://mikkm.xyz/android/androidApi.php?url=<panel>&mode=live&username=<user>&password=<pass>
```

En claro, por query string, **a un dominio de un tercero** que no es ni `dramalive.*` ni
`eastgoessouth.online`. Cualquier observador de la red (WiFi pública, ISP, o el propio
operador de `mikkm.xyz`) ve usuario y contraseña del panel.

### Impacto

- **MITM trivial** en WiFi abierto: el atacante puede leer y **modificar** cualquier respuesta.
  Como la config remota también llega por HTTP, un MITM puede **cambiar la lista de
  servidores, las URLs de update y el catálogo** → redirigir a la víctima a un APK malicioso
  (ver F-04) o a streams falsos.
- Robo de credenciales Xtream → acceso al panel del usuario (y a su historial/facturación).
- Inyección de contenido en el reproductor.

### Remediación

1. TLS obligatorio en todos los hosts (`eastgoessouth.online`, `twoapistack.work`).
2. `networkSecurityConfig` con `cleartextTrafficPermitted="false"` y sin excepciones.
3. Eliminar el proxy `mikkm.xyz`: hablar directo con el panel del usuario, con las
   credenciales en el **cuerpo** de la petición POST, nunca en el query string.
4. Certificate pinning sobre el backend propio.
5. STARTTLS **required** + SASL en XMPP.

---

<a name="f-03"></a>
## F-03 · IP de infraestructura hardcodeada — 🟠 Media

### Qué

En `mainServerModelArraylist` (lista de servidores de respaldo con failover):

```json
[
  { "url": "http://main.backendcoreapi.com/api/live/livedrama/v13.0.0/",  "checked": false },
  { "url": "http://main.swiftapi.org/api/live/livedrama/v13.0.0/",        "checked": false },
  { "url": "http://<IP-REDACTADA>:8787/api/live/livedrama/v13.0.0/",      "checked": false },
  { "url": "http://dramalive.app:8787/api/live/livedrama/v13.0.0/",       "checked": false }
]
```

La tercera entrada es una **IP literal** en el rango de AWS EC2 `eu-central-1` (Frankfurt),
con un **puerto no estándar (8787)** expuesto directamente.

> La IP concreta se omite deliberadamente de este repo: publicarla facilita el escaneo de un
> host de un tercero. Está registrada en el informe privado que se enviará al titular.

### Impacto

- Revela la topología real de la infraestructura (la IP no rota con DNS).
- Un host con IP fija y puerto no estándar **no está detrás del WAF/CDN** que sí cubre los
  dominios → es el eslabón débil. Si el WAF se salta, las protecciones de rate-limit y
  filtrado también.
- La IP queda **fosilizada** en todas las instalaciones distribuidas: si el servidor se
  reubica, o peor, si esa IP se libera y la asigna AWS a **otro cliente**, todas las apps
  instaladas empezarán a enviar tráfico (y credenciales) a un host de un tercero ajeno.
  Este es un fallo conocido de diseño ("dangling IP") y es grave cuando hay failover
  automático.

### Remediación

- Sustituir la IP por un nombre DNS propio, siempre.
- Poner el backend de respaldo detrás del mismo CDN/WAF.
- Si se necesita failover, usar DNS con varios registros A/AAAA y health checks, no una lista
  de IPs en el cliente.

---

<a name="f-04"></a>
## F-04 · Cadena de autoupdate: HTTP + `REQUEST_DELETE_PACKAGES` — 🟠 Media

### Qué

El manifiesto pide `android.permission.REQUEST_DELETE_PACKAGES` (permite lanzar el diálogo de
**desinstalación** de otras apps) y la config embebida trae:

```json
"appVersionModel": {
  "forceUpdate":     false,
  "update_url":        "https://dataflowstation.net/download/g/dramalive",
  "update_url_direct": "https://dataflowstation.net/download/g/dramalive",
  "update_message":    "New update is available"
}
```

El flujo es: la app consulta la versión remota, y si hay update descarga un APK y lanza el
instalador del sistema. Confirmado por los literales DEX del propio código de la app:
`apk_download_start`, `apk_download_end`, `apk_start_install`, `apk_verify`, `apk_sign`,
`apkHash`, `apk_sig`, `apk_allow_install_in_bg`, `apk_redownload`.

**Nota positiva:** existen `apk_verify` / `apk_sign` / `apkHash`, así que hay verificación de
integridad del APK descargado. Eso mitiga parte del riesgo. `update_url` además **sí** es
HTTPS.

### Impacto residual

- La **decisión** de actualizar (qué versión es la actual, si `forceUpdate` está activo) puede
  llegar por el canal HTTP de F-02 → un MITM puede forzar el diálogo de update o de
  desinstalación de forma persistente, aunque no pueda instalar un APK firmado por otro.
- `REQUEST_DELETE_PACKAGES` en un reproductor de vídeo no tiene justificación funcional
  evidente. Combinado con `RECEIVE_BOOT_COMPLETED` y con un `BackgroundService` (StartApp),
  es el tipo de combinación que los análisis automáticos marcan como *potentially unwanted
  behavior*.

### Remediación

- Servir el manifiesto de versión por HTTPS con pinning.
- Retirar `REQUEST_DELETE_PACKAGES` si no hay un caso de uso real (¿limpiar clones? entonces
  debe declararse en la política de privacidad y en Play Console).
- Distribuir actualizaciones por Play Store / App Bundle en lugar de sideload.

---

<a name="f-05"></a>
## F-05 · Telemetría ACRA a dominio de tercero por HTTP — 🟠 Media

Consecuencia directa de F-01 + F-02, con agravante de privacidad: el reporte de crash viaja
**sin cifrar** a `crash2.semprotech.online:8080`, un dominio que **no es del producto**
(`dramalive.*`) sino del estudio desarrollador. Un usuario de Drama Live no tiene forma de
saber que sus stacktraces e identificadores de dispositivo acaban en `semprotech.online`.

Revisar la política de privacidad (`https://dramalive.app/privacy.htm`): debe listar
`semprotech.online` como encargado del tratamiento. Bajo GDPR/Decisión 351 CAN, omitirlo es
una infracción de transparencia.

---

<a name="f-06"></a>
## F-06 · `minSdkVersion 16` — 🟡 Baja

`minSdk 16` = **Android 4.1 Jelly Bean (2012)**. Con `targetSdk 34`.

- Google Play exige `targetSdk` alto (cumple) pero `minSdk 16` implica arrastrar soporte de
  bibliotecas obsoletas y obliga a `org.apache.http.legacy` (declarado en `<uses-library>`),
  eliminado del framework en API 28+.
- Es casi seguro que sea **configuración residual** de la plantilla: ningún SDK publicitario
  moderno soporta ya API 16. En la práctica el `minSdk` efectivo lo fija la biblioteca más
  exigente.
- Riesgo: con `minSdk` tan bajo, `android:exported` no es obligatorio y hay paths de código
  para versiones donde los `PendingIntent` no son inmutables por defecto.

**Remediación:** subir a `minSdk 24` (Android 7.0) y eliminar `org.apache.http.legacy`.

---

<a name="f-07"></a>
## F-07 · Esquema de firma — 🟡 Baja

```
v1 (JAR) : sí
v2       : sí
v3       : NO
v4       : no evaluado
Issuer   : CN=Sneig, O=Sneig        ← autofirmado, sin datos de contacto
Subject  : CN=Sneig, O=Sneig
Serial   : 2015039090
Validez  : 2020-03-28 → 2119-03-05  ← 99 años
SHA-256  : 8A7A985441CA6C688D3FED E5D589A0744222C330 1E6EEA157CDF58668CE1FB1
```

- **Sin v3** no se puede hacer *key rotation*: si la clave privada se pierde o se filtra, la
  app queda inutilizable para siempre (no se puede publicar una actualización firmada por otra
  clave). Con 99 años de validez declarada, ese riesgo importa.
- `O=Sneig` sin organización verificable dificulta atribuir la app a una entidad legal.

**Remediación:** firmar con v2+v3, usar Play App Signing (delega la clave de publicación en
Google y permite rotación), y un certificado con datos de organización reales.

---

<a name="f-08"></a>
## F-08 · Superficie de componentes — 🟡 Baja

| Componente | Total | Propios (`com.sneig.livedrama.*`) | De SDKs |
|---|---|---|---|
| Actividades | 102 | **7** | 95 |
| Servicios | 21 | 3 | 18 |
| Receivers | 14 | 1 | 13 |
| Providers | 15 | 0 | 15 |
| DEX | 8 (≈58 MB sin comprimir) | — | — |
| Archivos en el APK | 4.106 | — | — |
| Tamaño | 30,5 MB | — | — |

Las 7 actividades propias son toda la app:

```
StartActivity        ← launcher (también LEANBACK_LAUNCHER → Android TV)
IntroActivity
HomeActivity
LiveActivity
MultyPlayerActivity  [sic]
FullScreenActivity
ProfileActivity
```

Servicios propios: `chat.services.ConnectXmpp`, `services.MyFcmListenerService`,
`services.SwipOutService`.

**Riesgo:** 95 actividades exportables o lanzables de SDKs publicitarios amplían mucho la
superficie de ataque local (intents maliciosos desde otra app del dispositivo). Varias de
ellas (`MaxDebugger*`, `ironsource.testSuite`, `yandex.debugpanel`, `IntegrationInspector`)
son **paneles de depuración** que no deberían estar en un build de producción.

**Remediación:** excluir los módulos de *debug/test-suite* de los SDKs en release
(`debugImplementation` en vez de `implementation`), y auditar `android:exported` de cada
actividad de terceros.

---

<a name="f-09"></a>
## F-09 · `banned_apps`: la plantilla clonada 25 veces — ℹ️ Info

La config trae una lista de **25 paquetes prohibidos**:

```
com.dramatvesp.rgyptemtkdh     com.app.dramalivetvplayer      com.drama_live.drama_live_tv_apk
drama.live.tv                  net.dramalive.tvplayer         com.app.dramatvforyou
com.dramalive23                com.dramatv01                  com.app.dramalivearabeforu
com.app.dramatelfaziback       com.app.dramaarabictv          app2022.mopikora1122
app2022.yallashootelive1122    shabaktytv22022.app            app2022.elastooralive332022
ostorakora112022.app           yacinetv2022live2211.app       qata22022rfifa2022.app
dramalive2022.app              dramakivee10120.app            dramakivee10110.app
com.dramalive.footballlive     app2022.livedrama11            com.matches.football.livesfootball
app2022.yasinetvlive11
```

Lectura técnica: **esta app es una plantilla white-label** que se ha reempaquetado decenas de
veces con otro `applicationId`, otro nombre y otro icono (nótese la temática: fútbol,
Ramadán, Qatar 2022, Yasine TV, Kora árabe…). La lista `banned_apps` es un **mecanismo de
control de canal**: el backend o la app comprueba si el paquete actual está en la lista y se
niega a funcionar. Sirve para:

- Bloquear **clones pirateados** de la propia plantilla.
- Retirar del mercado apps de un revendedor que dejó de pagar.
- Responder a **takedowns** (varios de esos nombres huelen a apps ya retiradas de Play).

Implicación para este repo: cualquier "réplica" que se publique con uno de esos
`applicationId` **no arrancará**. Y, más importante, confirma que el valor del producto no
está en el cliente sino en **el catálogo del backend** — que es exactamente lo que este
proyecto **no** replica (ver `docs/00-LEGAL-Y-ALCANCE.md`).

---

<a name="f-10"></a>
## F-10 · Monetización: 15 redes integradas, todas apagadas — ℹ️ Info

El APK integra **15 redes publicitarias**: AppLovin MAX, ironSource, Unity Ads, Vungle,
Tapjoy, StartApp, InMobi, Mintegral, Pangle/ByteDance, Maticoo, Bigo, Yandex, myTarget (VK),
AppNext, Chartboost — orquestadas por **TopOn/AnyThink** (`com.anythink.*`, `mores.toponad.com`,
`ssapi.mosspf.com/sdk/realtime_waterfall`).

Y sin embargo la config remota las desactiva todas:

```json
"adsModel": {
  "home_ban": "nactive", "live_ban": "nactive", "all_int": "nactive", "time_int": "5",
  "home_nat": "nactive", "live_nat": "nactive", "sport_nat": "nactive",
  "billing_available": false, "coupon_available": false, "coupon_active": false,
  "coupon_end_date": ""
}
```

`"nactive"` (sic, no `"inactive"`) es el valor por defecto: los ads se **encienden en remoto**.
Igual `billing_available: false` → el pago in-app (Google Play Billing **sí** está integrado)
está apagado por flag remoto.

**Consecuencias:**

1. Los **30,5 MB** del APK son en su mayor parte SDKs publicitarios inactivos. Es el coste de
   la plantilla white-label.
2. Un flag remoto puede **activar publicidad y cobros** sin actualizar la app ni pasar
   revisión de Play Store. Eso es legítimo si se declara, pero:
   - `ACCESS_ADSERVICES_AD_ID` + `AD_ID` + `ACCESS_ADSERVICES_ATTRIBUTION` + `ADSERVICES_TOPICS`
     están pedidos **desde la primera instalación**, antes de que exista ningún anuncio.
   - Con F-02 (HTTP), el flag remoto puede **falsearlo un MITM**: encender ads o alterar
     `billing_available` en el dispositivo de la víctima.
3. Hay `user-messaging-platform` (UMP/TCF de Google) integrado, lo que sugiere gestión de
   consentimiento GDPR. Verificar que el consentimiento se pide **antes** de inicializar las
   15 redes, no después.

---

## Permisos solicitados (22)

```
INTERNET                     ACCESS_NETWORK_STATE       ACCESS_WIFI_STATE
WAKE_LOCK                    FOREGROUND_SERVICE         FOREGROUND_SERVICE_MEDIA_PLAYBACK
POST_NOTIFICATIONS           RECEIVE_BOOT_COMPLETED     REQUEST_DELETE_PACKAGES   ⚠ F-04
CAMERA                       READ_MEDIA_IMAGES          READ_EXTERNAL_STORAGE
WRITE_EXTERNAL_STORAGE       com.android.vending.BILLING
ACCESS_ADSERVICES_AD_ID      ACCESS_ADSERVICES_ATTRIBUTION  ACCESS_ADSERVICES_TOPICS  ⚠ F-10
com.google.android.gms.permission.AD_ID
com.google.android.c2dm.permission.RECEIVE
com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE
com.applovin.array.apphub.permission.BIND_APPHUB_SERVICE
com.sneig.livedrama.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION   ← correcto, Android 14
```

`CAMERA` en un reproductor de TV en vivo no tiene justificación funcional obvia (¿QR para
compartir? ¿avatar del chat?). Debe declararse en la política de privacidad.

**No** se piden: `ACCESS_FINE_LOCATION`, `READ_CONTACTS`, `RECORD_AUDIO`, `READ_PHONE_STATE`.
Eso es una buena señal relativa — el abuso potencial se limita al identificador de publicidad.

---

## Metodología y reproducibilidad

```bash
analysis/scripts/apk_triage.sh dramalive.apk      # manifiesto + firma + strings + config
analysis/scripts/extract_endpoints.py             # URLs y dominios
```

Herramientas: `unzip`, `androguard 4.1.4` (parser AXML + certificado), y extracción de
literales del pool de cadenas del DEX. **No se ejecutó la app**, **no se descompiló a Java**,
**no se hizo análisis dinámico** y **no se contactó ningún endpoint** de la lista.

### Siguiente paso: análisis con REA

Los literales dan el mapa de servidores pero no el **protocolo**: qué paths concretos cuelgan
de `/api/live/livedrama/v13.0.0/`, qué cabeceras de autenticación, qué esquema JSON. Eso
vive en el código de `com.sneig.livedrama` (probablemente OkHttp/Retrofit + Gson) y se
extrae con descompilación. Ver `docs/06-FLUJO-REA.md` para la tarea lista para REA.

---

## F-11 · Ecosistema de clones white-label (ℹ️ contexto, no un hallazgo de Drama)

El hallazgo F-09 (`banned_apps`, 25 paquetes) indica que la plantilla de Drama Live se
clona en cadena. Para dimensionar el ecosistema se auditó **estáticamente** un repositorio
público que se autodefine como «cliente al estilo de DramaLive»
(`youcefyakhoo/PelisLatino-Android`, Java, ~288 archivos, creado 2026-10).

> **Alcance de esta auditoría:** solo lectura del código público. **No se ejecutó** contra
> Drama Live ni contra ningún otro servicio, **no se reprodujo su método de extracción** y
> **no se publican aquí hosts, claves ni tráfico capturado** (se redactan). El objetivo es
> documentar el ecosistema y sus riesgos, no proveer un how-to.

Clases de falla observadas en ese clon (referencias a archivos, sin secretos):

| # | Clase | Evidencia (redactada) |
|---|-------|-----------------------|
| a | **Tráfico real y vectores de clave de terceros commiteados** a git | `app/src/test/resources/drama_*_real.bin`, `docs/vectores-clave-*.json` trackeados, pese a que el `.gitignore` sí tiene sección de secretos |
| b | **Elusión de cifrado del servicio** (AES/CryptoJS revertido para leer su tráfico) | `assets/drama_auto.js` (AES propio), lado Java con `SecretKeySpec` + KDF tipo OpenSSL |
| c | **Sesión aprendida en claro** + `allowBackup=true` con reglas de backup por defecto (sin excluir nada) | `DramaSesion.java` (`SharedPreferences`), `AndroidManifest.xml`, `res/xml/backup_rules.xml` |
| d | **WebView remoto con puente JS** expuesto a la página cargada | `DramaAutoActivity.java` (`setJavaScriptEnabled`, `addJavascriptInterface`, `@JavascriptInterface`) |
| e | **Canal de control sobre relay público** sin auth real (topic como único secreto) | `tools/puente-ntfy.py` |
| f | **Spoofing de Referer/Origin/User-Agent** por host para saltar protección de hotlink | `tools/api-canales/server.mjs`, `Encabezados.java` |
| g | **Tráfico abusivo** al objetivo documentado por ellos mismos («98 req en 13 s») | comentario en `assets/drama_auto.js` |
| h | **Licencia incorrecta** (OFL-1.1, de tipografías, aplicada a una app) y `targetSdk` por detrás de Play | `LICENSE`, `app/build.gradle` |

**Conclusión para este proyecto:** esas fallas (a–g) son la consecuencia directa de extraer
contenido real de un servicio ajeno. `dramalive-analysis` las evita **por diseño**: no
commitea tráfico de terceros, no revierte cifrados ajenos, no guarda sesiones, no hace
puentes WebView de captura, no tunelea control por relays públicos y no spoofea cabeceras.
La reproducción real que ofrece este repo (canal 9001) usa **únicamente contenido generado
por el propio repo**. Ver `docs/00-LEGAL-Y-ALCANCE.md` §4.
