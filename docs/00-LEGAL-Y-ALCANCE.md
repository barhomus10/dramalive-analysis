# Alcance, límites y avisos legales

**Última actualización:** 2026-10-20

## 1. Qué es este proyecto

Un ejercicio de **investigación y documentación técnica** sobre una aplicación Android/PWA
de terceros (Drama Live), más una **implementación independiente** de un reproductor con
arquitectura equivalente.

## 2. Qué se analizó y cómo

Solo se usó material **servido públicamente y sin autenticación** por
`https://web.dramalive.cc/`:

- `index.html`, `manifest.json`, `version.json`, `flutter_bootstrap.js`, `assets/AssetManifest.json`
- `main.dart.js` — el bundle JavaScript que el propio servidor entrega a cualquier navegador.

No se realizó: fuzzing, fuerza bruta, bypass de autenticación, explotación de vulnerabilidades,
ingeniería social, ni peticiones masivas. Las peticiones fueron un puñado de `GET` de lectura.

El análisis del **APK** (cuando el propietario del repo lo aporte) se documentará en
`docs/06-FLUJO-REA.md` y se ejecutará con [REA](https://github.com/morluto/rea) en local,
sin interactuar con servidores de terceros más allá de lo estrictamente necesario y autorizado.

## 3. Riesgos legales que debes conocer

El modelo de negocio detectado (agregador IPTV con fuentes aportadas por el usuario) vive en
una zona con riesgos reales. Antes de seguir:

| Riesgo | Detalle |
|---|---|
| **Términos de servicio** | La ingeniería inversa suele estar prohibida expresamente en los ToS. Verifica los de Drama Live (`http://dramalive.tv/privacy/index.html` y sus términos) antes de continuar. |
| **Propiedad intelectual** | El código, el branding, los textos localizados y el catálogo son de sus autores. Este repo **no** los redistribuye. |
| **DMCA §1201 / anti-elusión** | Eludir medidas tecnológicas de protección (DRM, firmado de peticiones, tokenización) es ilegal en muchas jurisdicciones **aunque** el fin sea interoperabilidad. Este proyecto no lo hace ni documenta cómo hacerlo. |
| **Contenido no licenciado** | Gran parte del ecosistema IPTV redistribuye canales de pago sin licencia. **Consumir o redistribuir ese contenido puede ser ilícito** en tu país. Este repo no apunta a ninguna fuente de ese tipo. |
| **Datos personales** | Si en algún momento capturas tráfico, puedes estar capturando credenciales de usuarios. `analysis/evidence/` **no** debe contener nunca credenciales reales, tokens ni datos personales. Ver §5. |
| **Publicación** | El repo está pensado como **público**. Un informe de RE que revele debilidades explotables de un servicio de terceros puede generar responsabilidad. Revisa `docs/01-RECON-WEB.md` antes de publicar y elimina lo que no deba salir. |

> Esto es información general, **no asesoría legal**. Si el proyecto tiene uso comercial o
> vas a publicarlo, consúltalo con un abogado de tu jurisdicción (Perú: Ley 30074 — Ley de
> delitos informáticos, y Decisión 351 de la CAN sobre derechos de autor).

## 4. Reglas duras del repo

Cosas que **no** se hacen aquí, y si aparecen en un PR se rechazan:

1. No se usa la infraestructura de terceros (`main.fastconnections.online`, `mikkm.xyz`,
   `fgcode.store`, `dramalive.tv`) como fuente de contenido ni se somete a carga.
2. No se eluden autenticación, firmas, DRM, rate limits ni geobloqueo.
3. No se redistribuyen streams, EPG, iconos, textos localizados ni binarios de Drama Live.
4. No se publican vulnerabilidades explotables sin antes practicar **divulgación responsable**
   (aviso al titular + plazo razonable de 90 días).
5. No se almacenan credenciales reales de ningún panel en el repo.

## 5. Saneado de evidencia

Antes de cada commit que toque `analysis/`:

```bash
make sanitize      # escanea evidencia y artefactos en busca de secretos/datos personales
```

El script revisa patrones de: `password=`, `token`, `Authorization:`, `user_info`, correos,
números de tarjeta y claves privadas. **Bloquea el commit** si encuentra algo (hook de
pre-commit en `.git/hooks/pre-commit`, instalado por `make hooks`).

Los binarios de terceros (`main.dart.js`, APKs, `.so`) **no se versionan**: están en
`.gitignore`. Si necesitas conservarlos, usa Git LFS en un repo **privado**.

## 6. Uso legítimo previsto

- Aprender arquitectura de apps Flutter híbridas (PWA + APK desde el mismo código).
- Entender los formatos IPTV abiertos: **M3U/M3U8**, **Xtream Codes API**, **XMLTV/EPG**, **FG Code**.
- Construir **tu propio** reproductor para **tus propias** listas con licencia.
- Auditar una app **de tu propiedad** o con **autorización escrita** del titular.

Si tu caso es otro, este repo probablemente no sea la herramienta adecuada.
