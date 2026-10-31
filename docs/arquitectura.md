> Describe la Cuadrilla v1 (etiqueta `cuadrilla-v1`). La versión actual, una sola orden sin procesos residentes, está en `cuadrilla-ligera.md` y D-003.

# Arquitectura de Cuadrilla

Cuadrilla coordina en un mismo PC con Windows a tres agentes de línea de comandos: **Claude Code** (`claude`), **Codex CLI** (`codex`) y **Antigravity** (`agy`). No hay servidor, base de datos ni servicio externo: todo es PowerShell 5.1 y archivos JSON en disco. Cada agente lee y escribe esos archivos con `herramientas\mesa.ps1`, y varios procesos pequeños (supervisor, vigía, panel web) los observan.

Este documento describe cómo funciona hoy. Conviene leerlo con `CLAUDE.md` (el protocolo que siguen los agentes) al lado.

## 1. Idea en cinco líneas

- La **persona** da una tarea a un agente. Si no hay hilo abierto sobre ella, ese agente es el **líder**: abre un *hilo*, reparte el trabajo y revisa las entregas.
- Un **hilo** es una carpeta con mensajes numerados (`0001-claude.json`, `0002-codex.json`…). Es el único canal entre agentes.
- Un **reclamo** es un archivo que dice «esta tarea es mía y toco estos archivos». Se crea de forma atómica: dos agentes no pueden reclamar lo mismo.
- Un **encargo** es un mensaje que el líder envía a otro agente; `ejecutar.ps1` lo convierte en una llamada real al CLI de ese agente.
- Un **supervisor** sin modelo vigila que los procesos sigan vivos, marca el estado de cada agente y avisa.

## 2. Carpetas y archivos

### Raíz

| Archivo | Para qué sirve |
|---|---|
| `Cuadrilla.bat` | Lanzador: comprueba requisitos, prepara la instalación, arranca supervisor y panel web, y abre Windows Terminal con Claude, Codex, agy y el tablero. Subcomandos: `nuevo`, `panel <agente>`, `diagnostico`, `pruebas`, `cerrar`, `prueba`. |
| `Probar.bat` | Ejecuta las cuatro suites de `pruebas\` con agentes simulados. |
| `plantillas\protocolo.md` | Plantilla del protocolo; `instalar.ps1` genera de ella `CLAUDE.md`, `AGENTS.md` y `GEMINI.md` (no se versionan). |
| `.claude\settings.json` | Hooks de Claude Code (sección 4). |
| `README.md`, `LICENSE`, `LICENCIAS.md` | Presentación y licencias. |

### `herramientas\`

| Archivo | Para qué sirve |
|---|---|
| `comun.ps1` | Biblioteca común: rutas, variables de entorno, lectura/escritura segura de JSON, candados, reclamos, entregas, normalización de nombres de agente, tipo de encargo y causa de un fallo. |
| `mesa.ps1` | CLI principal. Subcomandos: `abrir`, `enviar`, `leer`, `hilos`, `pendientes`, `lider`, `sugerir-lider`, `aprobar`, `rechazar`, `reclamar`, `reclamos`, `soltar`, `avance`, `entregar`, `revisar`, `entregas`, `tareas`, `archivar`, `reintentar`, `cortar`, `limpiar`, `diagnostico`, `bitacora`, `cuota`, `llamadas`, `foto`, `actividad`, `alertas`. |
| `delegar.ps1` | Atajo del líder: abre el hilo si falta, crea el encargo, lo autoaprueba si procede y lo lanza o lo deja en la cola del panel del agente. |
| `ejecutar.ps1` | Ejecuta un encargo aprobado llamando al CLI de `claude`, `codex` o `agy`; guarda el log, la respuesta y el resultado. |
| `trabajador.ps1` | Panel de un agente en Windows Terminal: atiende su cola, deja un latido, reenvía lo que escribe la persona y vigila el relevo de líder. |
| `esperar-novedades.ps1` | Bloquea hasta que llegue algo para un agente interactivo y lo imprime. |
| `hook-claude.ps1` | Hook de Claude Code: le muestra las novedades al empezar sesión y al recibir cada mensaje. |
| `supervisor.ps1` | Supervisor de salud (sección 7). |
| `vigia.ps1` | Observador de seguridad: registra comandos y escrituras de los agentes y levanta alertas (por ejemplo, salidas del ámbito de trabajo). No ejecuta nada ni cambia permisos. |
| `worktrees.ps1` | Crea, lista y limpia un worktree de git por agente y tarea. |
| `tablero.ps1` | Monitor de consola (4 secciones, solo lectura). |
| `cuota.ps1`, `costes.ps1`, `observatorio.ps1`, `tokens-calibrador.ps1`, `medir-claude.ps1` | Medición de cuota y tokens a partir de los metadatos de las sesiones locales (nunca del contenido de los mensajes). |
| `instalar.ps1` | Crea la configuración propia y los archivos de instrucciones si faltan. Idempotente. |
| `abrir-claude.cmd` | Abre Claude Code reanudando la conversación de la mesa. |
| `mcp` | Servidor MCP por stdio para la app de escritorio de Claude: ocho herramientas que llaman a `mesa.ps1` con autor `claude-app` (D-002). |

### `panel\` (oficina web local)

| Archivo | Para qué sirve |
|---|---|
| `servidor.ps1` | Servidor HTTP mínimo solo en `127.0.0.1` (puerto desde 8790). Genera un token aleatorio por arranque en `token.txt`; `/api/*` exige token y `Origin`/`Referer` locales. Responde con `ETag`/304. |
| `estado.ps1` | Calcula el estado completo de la mesa y lo deja en `datos\estado-panel.json`; un trabajador en segundo plano lo refresca cada pocos segundos. |
| `index.html`, `oficina.js`, `oficina.css`, `arte-v1.js`, `reclamos.js` | Interfaz: una oficina con un despacho por agente, corcho de reclamos, hilos y entregas. |
| `puerto.txt`, `token.txt` | Puerto y token del arranque actual (no se versionan). |

Endpoints: `GET /api/ping` (sin token), `GET /api/estado` y `GET /api/hilo?id=<hilo>`.

### `pruebas\`

| Archivo | Qué comprueba |
|---|---|
| `caos.ps1` | Casos de fallo (procesos muertos, candados, carreras, cortes) en una mesa temporal con agentes simulados. |
| `probar-relevo.ps1` | El relevo de líder de `trabajador.ps1`. |
| `probar-vigia-ambito.ps1` | Las reglas de ámbito del vigía. |
| `probar-oficina.ps1` | Reglas del vigía y estado del panel. |

Todas trabajan en copias bajo `%TEMP%` (con `MESA_DATOS`) y no gastan cuota.

### `datos\` (estado vivo; casi todo fuera de git)

| Ruta | Contenido |
|---|---|
| `mesa.json` | Configuración propia (si falta, se usa `mesa.ejemplo.json`). |
| `mesa.ejemplo.json` | Configuración de ejemplo, versionada. |
| `excluidos.txt` | Una expresión regular por línea: ámbitos que ningún agente toca ni se muestran. |
| `hilos\<id>\` | Un hilo: `hilo.json`, mensajes `NNNN-<autor>.json`, `entregas\`, `logs\`, y a veces `claims\` y `relevo-<agente>.md`. |
| `reclamos\<tarea>.json` | Reclamos globales; `relevo-<hilo>.lock` evita dos relevos del mismo hilo. |
| `agentes\<agente>.json` | Estado de cada agente, escrito por el supervisor. |
| `agentes\en-curso-<pid>.json` | Qué encargo corre en ese proceso. |
| `agentes\supervisor.latido`, `agentes\claude-visto.txt` | Último pulso del supervisor; hasta cuándo ha visto novedades Claude. |
| `trabajador-<agente>.latido` | Pulso del panel de cada agente. |
| `sesion-<agente>.txt` | Id de la última conversación, para reanudarla. |
| `bitacora\AAAA-MM-DD.md` | Diario del supervisor. |
| `worktrees.json` | Worktrees de la mesa, para el tablero (el supervisor lo refresca cada 5 min). |
| `supervisor-estado.json` | Memoria del supervisor: avisos ya dados y relanzamientos. |
| `actividad.jsonl`, `alertas.jsonl`, `alertas-revisadas.json`, `vigia-estado.json` | Salida del vigía. |
| `registro-tokens.jsonl`, `aprobaciones.log`, `cuota-*.json(l)` | Consumo, aprobaciones y cuota. |
| `estado-panel.json` | Caché del panel web. |
| `personajes.json`, `despachos\<agente>.json` | Aspecto de los personajes y los despachos de la oficina. |
| `errores-paneles.log` | Errores de paneles y supervisor. |
| `archivo\` | Lo que `limpiar` y la rotación mueven (nada se borra). |
| `*.lock` | Candados entre procesos. |

`actividad.jsonl` y `alertas.jsonl` se rotan a `archivo\` al pasar de 5 MB y 2 MB; `errores-paneles.log`, de 1 MB.

## 3. Formato de los archivos de `datos\`

Todos son JSON en UTF-8 sin BOM, salvo los `.jsonl` (una línea por registro), los `.latido` y los `.log`. Los ejemplos están inventados.

### 3.1 Hilo: `hilos\20261020-informe-ventas\hilo.json`

```json
{
  "id": "20261020-informe-ventas",
  "titulo": "Informe de ventas",
  "estado": "abierto",
  "lider": "claude",
  "participantes": ["claude", "codex", "agy"],
  "creado": "2026-10-20T09:00:00-05:00",
  "actualizado": "2026-10-20T09:40:12-05:00",
  "tareas": ["limpiar-datos"]
}
```

`estado` es `abierto` o `cerrado`. **El campo `lider` es la única fuente del liderazgo.** `limpiar` mueve a `archivo\hilos` los hilos cerrados hace más de 30 días.

### 3.2 Mensaje: `hilos\<id>\0003-claude.json`

Todos los mensajes comparten forma; cambia `tipo` (`encargo`, `respuesta`, `nota`, `entrega`, `revision`, `lider`, `avance-inicio`, `avance-hito`, `avance-alcance`, `avance-bloqueo`). Los avances añaden el campo `tarea`.

```json
{
  "n": 3,
  "autor": "claude",
  "para": "codex",
  "herramienta": "codex",
  "modelo": "gpt-6-astra",
  "fecha": "2026-10-20T09:05:30-05:00",
  "tipo": "encargo",
  "texto": "Delegación a codex (gpt-6-astra): encargo-limpiar-datos.md",
  "encargo": "C:\\proyectos\\ventas\\encargo-limpiar-datos.md",
  "dir": "C:\\proyectos\\ventas",
  "estado": "ejecutando",
  "traspaso": { "hecho": "autoaprobado (repo)", "falta": "", "archivos": ["C:\\proyectos\\ventas\\encargo-limpiar-datos.md"] },
  "llamada": {
    "inicio": "2026-10-20T09:05:41-05:00",
    "fin": null,
    "salida": null,
    "log": "C:\\...\\hilos\\20261020-informe-ventas\\logs\\0003-codex.log",
    "pid": 14820,
    "intento": "a1b2c3d4e5f6",
    "causa": null,
    "hasta": null
  },
  "intentos": 1,
  "cola": true
}
```

- `estado` de un encargo: `pendiente` (espera a la persona), `aprobado`, `ejecutando`, `hecho`, `fallo`, `huerfano`, `escalado`, `rechazado`. Notas, avances y entregas nacen `hecho`.
- `llamada.pid` y `llamada.intento` identifican el proceso y el intento concretos; `causa` (`sin-cuota`, `necesita-login`, `red`) y `hasta` los rellena `ejecutar.ps1` si el CLI falló por esa razón.
- `cola: true` lo pone `delegar.ps1 -Visible` para que el panel del agente lo recoja. `intentos` aparece tras un `reintentar`.
- El número se asigna bajo candado del hilo, así dos mensajes simultáneos nunca comparten número.

Ejemplo de avance:

```json
{ "n": 4, "autor": "codex", "para": "claude", "tarea": "limpiar-datos", "tipo": "avance-inicio",
  "texto": "[INICIO] limpiar-datos (archivos: ventas\\datos\\*.csv): normalizar fechas y quitar duplicados.\n[git C:\\proyectos\\ventas]\n## main",
  "estado": "hecho", "fecha": "2026-10-20T09:06:10-05:00" }
```

El punto de control añade el estado de git del directorio de trabajo del agente.

### 3.3 Reclamo: `reclamos\limpiar-datos.json`

```json
{"tarea":"limpiar-datos","agente":"codex","fecha":"2026-10-20T09:05:50-05:00","hilo":"20261020-informe-ventas","toca":"ventas\\datos\\*.csv"}
```

Se crea con `CreateNew` (atómico en NTFS). Un agente solo puede tener **una** tarea reclamada a la vez (los reclamos `archivo-*` no cuentan). Se suelta con `soltar` o al aceptarse la entrega. `reclamos\LEEME.md` lo resume.

### 3.4 Entrega: `hilos\<id>\entregas\limpiar-datos.json`

```json
{
  "hilo": "20261020-informe-ventas",
  "tarea": "limpiar-datos",
  "autor": "codex",
  "estado": "aceptada",
  "fecha": "2026-10-20T09:30:00-05:00",
  "ronda": 1,
  "resumen": "Normalizadas las fechas de 12 archivos; 340 duplicados eliminados.",
  "pruebas": "Script de validación: 12/12 archivos sin fechas inválidas.",
  "pendientes": "",
  "archivos": ["ventas\\datos\\2026-09.csv"],
  "revisor": "claude",
  "motivo": "Revisado el diff y la validación.",
  "revisado": "2026-10-20T09:38:00-05:00",
  "archivada": null
}
```

`estado`: `entregada` → `aceptada` | `devuelta` → (nueva ronda) → `archivada`. Las entregas nunca se borran. Entregar exige un `avance-inicio` previo de esa tarea (sin él, el comando falla: «entrega sorpresa»).

### 3.5 Agente: `agentes\codex.json`

```json
{
  "agente": "codex",
  "estado": "trabajando",
  "motivo": "encargo #3 desde 2026-10-20T09:05:41-05:00",
  "hilo": "20261020-informe-ventas",
  "n": 3,
  "latido": "2026-10-20T09:20:02-05:00",
  "actualizado": "2026-10-20T09:20:30-05:00",
  "hasta": null
}
```

`estado`: `libre`, `trabajando`, `colgado`, `caido`, `sin-cuota`, `necesita-login`. `hasta` solo se usa con `sin-cuota`.

### 3.6 Encargo en curso: `agentes\en-curso-14820.json`

```json
{ "hilo": "20261020-informe-ventas", "n": 3, "intento": "a1b2c3d4e5f6", "inicio": "2026-10-20T09:05:41-05:00" }
```

El nombre lleva el pid del proceso que ejecuta. `mesa.ps1 cortar` solo mata el CLI si hilo, número e intento coinciden con este archivo; así no corta el encargo siguiente de un panel que ya pasó a otro.

### 3.7 Worktrees: `worktrees.json`

```json
[
  { "repo": "C:\\proyectos\\ventas", "ruta": "C:\\proyectos\\ventas\\.claude\\worktrees\\codex-limpiar-datos",
    "rama": "codex/limpiar-datos", "agente": "codex", "tarea": "limpiar-datos", "sin_confirmar": 2, "integrada": false }
]
```

### 3.8 Bitácora: `bitacora\2026-10-20.md`

```
- 09:20 · codex pasa de libre a trabajando: encargo #3 desde 2026-10-20T09:05:41-05:00.
- 09:41 · Qué pasó: el encargo 20261020-informe-ventas#5 de agy quedó huérfano: su proceso ya no existe (empezó hace 2 h) · Qué hice: lo marqué como huérfano; su reclamo y sus puntos de control siguen en el hilo · Qué necesito: que el líder lo relance con: mesa.ps1 reintentar -Hilo 20261020-informe-ventas -N 5 -De <líder>
```

Los avisos del supervisor siempre tienen tres partes: qué pasó, qué hizo el sistema y qué necesita de la persona.

### 3.9 Configuración: `mesa.ejemplo.json`

| Clave | Significado |
|---|---|
| `humano` | Nombre de quien dirige la mesa en los hilos (por defecto `usuario`). |
| `topes` | Llamadas máximas por hora y por día de cada agente. |
| `autoaprobar` | Agentes cuyos encargos pueden aprobarse solos. |
| `aprobacion` | `modo` (`por-tipo`, `todo`, `nada`) y `autoaprobados` (tipos que no esperan a la persona). |
| `limites` | Minutos máximos de un encargo y de una charla. |
| `modelos` | Modelos disponibles por agente; el primero es el predeterminado. |
| `supervisor` | `relanzar`, `max_relanzar`, `ventana_min`, `colgado_min`, `reclamo_min`, `latido_seg`, `max_intentos`. |
| `worktrees` | `max_por_agente` (3). |
| `coste_semilla`, `claude_proyectos` | Parámetros de la estimación de cuota. |

### 3.10 Otros

- `actividad.jsonl`: `{"agente":"codex","modelo":"gpt-6-astra","hora":"2026-10-20T14:21:05Z","tipo":"comando","valor":"git status","herramienta":"exec_command","operacion":"ejecucion"}`.
- `alertas.jsonl`: lo mismo más `id`, `nivel` (`medio`/`alto`) y `motivo`.
- `aprobaciones.log` (TSV): `fecha<TAB>APROBADO<TAB>hilo=…<TAB>n=3<TAB>de=claude<TAB>para=codex<TAB>modelo=…<TAB>motivo=autoaprobado`.
- `trabajador-<agente>.latido`: una fecha ISO, `2026-10-20T09:20:02-05:00`.

## 4. Cómo se entera cada CLI de que hay trabajo

Hay tres mecanismos; ninguno usa las ventanas de otro programa ni simula teclas.

1. **Hooks de Claude Code.** `.claude\settings.json` registra `hook-claude.ps1` en `SessionStart` (`-Evento inicio`) y `UserPromptSubmit` (`-Evento mensaje`). El hook imprime las novedades para `claude` (mensajes dirigidos a él o a `todos`, y los `avance-inicio/alcance/bloqueo` y cambios de líder de los demás) desde la última vez que las vio (`agentes\claude-visto.txt`), más sus reclamos. Al iniciar guarda el id de sesión en `sesion-claude.txt` para que `abrir-claude.cmd` reanude esa conversación. Cualquier fallo sale en silencio con código 0: un hook roto nunca bloquea a Claude.
2. **Paneles `trabajador.ps1 -Agente <a>`.** Cada 3 s el panel busca un encargo `aprobado` con `cola: true` para su agente, lo ejecuta a la vista con `ejecutar.ps1 -Ver` y mantiene un latido. Mientras espera, lo que escribe la persona se envía como charla (hilo `charla-<agente>`) continuando la última conversación. Un fallo en una vuelta se anota en `errores-paneles.log` y el panel sigue.
3. **`esperar-novedades.ps1 -Para <a>`.** Para sesiones interactivas sin hooks (Codex, agy): se deja en segundo plano, comprueba cada 15 s (hasta 55 min) y sale imprimiendo las novedades; el agente las atiende y lo relanza.

Cuando se delega con `-Visible` y el panel del agente tiene latido de menos de 30 s, el encargo va a su cola. Si no, se avisa y se lanza oculto con `ejecutar.ps1`.

## 5. Líder y reparto de una tarea

### Quién lidera

El líder de un hilo vive solo en `hilo.json` (`lider`). `mesa.ps1 lider -Hilo <id> -Nuevo <agente>` lo cambia y deja un mensaje `lider`. Solo el líder (o la persona) puede lanzar encargos, aprobar y revisar; si otro agente escribe a un tercero, el mensaje se degrada a nota. Antes de actuar sobre cualquier petición, un agente mira `pendientes` e `hilos`: si ya hay un líder sobre lo mismo, avisa en ese hilo y espera su reparto.

**Relevo.** Cada minuto, el panel de cada agente comprueba si un hilo abierto tiene una `entrega` o un `avance-bloqueo` sin respuesta del líder desde hace 15 min (y menos de un día) y si el líder no ha dado señal de vida en `actividad.jsonl` en ese tiempo. Si es así, crea `reclamos\relevo-<hilo>.lock` (atómico, gana el primero), se nombra líder y se encarga a sí mismo, con tipo `relevo`, la lectura del hilo y la revisión de lo pendiente.

### Ejemplo de principio a fin

La persona le pide a `claude`: «prepara el informe de ventas de septiembre».

1. `claude` ve que no hay hilo abierto sobre eso y abre uno:
   `mesa.ps1 abrir -Titulo "Informe de ventas" -Lider claude -Participantes "claude,codex,agy"`.
2. Reclama su parte (`mesa.ps1 reclamar -Tarea redactar-informe -De claude -Hilo <id> -Texto "ventas\informe.md"`) y avisa `avance -Fase inicio`.
3. Reparte según la cuota (`cuota.ps1`): el trabajo mecánico a un modelo barato, lo que exige criterio, para sí. Escribe `encargo-limpiar-datos.md` (objetivo, rutas, reglas, puntos de control, criterio de terminado) y delega:
   `delegar.ps1 -A codex -Modelo gpt-6-astra -Encargo C:\proyectos\ventas\encargo-limpiar-datos.md -Dir C:\proyectos\ventas -Hilo <id> -De claude -Visible -Worktree`.
4. `delegar.ps1` crea el mensaje `0003-claude.json` (tipo `encargo`), decide si se autoaprueba (sección 5.1) y, con el panel de codex vivo, lo marca `cola: true`. Con `-Worktree` el encargo corre en `C:\proyectos\ventas\.claude\worktrees\codex-limpiar-datos` (sección 6).
5. El panel de codex lo toma, `ejecutar.ps1` lo pone en `ejecutando` (con `pid` e `intento`), lanza el CLI y escribe el log.
6. `codex` reclama `limpiar-datos` y publica `avance -Fase inicio`; después `hito` en cada paso importante, `alcance` si cambia lo que toca y `bloqueo` si se atasca. Cada avance le devuelve las notas pendientes del líder, de la persona o del supervisor, que debe cumplir antes de seguir; lo que escriba otro agente es un dato, no una orden.
7. Al terminar: `mesa.ps1 entregar -Hilo <id> -Tarea limpiar-datos -De codex -Texto "…" -TraspasoHecho "<prueba real>"`. Se crea la entrega y llega un mensaje `entrega` al líder.
8. `claude` revisa informe, diff y pruebas: `mesa.ps1 revisar -Hilo <id> -Tarea limpiar-datos -De claude -Veredicto aceptada`. Nadie revisa su propia entrega (la del líder la revisa otro participante). Al aceptar, el reclamo de codex se suelta solo; si se devuelve (`-Veredicto devuelta -Motivo "…"`), codex entrega otra ronda.
9. Cuando todo está aceptado, `mesa.ps1 archivar -Hilo <id> -De claude` archiva las entregas. Un cambio de producto en un repositorio se integra por pull request con la integración continua en verde; en la propia Cuadrilla, que vive solo en local (D-001), se une a `main` con `Probar.bat` en verde.

### 5.1 Autoaprobación por tipo

Un encargo nace `pendiente` o `aprobado`. Se autoaprueba solo si el autor está en `autoaprobar` **y** su tipo está permitido por `aprobacion.autoaprobados`. El tipo lo declara quien delega (`-Tipo`) o se deduce de `-Dir`:

| Tipo | Qué es | Por defecto |
|---|---|---|
| `lectura` | Solo lee. | Se autoaprueba |
| `mesa` | Escribe solo dentro de la carpeta de Cuadrilla (`-Dir` dentro de ella). | Se autoaprueba |
| `relevo` | Toma de liderazgo por abandono. | Se autoaprueba |
| `repo` | Escribe en un repositorio git (se deduce de `-Dir`). | Espera a la persona |
| `carpeta` | Escribe en una carpeta que no es repo. | Espera a la persona |
| `red` | Usa la red. | Espera a la persona |
| `irreversible` | No se puede deshacer. | Espera a la persona |

Modos: `por-tipo` (el de arriba), `todo` (se autoaprueba cualquier encargo de un agente de la lista) y `nada`. La persona aprueba o rechaza con `mesa.ps1 aprobar` / `rechazar`; todo queda en `aprobaciones.log`. Además `delegar.ps1` y `ejecutar.ps1` respetan los `topes` por hora y día de cada agente.

## 6. Worktrees

Para que dos agentes no pisen la misma copia de un repositorio, `worktrees.ps1 crear` da a cada agente y tarea su propio worktree:

- Ruta `<repo>\.claude\worktrees\<agente>-<tarea>`, rama `<agente>/<tarea>`, creada desde la rama principal tras un `git fetch`.
- `.claude/worktrees/` se añade a `.git/info/exclude`, sin tocar el `.gitignore` del repo.
- Tope `worktrees.max_por_agente` (3) de vivos por agente; si se supera, falla y pide integrar o limpiar.
- `delegar.ps1 -Worktree` lo usa solo si `-Dir` es un repositorio; si no, avisa y trabaja con reclamos.
- `lista [-Json]` los enumera con cambios sin confirmar y si están integrados; el supervisor mantiene `worktrees.json` para el tablero.
- `limpiar` quita solo los que están integrados, limpios y sin tarea reclamada; con trabajo pendiente decide la persona. Nunca borra trabajo.

## 7. Supervisor, estados y reintentos

`supervisor.ps1` (sin modelo, una sola instancia por candado `supervisor.lock`) da una vuelta cada 30 s y escribe `agentes\<agente>.json`. Estados:

| Estado | Cuándo |
|---|---|
| `libre` | Sin encargo en curso. |
| `trabajando` | Tiene un encargo `ejecutando` con proceso vivo. |
| `colgado` | Proceso vivo, pero sin salida nueva en el log en `colgado_min` minutos (o «waiting for network» más de 10 min). Se avisa al líder; no se mata nada. |
| `caido` | Está libre, pero no hay proceso de `claude`, o el panel de codex/agy lleva más de `latido_seg` sin latido. Si `relanzar` está activo, reabre el panel hasta `max_relanzar` veces por `ventana_min` minutos; si no, avisa. |
| `sin-cuota` | El último encargo falló por cuota y aún no ha llegado `hasta`. No es una caída: se pide al líder que reasigne. |
| `necesita-login` | El último encargo falló por sesión caducada (menos de 12 h). |

Además:

- **Huérfanos.** Un encargo `ejecutando` cuyo `pid` ya no existe pasa a `huerfano` (releído bajo el candado del hilo: si `ejecutar.ps1` terminó entretanto, no se pisa su resultado). Se conservan el reclamo y los puntos de control.
- **Reclamos sin vida.** Si el agente de un reclamo lleva `reclamo_min` minutos sin señal, avisa al líder, que decide si lo suelta y reasigna.
- **Suspensión del PC.** Si el latido del propio supervisor envejece más del doble del intervalo, esa vuelta es *tolerante*: renueva referencias y no avisa de caídas ni de colgados (solo de huérfanos y de cuota/login, que no dependen del reloj).
- **Avisos.** Cada problema se cuenta una vez: bitácora, nota `[SUPERVISOR]` en el hilo y notificación de Windows (se silencia con `-SinAvisos` o `MESA_SIN_AVISOS=1`). Los avisos de más de 7 días se olvidan.
- **Mantenimiento.** Rota los logs grandes y refresca `worktrees.json`.
- Cada panel vigila además al supervisor: si no da latido en 3 min, lo dice en pantalla.

### Reintento con puntos de control

- El líder relanza un encargo `huerfano` o `fallo` con `mesa.ps1 reintentar -Hilo <id> -N <n> -De <líder>`: lo vuelve a `aprobado`, suma uno a `intentos` y lo pone en la cola del panel (o lo lanza oculto si no hay panel).
- `ejecutar.ps1` antepone al encargo un aviso de **REINTENTO** con los últimos 5 puntos de control de ese agente en el hilo, para que revise `git status` y no repita lo ya hecho.
- Al llegar a `supervisor.max_intentos` (3), el encargo pasa a `escalado`: se deja una nota a la persona con el log y ya no se relanza solo.
- Un encargo colgado se corta antes con `mesa.ps1 cortar -Hilo <id> -N <n> -De <líder>`. Mata solo el CLI (no el panel) y solo si `en-curso-<pid>.json` coincide con ese intento; luego el encargo queda en `fallo` y se reintenta.

## 8. Variables de entorno

| Variable | Efecto |
|---|---|
| `MESA_DATOS` | Carpeta de datos en lugar de `datos\` junto a la mesa. Sirve para pruebas aisladas y para varias mesas. Su nombre antiguo, `MESA_RAIZ_PRUEBA`, sigue valiendo. |
| `MESA_TRABAJO` | Carpeta donde trabajan los agentes. Por defecto, la que contiene la mesa (por ejemplo `C:\proyectos`). También la usa `Cuadrilla.bat`. |
| `MESA_HUMANO` | Nombre de quien dirige la mesa en los hilos. Si falta, se usa `humano` de `mesa.json` y, si tampoco está, `usuario`. |
| `MESA_CONFIG` | Ruta de un `mesa.json` alternativo. Si falta, se usa `datos\mesa.json` o, sin él, `datos\mesa.ejemplo.json`. |
| `MESA_SIMULAR` | Con `1`, `ejecutar.ps1` no llama a ningún CLI y escribe una respuesta simulada: así se prueba el flujo sin gastar cuota. Equivale a `-Simular`. |
| `MESA_SIN_AVISOS` | Con `1`, el supervisor no muestra notificaciones de Windows (la bitácora y las notas siguen). |

## 9. Garantías y límites

- **Escrituras.** Los JSON se escriben a un archivo temporal y se mueven sobre el destino; los `.jsonl` se anexan bajo candado (`<archivo>.lock`, abierto en exclusiva: Windows lo suelta aunque el proceso muera).
- **Numeración y reclamos.** La numeración de mensajes va bajo el candado del hilo; los reclamos usan `CreateNew`.
- **Lecturas tolerantes.** Un mensaje dañado se avisa y se salta, sin cortar el listado entero.
- **Ámbito.** Lo listado en `excluidos.txt` no se lee, muestra ni toca; los agentes no leen credenciales ni sesiones, y no se automatizan ventanas ni se ejecutan programas con interfaz.
- **Límites conocidos.** Solo Windows y PowerShell 5.1; la coordinación es por sondeo de archivos (latencia de segundos, no de milisegundos); el prompt de `claude` y `agy` viaja como argumento de línea de comandos (límite de Windows de unos 32 000 caracteres),. Los fallos conocidos están en [fallos-conocidos.md](fallos-conocidos.md).
