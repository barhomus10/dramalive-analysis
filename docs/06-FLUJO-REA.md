# 06 — Flujo de trabajo con REA

Cómo usar [REA](https://github.com/morluto/rea) (*Reverse engineer anything with agents*)
sobre el APK de Drama Live, y qué se espera obtener.

---

## 1. Por qué REA y no solo `jadx`

El triage estático básico (este repo, `analysis/scripts/apk_triage.sh`) ya dio el mapa de
**hosts**: la config remota embebida en `classes.dex` es un JSON en claro con todos los
servidores. Eso se resuelve con `unzip` + un parser AXML + literales del DEX.

Lo que **no** da ese triage es el **protocolo**: qué paths concretos cuelgan de
`http://main.eastgoessouth.online/api/live/livedrama/v13.0.0/`, qué cabeceras se envían,
qué esquema JSON se espera. Esas rutas **no existen como literales** — se construyen por
concatenación en runtime. Recuperarlas exige seguir el flujo de datos a través de
8 DEX y ~58 MB de código descompilado, que es exactamente el trabajo tedioso y de gran
superficie donde un agente rinde más que un humano con `jadx-gui`.

REA aporta además Ghidra para la capa nativa (`libnms.so`, `libpglarmor.so`,
`libtobEmbedPagEncrypt.so` de Pangle/ByteDance), aunque en este APK las nativas pertenecen
todas a SDKs publicitarios: **la lógica de la app es 100 % DEX**, así que el análisis nativo
es secundario.

## 2. Estado del entorno

| Herramienta | Estado | Para qué |
|---|---|---|
| `unzip` | ✓ | descomponer el APK |
| `java` | ✓ | requerido por apktool/jadx |
| `python3` + `androguard 4.1.4` | ✓ | manifiesto AXML, certificado, DEX |
| `apktool` | ✗ instalar | recursos + smali legible |
| `jadx` | ✗ instalar | descompilar DEX → Java |
| `aapt2` | ✗ instalar | dump del manifiesto como segunda opinión |

```bash
# Debian/Ubuntu
sudo apt install -y apktool unzip default-jdk
# jadx: descarga el release desde github.com/skylot/jadx/releases y ponlo en PATH
curl -sL https://github.com/skylot/jadx/releases/latest/download/jadx-1.5.1.zip -o /tmp/jadx.zip
unzip -q /tmp/jadx.zip -d ~/.local/jadx && ln -sf ~/.local/jadx/bin/jadx ~/.local/bin/jadx
```

> ⚠️ Con `minSdk 16` y 8 DEX, `jadx` tardará y puede agotar heap. Arráncalo con
> `JAVA_OPTS="-Xmx8g"` y usa `--no-res --no-debug-info` para la primera pasada.

## 3. Procedimiento

```bash
# 0. el APK en su sitio (no se versiona)
cp /descargas/dramalive.apk artifacts/apk/

# 1. triage — identidad, manifiesto, firma, literales de red, config embebida
analysis/scripts/apk_triage.sh artifacts/apk/dramalive.apk
#    → analysis/evidence/apk-dramalive/{00..04}-*

# 2. descompilación gruesa (manual, no la hace el script)
apktool d -f -o /tmp/apktool artifacts/apk/dramalive.apk
jadx --no-res --no-debug-info -d /tmp/jadx artifacts/apk/dramalive.apk

# 3. sesión de REA
#    arranca REA apuntando al repo, y pega analysis/rea/REA-TASK.md como tarea.
#    REA leerá analysis/rea/rea.config.json para objetivos, límites y formato.

# 4. verificar que la salida no filtra nada antes de commitear
make sanitize
git status
```

## 4. Qué se espera obtener

Siete entregables, definidos en `analysis/rea/rea.config.json`:

| # | Entregable | Pregunta clave |
|---|---|---|
| 1 | `05-CLIENTE-HTTP.md` | los **paths** y el esquema JSON del backend propio |
| 2 | `06-REMOTE-CONFIG.md` | semántica de los flags y frecuencia de refresco |
| 3 | `07-BANNED-APPS.md` | cómo funciona el control de canal sobre 25 clones |
| 4 | `08-AUTOUPDATE.md` | cómo se verifica el APK descargado antes de instalarlo |
| 5 | `09-CHAT-XMPP.md` | JID, SASL, STARTTLS y persistencia del chat |
| 6 | `10-CRIPTO.md` | si las credenciales del usuario se cifran en reposo |
| 7 | `11-BACKGROUND.md` | servicios, `BOOT_COMPLETED`, `REQUEST_DELETE_PACKAGES` |

El nº 1 es el que desbloquea todo lo demás y el único marcado como `critical`.

## 5. Restricciones de la sesión

Las mismas de `docs/00-LEGAL-Y-ALCANCE.md` §4, reforzadas en `rea.config.json`:

- **Solo estático.** No se ejecuta la app, ni en emulador ni en dispositivo.
- **Cero tráfico** hacia los hosts del objetivo. `forbidden_hosts` lista 14 patrones.
  El objetivo es leer código, no sondear un servicio de terceros.
- **No usar las credenciales embebidas** para nada.
- **Redactar** en toda salida: credenciales, tokens, IPs de infraestructura, correos,
  datos personales. Los dominios públicos sí.
- Si aparece una vulnerabilidad explotable: describir mecanismo e impacto, **sin PoC
  funcional**, y marcarla para divulgación responsable.

## 6. Validación de los resultados

Cada hallazgo de REA debe llevar clase+método, fragmento descompilado, DEX y offset, y un
nivel de confianza. Antes de dar por bueno un hallazgo `confirmed`:

```bash
# ¿el fragmento existe de verdad en el binario?
grep -rn "<cadena distintiva>" /tmp/jadx/sources/com/sneig/

# ¿la clase existe en el manifiesto / en el DEX?
python3 - <<'PY'
from androguard.core.apk import APK
a = APK('artifacts/apk/dramalive.apk')
print([x for x in a.get_activities() if 'NOMBRE' in x])
PY
```

Los hallazgos que no pasen esa comprobación se degradan a `inferred` o se descartan.
Nada entra en `docs/` sin verificar.

## 7. Lo que ya se ha respondido sin REA

Para no duplicar trabajo:

| Pregunta | Respuesta | Dónde |
|---|---|---|
| ¿Qué framework es? | La web es Flutter; **el APK es Kotlin/Java nativo** — son dos generaciones | `docs/02` §1 |
| ¿Qué backend usa? | `*.eastgoessouth.online` (APK) / `main.fastconnections.online` (web) | `docs/01` §5, `docs/02` §2 |
| ¿De dónde sale el contenido? | De la fuente que aporta el usuario: Xtream / M3U / FG / GitHub | `docs/04` |
| ¿Qué SDKs lleva? | 15 redes de ads + TopOn, Smack, ExoPlayer, Firebase, Billing, ACRA… | `docs/03` |
| ¿Hay credenciales en el binario? | Sí, del colector de crashes | `docs/07` F-01 |
| ¿HTTP o HTTPS? | HTTP plano en todo el backend | `docs/07` F-02 |
| ¿Quién lo firma? | `CN=Sneig, O=Sneig`, autofirmado 2020→2119 | `docs/07` F-07 |
