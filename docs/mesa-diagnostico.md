# Diagnóstico de la Mesa (Fase 2)

19 de octubre de 2026. Comparación punto por punto con la lista de requisitos, ordenada por prioridad: primero recuperar a un agente que muere. **Estado** es cómo estaba antes de esta ronda; **Ahora** es lo que quedó hecho y probado en esta ronda (Daniel pidió aplicar lo recomendado). Las pruebas citadas están en `pruebas\caos.ps1` (12/12) y corren con `Probar.bat`.

Leyenda: ✅ cubierto · 🟡 parcial · ❌ no.

## Evidencia de partida (datos reales del 17 al 19 de octubre)

- 3 encargos atascados en `ejecutando` para siempre: `20261018-prueba-de-coordinacion-p` #1 (codex, el log solo repite `Reconnecting... waiting for network`), #64 (agy, sin log) y `charla-agy` #1. Nadie los detectó.
- 1 cuota agotada tratada como fallo cualquiera: `20261018-encargo-agy-intermitente` #1, `RESOURCE_EXHAUSTED`, 429, `Resets in 134h28m`.
- 1 reclamo que sobrevivió un día a su entrega (`modelado-blender` de claude).
- `trabajador.ps1` no capturaba excepciones fuera del relevo: un JSON dañado o un candado ocupado más de 10 s cerraban el panel de codex o agy.
- `actividad.jsonl` 3,6 MB, `vigia-estado.json` 1,2 MB, `estado-panel.json` 534 KB descargado cada 5 s, sin rotación.
- `probar-oficina.ps1` fallaba (esperaba que `cd ..` fuera peligroso).

## B. Agente que muere a mitad (prioridad 1)

| # | Punto | Estado | Evidencia | Ahora |
|---|---|---|---|---|
| B1 | Arriendo con caducidad | 🟡 | `reclamar` crea el reclamo atómico (`mesa.ps1`, `'reclamar'`), pero nunca caducaba. | El arriendo se renueva solo: cuenta la última herramienta que usó el agente (`actividad.jsonl`, que el vigía ya escribía) y su último `avance`. Sin señal en `supervisor.reclamo_min` (60 min) el supervisor avisa al líder; no lo suelta solo, para no tener dos dueños si el agente vuelve (`supervisor.ps1`, sección 3). Prueba «Arriendo de reclamo caducado». |
| B2 | Libre, muerto y colgado | ❌ | La oficina solo conocía «apagado» y «esperando»; no usaba los latidos (`panel\estado.ps1`). | Cada encargo guarda el PID de quien lo ejecuta (`ejecutar.ps1`, `llamada.pid`). Muerto: el PID ya no existe → encargo `huerfano`. Colgado: vivo y sin salida nueva en `colgado_min` (30) o el CLI esperando red más de 10 min. Panel caído: su latido tiene más de 90 s. Estado en `datos\agentes\<agente>.json`. Pruebas «Agente muerto a mitad», «Encargo colgado», «Pestaña cerrada». |
| B3 | Cuota, login y contexto perdido | ❌ | El 429 de agy acabó como `fallo` genérico. | `Mesa-CausaFallo` (`comun.ps1`) lee la cola del log: `sin-cuota` hasta la hora que diga «Resets in…», `necesita-login`, `red`. Queda en `llamada.causa/hasta` y el supervisor pone al agente en ese estado y avisa para reasignar. Contexto compactado: no se detecta por el log; lo cubre el reintento con puntos de control (B8). Pruebas «Cuota agotada», «Sesión caducada». |
| B4 | Puntos de control | 🟡 | `avance` inicio/hito/bloqueo/alcance ya existía y `entregar` lo exige. Faltaban rama, worktree y cambios sin confirmar. | Sin cambio de formato. Propuesta: añadir a `avance` un campo automático con `git -C <dir> status --porcelain -b` cuando la carpeta sea un repo. Pendiente: necesita que cada agente trabaje en su worktree (B5). |
| B5 | Un worktree por agente | ❌ | Todos trabajan en `D:\Programas de uso libre` (`ejecutar.ps1`, `-C $workDir`). | No hecho: cambia cómo trabaja cada agente en Rodaje y los demás repos. Propuesta: `delegar.ps1 -Worktree` que cree `..\worktrees\<agente>-<tarea>` con `git worktree add` y lo pase como `-Dir`; solo el líder integra. Es la siguiente pieza recomendada. |
| B6 | Quién recupera | 🟡 | El relevo del líder existía (`trabajador.ps1`, `Vigilar-Lideres`, 15 min, candado `relevo-<hilo>.lock`). Faltaba recuperar las tareas. | El supervisor escribe al líder del hilo «Qué pasó · Qué hice · Qué necesito» con la orden exacta (`mesa.ps1 reintentar -Hilo -N -De <líder>`). Reintentar suma intentos y al tercero escala a Daniel (`supervisor.max_intentos`). El candado del relevo hace de arriendo del liderazgo. Pruebas «Reintento tras la muerte», «Escalado tras 3 intentos», «Arriendo del líder caduca». |
| B7 | Reinicio | ❌ | Daniel reabría a mano. | Supervisor en PowerShell sin modelo (`supervisor.ps1`), arrancado por `Mesa.bat`, con notificación de Windows. Ofrece `Mesa.bat panel codex|agy`, que reabre el panel en la misma ventana (`wt -w mesa`). Relanzar solo: `supervisor.relanzar = true` en `mesa.json`, máximo 3 en 10 min; luego para y avisa. Viene apagado. Comandos de reanudar comprobados: `claude --continue`/`--resume <id>`, `codex exec resume <id>`, `agy --conversation <id>`/`--continue`. `Mesa.bat` reanuda Claude con `--continue`; los paneles ya reanudan su charla con `datos\sesion-<agente>.txt`. |
| B8 | Inyectar la tarea al volver | ❌ | — | Al reintentar, `ejecutar.ps1` antepone al encargo «REINTENTO n» y los últimos 5 puntos de control de ese agente en el hilo, con la orden de revisar `git status` y no repetir pasos. Para la sesión interactiva de Claude, propuesta: un hook `SessionStart` que ejecute `mesa.ps1 pendientes -Para claude` y `reclamos`; no lo activé porque cambia tu configuración de Claude Code (ver E3). |
| B9 | Repetir sin daño | 🟡 | `ejecutar.ps1` relee el estado bajo candado antes de lanzar (no hay doble lanzamiento); los mensajes tienen número único por hilo (`Mesa-EscribirMensaje`). | El reintento parte de los puntos de control. Falta marcar pasos como hechos dentro del encargo: se apoya en `avance -Fase hito`. |

## C. Errores de Windows y de la carpeta

| # | Punto | Estado | Evidencia | Ahora / propuesta |
|---|---|---|---|---|
| C1 | Espacios y variable de raíz | 🟡 | Casi todo con `-LiteralPath`; `D:\Programas de uso libre` escrito en `comun.ps1`, `delegar.ps1`, `ejecutar.ps1`, `vigia.ps1`. | ✅ Raíz de trabajo en `MESA_TRABAJO` (por defecto, la carpeta que contiene la mesa) y raíz de datos en `MESA_RAIZ_PRUEBA`. Ya no queda ninguna ruta escrita a mano en el código. |
| C2 | UTF-16 y finales de línea | 🟡 | Todo JSON se escribe en UTF-8 sin BOM (`Mesa-EscribirJson`). Los logs con `*>` salen en UTF-16 y se mezclan con UTF-8 en `-Ver`. Los `.bat` escritos con LF no los entiende cmd (lo comprobé con `Mesa.bat`). | ✅ `.gitattributes` fija CRLF para `.bat`, `.cmd` y `.ps1`; los `.ps1` en UTF-8 con BOM. Los logs mixtos se leen bien (`ReadAllText` detecta el BOM). PowerShell 7 no hace falta. |
| C3 | Escrituras a medias | ✅ | Temporal en la misma carpeta y `Move-Item` (`Mesa-EscribirJson`). | Además, un JSON dañado ya no tumba listados ni paneles: `Mesa-LeerMensaje` lo avisa y lo salta. Prueba «JSON dañado en un hilo». |
| C4 | Bloqueos de Defender o del indexador | 🟡 | `Mesa-Bloquear` reintenta 200 × 50 ms y lanza «Ocupado». | ✅ El panel ya no muere por esa excepción: la registra en `datos\errores-paneles.log` y sigue. |
| C5 | `index.lock` de git | ❌ | Ver B5. | Worktree por agente y un solo integrador. |
| C6 | Dos agentes, mismo archivo | ✅ | Reclamos con `toca` y el vigía avisa de ediciones sin reclamo. | — |
| C7 | Orden de mensajes | ✅ | Número de mensaje secuencial bajo candado (`NNNN-autor.json`), no la hora. | — |
| C8 | Bucles y topes | 🟡 | Topes por hora y día por CLI (`mesa.json` `topes`, `ejecutar.ps1`). No había tope de saltos por tarea. | ✅ Tope de 3 intentos por encargo con escalado. Interruptor de apagado: `Mesa.bat cerrar` o poner los topes a 0. |
| C9 | Inyección entre agentes | 🟡 | Una nota de otro agente no lanza trabajo (`enviar` fuerza `SoloNota` si no eres líder). Pero `avance` devuelve «CUMPLELA ANTES DE SEGUIR» con el texto de cualquier nota. | ✅ Ahora ese aviso solo da por órdenes las notas del líder del hilo, de Daniel o del supervisor; las de otros agentes quedan como dato. Lo irreversible ya pasa por Daniel según `CLAUDE.md`. |
| C10 | Suspensión, terminal cerrada, CLI actualizado | 🟡 | — | Terminal cerrada: el supervisor ve el latido viejo y ofrece `Mesa.bat panel`. Suspensión: al despertar, los latidos envejecen de golpe y el supervisor puede avisar una vez de caída falsa; se resuelve solo en la siguiente vuelta (el aviso se borra cuando vuelve el latido). CLI que cambia flags: `Mesa.bat diagnostico` muestra versiones; se anota en `docs\fallos-conocidos.md`. |
| C11 | Hooks que bloquean | ✅ | No hay hooks en ningún CLI; todo es sondeo. | — |
| C12 | Archivos que crecen | ❌ | Ver evidencia de partida. | ✅ El supervisor rota `actividad.jsonl` (5 MB), `alertas.jsonl` (2 MB) y `errores-paneles.log` (1 MB) a `datos\archivo\` y olvida avisos de más de 7 días. Codex está aligerando `estado-panel.json` y `vigia-estado.json` (tarea `panel-ligero`). Falta archivar hilos cerrados de más de 30 días. |

## A. Ciclo de estados

| Estado pedido | Hoy | Dónde |
|---|---|---|
| recibida / reclamada / en curso | ✅ `pendiente`/`aprobado` → reclamo → `ejecutando` | mensajes del hilo y `datos\reclamos\` |
| verificando / entregada / en revisión | ✅ `entregada` en `entregas\<tarea>.json` hasta `revisar` | `mesa.ps1 entregar`, `revisar` |
| esperando aprobación de Daniel | ✅ mensaje `pendiente` (tablero, «Esperan a Daniel») | `aprobar`, `rechazar` |
| integrada / cerrada | 🟡 `aceptada` → `archivada`; «integrada» (PR unido) no se registra | `archivar` |
| huérfana / fallida / escalada | ✅ nuevo `huerfano`, `fallo` con causa, `escalado` | `supervisor.ps1`, `reintentar` |

Cada transición queda como mensaje numerado con fecha, autor y texto; la bitácora (`mesa.ps1 bitacora`) la cuenta en español llano. No hace falta una máquina de estados aparte.

## D. Rutas

Estructura aplicada: `herramientas\` (código), `panel\` (oficina), `pruebas\` (pruebas aisladas), `docs\` (documentación; `docs\historial\` con encargos e informes viejos, no se sube), `datos\` (todo el estado vivo; solo `mesa.json`, `personajes.json` y `reclamos\LEEME.md` se versionan), `datos\agentes\` (estado por agente que escribe el supervisor), `datos\bitacora\`, `datos\archivo\` (lo rotado y lo limpiado), `anteriores\` (copias viejas, no se sube). Temporales: en la misma carpeta que el archivo final. Nada dentro de Rodaje ni en OneDrive.

## E. Permisos

| # | Punto | Estado | Opinión y qué cambiar |
|---|---|---|---|
| E1 | Cada agente escribe solo lo suyo | 🟡 | Hoy cualquiera puede escribir cualquier archivo de `datos\`; las reglas están en `mesa.ps1` (solo el líder revisa, archiva y suelta reclamos ajenos). Estoy de acuerdo con tu idea, pero no con imponerlo con permisos de archivo: los tres CLI corren con tu usuario y NTFS no distingue entre ellos. Lo práctico es que todo pase por `mesa.ps1` (ya es así) y que el vigía alerte de escrituras directas en `datos\`. |
| E2 | Solo el líder asigna; solo Daniel lo irreversible | ✅ | `enviar` convierte en nota lo que no manda el líder; `revisar` exige líder; `CLAUDE.md` prohíbe releases sin pedirlo. El vigía marca `push --force`, `gh release`, borrados. |
| E3 | Permisos de cada CLI | 🟡 | **Claude**: `defaultMode: "auto"` sin `deny`. Recomiendo añadir en `~\.claude\settings.json` un `deny` para `Bash(git push --force*)`, `Bash(gh release*)`, `Bash(gh repo delete*)` y `Bash(rm -rf /*)`, y quitar `auto` solo si te molesta que actúe sin preguntar. **Codex**: ya va con `-s workspace-write` y red, sin `--dangerously-bypass`; está bien. **agy**: `permissions.allow` incluye `command(*)`, que lo permite todo; recomiendo cambiarlo por la lista concreta (`command(git *)`, `command(gh *)`, `command(powershell *)`, `command(dotnet *)`) y quitar tu carpeta de usuario de `trustedWorkspaces`. No cambié nada de esto: es tu configuración. |
| E4 | Ningún secreto en la mesa | ✅ | Los ámbitos excluidos salieron del código a `datos\excluidos.txt` (no se sube). El observatorio ya redacta tokens. |

## F. Cómo se abre

✅ `Mesa.bat` (sustituye a `Abrir-Mesa.bat`): comprueba `claude`, `codex`, `agy` y `wt`; archiva lo caducado (`mesa.ps1 limpiar`, mueve, no borra); arranca el supervisor y la oficina; abre una ventana `mesa` con Claude (reanudando con `--continue`), Codex, agy y el tablero. `Mesa.bat cerrar` para supervisor y oficina. Falta: comprobar que cada CLI tiene la sesión iniciada sin abrirlo (ninguno tiene una orden de consola fiable para eso; se detecta en el primer fallo con `necesita-login`). PowerShell 7 no se exige.

## G. De un vistazo

| # | Punto | Estado | Ahora |
|---|---|---|---|
| G1 | Tablero | ✅ | `herramientas\tablero.ps1` (codex): agentes, «Esperan a Daniel», tareas por estado y alertas en rojo, cada 5 s; un JSON dañado no lo tumba. |
| G2 | Mismos nombres y colores | 🟡 | claude naranja, codex verde, agy azul en tablero y oficina. Windows Terminal solo colorea pestañas, no paneles. |
| G3 | Título que cambia con el estado | ❌ | ✅ El panel se titula «codex · trabajando #N» o «codex · esperando» (`trabajador.ps1`). |
| G4 | Bitácora diaria | ✅ | `mesa.ps1 bitacora` y `datos\bitacora\AAAA-MM-DD.md`. |
| G5 | Errores en tres partes | ✅ | Todas las notas del supervisor: «Qué pasó · Qué hice · Qué necesito». |
| G6 | La oficina lee los mismos archivos | ✅ | Ya leía `datos\`. |

## H. Problemas del usuario

✅ `Mesa.bat diagnostico` (resumen pegable, sin secretos). ✅ `mesa.ps1 limpiar` (reinicio seguro: archiva en `datos\archivo\limpieza-<fecha>`). ✅ `docs\fallos-conocidos.md`, que crece con cada problema real.

## I. Pruebas

✅ Agentes simulados (`MESA_SIMULAR=1`; `ejecutar.ps1 -Simular` ya existía y ahora también lo activan los paneles) y caos en copia aislada: `pruebas\caos.ps1`, 12 casos con esperado y obtenido, 12/12. Faltan: matar el proceso real de un CLI a mitad (se simula con un PID muerto) y la suspensión del PC.

## Lo que sobra o es exagerado para tu caso

- **Permisos por agente con NTFS (E1).** Tres CLI con tu mismo usuario: no se puede sin cuentas de Windows separadas, y no compensa. Basta con que todo pase por `mesa.ps1` y el vigía.
- **Una máquina de estados con nueve estados (A).** Los mensajes numerados ya son el registro de transiciones; añadir «verificando» o «integrada» como estados separados es más ceremonia que información.
- **Relanzar solo (B7).** Con un relanzado automático se esconden fallos que conviene ver; la notificación con la orden exacta es suficiente. Por eso viene apagado.
- **Detectar contexto compactado (B3).** No hay señal fiable en los logs; el reintento con puntos de control cubre el mismo riesgo.
- **Orden por identificador ordenable (C7).** Ya está resuelto con el número secuencial bajo candado.
- **PowerShell 7 obligatorio.** No hace falta: todo escribe UTF-8 explícito.

## Siguiente, por orden

1. Worktree por agente (B5, C5) y estado de git en los puntos de control (B4).
2. Archivar hilos cerrados de más de 30 días (C12).
3. Hook `SessionStart` de Claude con tus pendientes y reclamos (B8), si lo apruebas.
4. Los `deny` de Claude y la lista concreta de agy (E3), si los apruebas.
