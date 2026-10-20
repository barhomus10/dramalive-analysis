# 03 — Stack y dependencias

## 1. Generación A — APK `com.sneig.livedrama` v13.0.3 (187)

Detectado por: literales en el pool de cadenas de los 8 DEX, nombres de paquete en
`AndroidManifest.xml`, archivos `.properties` de Gradle en la raíz del APK y nombres de
bibliotecas nativas en `lib/`.

### Núcleo de la app

| Componente | Evidencia |
|---|---|
| Kotlin + Coroutines | `META-INF/kotlinx_coroutines_{core,android}.version`, `kotlin/*.kotlin_builtins` |
| OkHttp 4 | `okhttp3/internal/publicsuffix/publicsuffixes.gz` en la raíz del APK |
| Room (SQLite ORM) | `androidx.room_room-runtime.version`, `MultiInstanceInvalidationService` |
| DataStore | `androidx.datastore_datastore.version` |
| WorkManager | `androidx.work_work-runtime.version`, 5 receivers de `androidx.work.impl` |
| androidx.startup | `InitializationProvider` → init declarativa de los SDKs |
| Material Components | `com.google.android.material_material.version` |
| ViewPager2, RecyclerView, SwipeRefresh, Transition, Emoji2 | versiones en `META-INF/*.version` |
| Picasso (imágenes) | `com.sneig.livedrama.com.squareup.picasso`, `PicassoProvider` |
| uCrop (recorte de avatar) | `com.yalantis.ucrop.UCropActivity` |
| ExoPlayer / Media3 | literales `exoplayer.dev`, `dashif.org`, `aomedia.org`, `updateDrmInitData`, `LoadControl` |
| AppIntro | `appIntro2BottomBarHeight`, `app_intro_*_button` → onboarding |
| ACRA (crash reporting) | `org.acra.attachment.AcraContentProvider`, `com.sneig.livedrama.acra` |
| Baseline profile | `assets/dexopt/baseline.prof` + `profileinstaller` |

### Chat

| Componente | Evidencia |
|---|---|
| **Smack 4.x** (cliente XMPP completo) | `org.jivesoftware.smack*/smack-config.xml`, `smacktcp.providers`, `smackim.providers`, `extensions.providers`, `experimental.providers` |
| MUC (salas grupales) | namespaces `jabber.org/protocol/muc`, `muc#owner`, `muc#roomconfig` |
| Service Discovery | `jabber.org/protocol/disco#info`, `disco#items` |
| Servicio de conexión | `com.sneig.livedrama.chat.services.ConnectXmpp` |
| Host XMPP | `xmpp_ip: fire.eastgoessouth.online` |
| Chat HTTP API | `chat_http_url: http://chat.eastgoessouth.online/chat/api/` |
| Presencia | literales `appPresence`, `userPresence`, `updateLocalEntityCaps` |

> Smack es una biblioteca **pesada** (arrastra `minidns`, XML pull parsers, `org.jivesoftware`).
> Es la elección correcta si de verdad se usa XMPP completo (MUC + roster + presencia).
> En la generación B (Flutter) el chat se resuelve con `flutter_chat_ui`, mucho más ligero.

### Publicidad — 15 redes + 1 mediador

| Red | Paquete / evidencia |
|---|---|
| **TopOn / AnyThink** (mediador) | `com.anythink.*`, `ATRewardVideoActivity`, `ATMixSplashActivity`, `mores.toponad.com`, `ssapi.mosspf.com/sdk/realtime_waterfall` |
| AppLovin MAX | `com.applovin.*`, `applovin.sdk.key`, `MaxDebugger*` (9 actividades de debug), `libapplovin-native-crash-reporter.so` |
| ironSource | `com.ironsource.*`, `TestSuiteActivity`, `www.supersonicads.com` |
| Unity Ads | `com.unity3d.services.ads.*`, `AdUnitTransparentSoftwareActivity` |
| Vungle | `com.vungle.ads.*`, `rt.applvn.com`, `a.applvn.com`, `ms.applvn.com`, `d.applvn.com` |
| Tapjoy | `com.tapjoy.*`, `libtapjoy.so` |
| StartApp | `com.startapp.sdk.*`, `SPLASH_ENABLED`, `BackgroundService`, `SchedulerService` |
| InMobi | `com.inmobi.ads.*`, `config.inmobi.com/config-server/v1/config/secure.cfg` |
| Mintegral | `com.mbridge.msdk.*`, `assets/mbridge_download_dialog_view.xml` |
| Pangle / ByteDance | `com.bytedance.sdk.openadsdk.*`, `libnms.so`, `libtt_ugen_layout.so`, `libapminsight{a,b}.so`, `libpglarmor.so`, `libtobEmbedPagEncrypt.so`, `api16-access-sg.pangle.io`, `gecko-pangle-sg.byteoversea.com` |
| Maticoo | `com.maticoo.sdk.*`, `maticoo/okhttp3/…` (¡trae su propio OkHttp rebautizado!) |
| Bigo Ads | `sg.bigo.ads.*`, `BigoAdsProvider` |
| Yandex Mobile Ads | `com.yandex.mobile.ads.*`, `MobileAdsInitializeProvider`, `adsdk.yandex.ru` |
| myTarget (VK) | `com.my.target.common.*`, `ad.mail.ru`, `target.my.com` |
| AppNext | `com.appnext.core`, `global.appnext.com/offerWallApi.aspx`, `admin.appnext.com/AdminService.asmx` |
| Chartboost | `live.chartboost.com`, `chartboo.st` |

Consentimiento: **Google UMP** (`user-messaging-platform.properties`,
`compliance.iabtechnologylab.com`, `MaxDebuggerTcfStringActivity`) y
`AnyThinkGdprAuthActivity`.

Verificación de anuncios: **OMID** (`assets/ad-viewer/omsdk-v1.js`,
`omid-session-client-v1.js`).

> **Observación:** `maticoo/okhttp3/…` es un OkHttp *repackaged* dentro del SDK de Maticoo.
> Conviven **dos** copias de OkHttp en el APK. Y `libpglarmor.so` (Pangle "armor") sugiere
> ofuscación/refuerzo en la capa nativa de ByteDance.
>
> Todas estas redes están **desactivadas por config remota** (`adsModel` todo en `"nactive"`).
> Ver `docs/07-HALLAZGOS-SEGURIDAD.md#f-10`.

### Google / Firebase / monetización

| Componente | Evidencia |
|---|---|
| Firebase Messaging (FCM) | `firebase-messaging.properties`, `MyFcmListenerService` |
| Firebase Analytics + Installations + DataTransport | `firebase-*.properties` (11 archivos) |
| **Google Play Billing** | `billing.properties`, `ProxyBillingActivity`, `com.android.vending.BILLING` |
| Google Sign-In | `play-services-auth.properties`, `play-services-auth-base` |
| **FIDO / Passkeys** | `play-services-fido.properties`, `update_passkey` |
| Play Install Referrer | `BIND_GET_INSTALL_REFERRER_SERVICE` |
| Location | `play-services-location.properties` (⚠ pero **no** se pide `ACCESS_FINE_LOCATION`) |
| Cronet | `play-services-cronet.properties` → stack de red de Chromium |
| Privacy Sandbox / AdServices | `androidx.privacysandbox.ads`, `android.ext.adservices` |
| App Indexing | `firebase-appindexing.properties` |
| Custom Tabs | `androidx.browser.customtabs.CustomTabsService` |
| AppMetrica (Yandex) | `io.appmetrica.analytics.*`, `appmetrica.io/docs/...` |

### Nativas (`lib/`)

| ABI | Bibliotecas |
|---|---|
| `arm64-v8a` | `libapminsighta.so` (97 K), `libapminsightb.so` (110 K), `libapplovin-native-crash-reporter.so` (868 K), `libbuffer.so`, `libfile_lock.so`, `libnms.so` (282 K), `libpglarmor.so` (61 K), `libtapjoy.so` (292 K), `libtobEmbedPagEncrypt.so`, `libtt_ugen_layout.so` (361 K) |
| `armeabi-v7a` | las mismas, menor tamaño |
| `x86` / `x86_64` | **solo** `libapplovin-native-crash-reporter.so` y `libtapjoy.so` |

> Las 4 ABIs son para los SDKs de ads. La app en sí es puro DEX (Java/Kotlin), así que no
> necesita nativas propias. `x86` incompleto → en emuladores x86 los ads de Pangle/Tapjoy
> fallarían al cargar. No es un bug que les importe.

### Almacenados en la raíz del APK (anomalía de empaquetado)

```
src/google/protobuf/*.proto      ← .proto FUENTE filtrados al APK (7 archivos)
google/protobuf/*.proto          ← duplicado
okhttp3/internal/publicsuffix/   ← recursos de OkHttp en ruta incorrecta
kotlin/**/*.kotlin_builtins
maticoo/okhttp3/…
org.jivesoftware.smack*/…        ← 5 directorios de recursos de Smack
assets/ad-viewer/*.js            ← OMID
assets/dexopt/baseline.prof
assets/builddatas.json           ← telemetría de Pangle (IPlayTempleView.alertShow → key 2000090…)
assets/rv_binddatas.xml
assets/dic
```

Que aparezcan `.proto` **fuente** y recursos en rutas no estándar indica un `sourceSets`/
`packagingOptions` mal configurado en Gradle. No es un riesgo, pero sí una señal de build
higiénicamente descuidado — coherente con `minSdk 16` (F-06) y el typo `MultyPlayerActivity`.

---

## 2. Generación B — PWA Flutter `web.dramalive.cc` v13.0.3 (241)

Detectado en `assets/AssetManifest.json` (42 assets) y literales de `main.dart.js`.

| Paquete | Rol |
|---|---|
| `flutter_chat_ui` | UI del chat (iconos en 1.0x/2.0x/3.0x) |
| `flutter_inappwebview` (+ `_web`) | WebView embebido — y trae el juego del dinosaurio de Chrome offline (`t_rex_runner/t-rex.html`) |
| `fluttertoast` | toasts (`toastify.css`/`.js`) |
| `wakelock_plus` | mantener pantalla encendida durante la reproducción (`no_sleep.js`) |
| `cupertino_icons` | iconografía iOS |
| **pointycastle** | AES (CBC/CCM/CMAC/CTR/EAX/ECB/GCM/GCTR/IGE/SIC), RSA (OAEP/PKCS1/PSS), HMAC, PBKDF2, HKDF, ConcatKDF, Poly1305, PKCS5S1/PKCS7/PKCS12 |
| Flutter engine | CanvasKit desde `gstatic.com/flutter-canvaskit/<engineRevision>` |

> **pointycastle es la diferencia más interesante entre generaciones.** En el APK nativo no
> hay cripto propia; en el build Flutter aparece una suite crigráfica completa. Hipótesis a
> validar con REA sobre `libapp.so`:
> - ¿cache local cifrada de la playlist/credenciales? (sería una **mejora** frente a F-02)
> - ¿firma de peticiones al backend nuevo (`fastconnections.online`)?
> - ¿descifrado de la remote config?
>
> Es la pregunta nº 1 del análisis pendiente. Ver `docs/06-FLUJO-REA.md`.

Servicios de terceros de la generación B:

| Servicio | Uso |
|---|---|
| `images.weserv.nl` | proxy de imágenes + reescalado + WebP. Con kill-switch remoto `iosImages` |
| `fgcode.store` | playlists FG Code |
| `mikkm.xyz` | proxy de activación Xtream |
| `raw.githubusercontent.com` | playlists alojadas en GitHub |
| `wa.me` / `t.me` / `twitter.com/intent` | compartir |

---

## 3. Comparativa

| | Generación A (APK) | Generación B (PWA) |
|---|---|---|
| Lenguaje | Kotlin/Java | Dart |
| Tamaño | 30,5 MB | 4,36 MB de JS (+assets) |
| Red | OkHttp (+Cronet) | `dart:io` HttpClient / `package:http` |
| Reproductor | ExoPlayer/Media3 | `video_player` / HTML5 |
| Chat | Smack (XMPP completo) | `flutter_chat_ui` |
| Cripto propia | ✗ | ✓ pointycastle |
| Ads | 15 redes (apagadas por flag) | ninguna visible |
| Pagos | Play Billing (apagado por flag) | ninguno visible |
| Backend | `*.eastgoessouth.online` (HTTP) | `main.fastconnections.online` (HTTPS) |
| Distribución | `dataflowstation.net` / `twoapistack.work` | Cloudflare + Apache/Bitnami |
| Crash | ACRA → `semprotech.online:8080` | no visible |
| Analítica | Firebase + AppMetrica | no visible |

**Lectura:** la generación B es un producto saneado. Sin ads, sin telemetría de terceros,
con cripto propia y con backend en HTTPS. Es razonable suponer que es la apuesta de futuro
(web + iOS + Android desde un único código Dart), y que el APK nativo se mantiene por la
base instalada y por los mercados donde no hay Play Store.
