# 08 · Remediación de `PelisLatino-Android` (dirección defensiva)

> **Alcance y límite.** Este documento es la contraparte accionable del hallazgo **F-11**
> (`docs/07`). Propone mejoras que **reducen daño a usuarios y riesgo legal**, o que
> **eliminan capacidad de infracción**. **No** propone ninguna mejora que haga que la
> extracción/reproducción de contenido de terceros funcione mejor: ni rutas de extracción,
> ni cripto, ni spoofing, ni empaquetado. Quien busque "que reproduzca Drama" no encontrará
> aquí cómo hacerlo, y este proyecto no lo proveerá.
>
> Análisis 100 % estático sobre el repo público. Sin ejecutar la app, sin contactar
> servicios, sin valores de credenciales/hosts (redactados).

Las mejoras están ordenadas de mayor a menor impacto. Cada una indica archivo y el cambio
concreto.

## R-01 · Purgar el material de terceros commiteado (crítico)

`app/src/test/resources/drama_glt_real.bin`, `drama_glbr_real.bin` y
`docs/vectores-clave-*.json` son **tráfico capturado y vectores de clave de un servicio
ajeno**, publicados en un repo público.

- Borrar los archivos y **purgar el historial** (`git filter-repo` o BFG); no basta un
  `git rm`, porque quedan en los objetos antiguos.
- Añadir al `.gitignore` una regla que cubra capturas y vectores
  (`*_real.bin`, `vectores-*clave*`), que hoy existe para `*.key`/`secrets.properties`
  pero **no** para estos.
- Sustituir los tests que dependen de esas capturas por fixtures sintéticos propios.

## R-02 · Dejar de exponer la sesión aprendida (crítico)

- `DramaSesion.java:~1303` guarda la semilla/sesión en `SharedPreferences` **en claro**.
  Migrar a `EncryptedSharedPreferences` (AndroidX Security) o al Keystore.
- `AndroidManifest.xml` trae `allowBackup="true"` y `res/xml/backup_rules.xml` /
  `data_extraction_rules.xml` son las **plantillas sin modificar** (todo comentado → no
  excluyen nada). O bien `allowBackup="false"`, o excluir explícitamente el fichero de
  sesión en ambas reglas.

## R-03 · Eliminar o blindar el puente WebView sobre contenido remoto (alto)

`DramaAutoActivity` carga un sitio remoto con `setJavaScriptEnabled(true)` y expone
`addJavascriptInterface(Puente, "AndroidDrama")` con `aprenderCodigo()`, `entregar()`,
`volcar()`. El JS de la página remota (o un MITM, dado R-05) puede invocar el puente nativo.

- Lo correcto es **eliminar esta pantalla de auto-extracción**: es el componente cuyo único
  fin es capturar una sesión ajena.
- Si se mantiene algún WebView legítimo: quitar `addJavascriptInterface`, fijar
  `setAllowUniversalAccessFromFileURLs(false)`, validar el origen en
  `shouldOverrideUrlLoading` y no aceptar callbacks de contenido no confiable.

## R-04 · Suprimir el canal de control por relay público (alto)

`tools/puente-ntfy.py` tunea comandos/resultados por `ntfy.sh` público cuyo único "secreto"
es un topic de 48 bits, sin auth ni ACL: cualquiera que lo conozca lee e inyecta. Es un
patrón tipo C2 sobre infraestructura de terceros.

- Eliminar el puente, o sustituirlo por un canal autenticado y autorizado por el propio
  operador (nunca un broker público anónimo).

## R-05 · Quitar el spoofing anti-hotlink y el cleartext (alto; reduce infracción)

- `tools/api-canales/server.mjs` (`CANALES_HOSTS`) y `Encabezados.java` inyectan
  `Referer`/`Origin`/`User-Agent` falsos por host para hotlinkear streams protegidos: es el
  mecanismo de elusión. **Eliminarlo** reduce capacidad de infracción, no la aumenta.
- `AndroidManifest.xml`: `usesCleartextTraffic="true"` sin `network_security_config`.
  Fijar a `false` y añadir una `network_security_config` que exija TLS.

## R-06 · Reducir superficie y riesgo legal restante (medio)

- Quitar `DebugResolverActivity` del build de release.
- Revisar `REQUEST_INSTALL_PACKAGES` + `RECEIVE_BOOT_COMPLETED` + alarmas exactas: si la
  auto-actualización fuera de tienda no es imprescindible, eliminarla.
- Corregir la licencia: el repo está bajo **OFL-1.1** (licencia de *tipografías*, válida solo
  para `LICENSE-Poppins.txt`). El código necesita una licencia propia o ser retirado.
- Subir `targetSdk` (34) al mínimo que exige Play; repasar `media3 = "1.10.1"` y quitar
  `play-services-maps3d` declarado y sin usar.
- Añadir backoff/rate-limit: su propio código documenta ráfagas de "98 req en 13 s" contra
  el backend ajeno.

## Lo que este documento NO contiene

Ninguna ruta, clave, cabecera, script o paquete que mejore la obtención o reproducción de
catálogo protegido de Drama Live, beIN, embed69, vimeus, mixdrop, dood o cualquier tercero.
Esa capacidad es el defecto de fondo del proyecto analizado, no una característica a
perfeccionar.
