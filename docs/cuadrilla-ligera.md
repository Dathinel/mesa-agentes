# Cuadrilla ligera

Plan del 25-oct. Sustituye la Cuadrilla de hilos, supervisor y panel (D-001, D-002) por una orden que se ejecuta y termina. Base: `cuadrilla.ps1` con subcomandos y una skill de usuario. Del diseño alternativo se toman el respaldo con bundle, la carpeta `datos\trabajos\`, el `--add-dir <repo>\.entorno`, la copia de la skill y dejar la poda de `comun.ps1` para el final.

## Qué es
Claude dirige; codex (`codex exec`) y agy (`agy -p`) hacen lo mecánico. Claude escribe el encargo en un .md y lo lanza con su Bash o su PowerShell en segundo plano (`run_in_background`), y Claude Code le avisa al terminar: no hay sondeo, hook, cola ni panel. Cada encargo deja `datos\trabajos\<id>\` con encargo.md, prompt.txt, log.jsonl, final.txt y `resultado.json`, este escrito de forma atómica. En reposo no queda ningún proceso de la mesa: 0 % de CPU, frente al 34 % de un núcleo que gastaba el trabajador del panel (16 000 s en 13 h, medido) más el 12-15 % del supervisor (estimado). El código activo baja de unas 13 000 líneas (herramientas 4 400 + panel 8 600) a menos de 1 000.

## Piezas
| Pieza | Ruta | Qué hace |
|---|---|---|
| Orden única | `herramientas\cuadrilla.ps1` (~250 líneas) | Subcomandos `delegar`, `estado [<id>]`, `cortar <id>` y `cuota`. De `ejecutar.ps1` trae las órdenes de los CLI (:308-323), `Leer-EventoFinal` (:65-82) y la parte de texto y tokens de `Extraer-ResultadoYTokens` (:84-170). |
| Lanzador | `herramientas\proceso.ps1` | Sin cambios en lo probado: Job con KILL_ON_JOB_CLOSE, UTF-8, stdin aparte, shims de npm. Añade `UltimaLinea` en `Guardar` y el parámetro `-Inactivo <s>`: si no llega ninguna línea en ese tiempo, corta el árbol con salida 124 y causa `colgado`. El bucle duerme 500 ms (hoy 40). |
| Biblioteca | `herramientas\comun.ps1` | Dos arreglos en `Mesa-CausaFallo`: «try again at 6:57 PM» de codex da la hora real (hoy o mañana), y `UNAVAILABLE`, 502, 503 y `overloaded` pasan a `red`. Recibe `Mesa-Ocultar` (observatorio.ps1:36-43) para la respuesta impresa. Lo que ya nadie usa (hilos, reclamos, contadores, alias openworker y opencode) se poda al final, con las pruebas en verde. |
| Worktrees | `herramientas\worktrees.ps1` | `crear`, `lista` y `limpiar` igual, con tres arreglos. `Repos` busca a dos niveles: hoy Subtitular, Rastrear y Lanzador quedan fuera de `lista`, de `limpiar` y del tope. `limpiar` se salta los worktrees de un agente con el candado tomado, porque uno recién creado está «integrado y limpio». Y deja de mirar reclamos. |
| Bloqueo de git | `herramientas\git-bloqueo\reference-transaction` | Hook de 3 líneas que aborta toda escritura de refs: commit, rama, reset, stash. El lanzador lo activa solo en el entorno del CLI con `GIT_CONFIG_COUNT`, que pone `core.hooksPath` y `url.cuadrilla-sin-push://.pushInsteadOf` para https://, git@ y ssh://. No toca la configuración del repo. |
| Skill | `plantillas\cuadrilla\SKILL.md`, copiada a `%USERPROFILE%\.claude\skills\cuadrilla\` | Cuándo delegar, la orden exacta, qué hacer con cada salida, revisión y PR, y el aviso al celular. Vale en cualquier proyecto, en la app y por Remote Control, y se invoca sola o con `/cuadrilla`. |
| Instalación | `herramientas\instalar.ps1` (~20 líneas) | Crea `datos\mesa.json` y `datos\trabajos\` si faltan y copia la skill si difiere. `estado` avisa si la copia instalada no coincide con la plantilla. |
| Configuración | `datos\mesa.ejemplo.json` | Solo quedan `modelos` (el primero es el de por defecto), `limites` (`encargo_min` 90 e `inactivo_min` 20) y `worktrees.max_por_agente` (3). |
| Pruebas | `pruebas\probar-cuadrilla.ps1`, `pruebas\caos-procesos.ps1`, `pruebas\probar-real.ps1` y `Probar.bat` | CLI falsos en una copia aislada (`MESA_DATOS`), sin gastar cuota, y la prueba real de solo lectura. |
| Reglas | `CLAUDE.md` de la mesa (versionado, ~25 líneas), `README.md`, `docs\decisiones.md` (D-003) | Qué es, los cuatro subcomandos, dónde están los datos y las cifras. |

## delegar, paso a paso
`delegar -A codex|agy -Encargo <md> -Dir <carpeta> [-Tarea t] [-Modelo m] [-Esfuerzo low|medium|high] [-Lectura] [-Red] [-Minutos n]`
1. **Valida antes de tocar nada.** Si algo falla, responde `NO LANZADO: <motivo>` con salida 3 en menos de 3 s. Comprueba que el CLI está en el PATH; que el .md y -Dir existen; que la ruta no lleva `$`, `(` ni backtick; que nada cae bajo `datos\excluidos.txt` (IVIMA); que el modelo está en `mesa.json`; que, si -Dir contiene repos sin ser uno, se pidió -Lectura; que el último resultado de ese agente no tiene un `sin-cuota` vigente; y que la misma tarea no está viva (`Mesa-ProcesoVivo`) ni hecha con el mismo hash del .md.
2. **Candado.** `datos\trabajos\<agente>.lock`, abierto con FileShare None durante todo el encargo, deja uno a la vez por CLI: el 24-oct, tres codex en paralelo agotaron la cuota. Windows lo suelta si el proceso muere.
3. **Worktree.** Si -Dir es un repo y no hay -Lectura, `worktrees.ps1 crear` da `<repo>\.claude\worktrees\<agente>-<tarea>` en la rama `<agente>/<tarea>`. La tarea es el nombre del .md sin `encargo-` ni el agente, así que se acaba `codex-codex-hdr`. Si la creación falla, no se lanza (hoy `delegar.ps1:61` cae al checkout principal con un aviso). Si el worktree ya existe, se reutiliza y el reintento sigue donde quedó.
4. **Prompt.** Es una cabecera fija más el encargo. Las rutas `<repo>\...` que existen en el worktree se cambian a él; lo no versionado, como `.entorno`, sigue en el original. Cabecera: «Trabajas en <worktree> (rama <rama>). Solo cambias archivos ahí. No haces commit, push, merge, rebase ni cambias de rama: Claude revisa y confirma. No abres programas con interfaz ni dejas procesos en segundo plano. Si algo te bloquea, para y dilo. Termina con: Hecho / Archivos tocados / Cómo lo probaste / Pendiente.»
   Tras un fallo o un corte añade: «REINTENTO: el intento <id> terminó <estado>; log <ruta>; mira git status y no repitas lo hecho».
5. **Lanza** dentro del Job, con `resultado.json` ya en `ejecutando` y la identidad del lanzador (pid, inicio y nombre).
   - codex: `exec --skip-git-repo-check -C <trabajo> -s workspace-write|read-only [--add-dir <repo>\.entorno] [-c sandbox_workspace_write.network_access=true solo con -Red] --json -m <m> -c model_reasoning_effort=<e> -o final.txt -`, con el prompt por stdin. Desaparecen `--add-dir D:\Programas de uso libre` y la red por defecto (ejecutar.ps1:311-313).
   - agy: `-p "Lee el encargo completo en el archivo UTF-8 <prompt.txt> y ejecuta sus instrucciones." --model <m> --mode accept-edits|plan --output-format stream-json`. Va siempre en stream-json para que el log avance; hoy, oculto, va en json y no escribe nada hasta el final (ejecutar.ps1:322).
6. **Recoge.** El texto sale de `final.txt` o, si falta, del `item.text` del último `agent_message` en codex, y de `response` en agy; se queda la cola de 3 000 caracteres, pasada por `Mesa-Ocultar`. Los tokens, del evento final. La causa, de `Mesa-CausaFallo`, o `tiempo` o `colgado`. Los cambios, de `git status --short` y `diff --stat`. Hay aviso si se movió HEAD, si cambió `refs/remotes/origin/<rama>`, si cambió el status del checkout principal o, con -Lectura, el de la carpeta. Guarda `cpu_lanzador_s`.
7. **Sale** con 0 (hecho), 2 (hecho con aviso: agy con `status: ERROR` pero `response` no vacía, o avisos de git), 1 (fallo), 124 (tiempo o colgado) o 3 (no lanzado). Imprime una línea de resumen, la ruta de `resultado.json` y la respuesta.

Ninguno de los otros subcomandos lee transcritos:
- `estado` solo lee los `resultado.json`. Da una línea por agente (libre; ocupado <id> con minutos y edad del log; sin cuota hasta HH:MM; no instalado) y los 10 últimos encargos. Un `ejecutando` cuyo lanzador ya no vive pasa a `interrumpido`.
- `cortar <id>` comprueba la identidad y mata al lanzador, y el Job se lleva el árbol (caso «Muerte del lanzador» de caos-procesos). No se usa TaskStop, que no garantiza llegar al powershell.exe hijo.
- `cuota` lee `agy -p "/usage"` bajo demanda, con tiempo máximo, y la última señal sin-cuota de cada agente.

## Flujo
1. Daniel pide algo en la app o por Remote Control. Claude separa lo que pide criterio (diseño, revisión, publicación, licencias, lo irreversible) de lo mecánico y comprobable. Lo que lleva menos de 5 min lo hace él.
2. Escribe el encargo en `datos\encargos\<tarea>.md` o en `Rodaje\.proceso\diseno\encargos\`, con cuatro apartados: Objetivo, Contexto (rutas absolutas y reglas del repo), Hecho cuando (con la orden que lo demuestra) y No toques.
3. Lo lanza con `run_in_background: true`: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Programas de uso libre\mesa-agentes\herramientas\cuadrilla.ps1" delegar -A codex -Encargo "<md>" -Dir "<repo>"`. Las rutas van literales, entre comillas dobles y sin barra final. Un encargo a codex y otro a agy pueden ir a la vez.
4. Sigue con otra cosa. Si Daniel pregunta cómo va, `estado` responde en menos de 1 s.
5. Al llegar el aviso, revisa en el worktree: lee los avisos, mira `git -C <wt> diff`, compila sin advertencias y pasa las pruebas él mismo. Si vale: commit, push de la rama y `gh pr create`, y la unión sigue la regla 4 del CLAUDE.md raíz. Si no vale: lo corrige él, o escribe un `<t>-correccion.md` y relanza con `-Tarea <t>` en el mismo worktree.
6. Si Daniel puede no estar delante (escribe por Remote Control o el encargo pasó de 10 min), Claude le manda un `PushNotification` de una línea con lo que debe saber. Si pide ver el cambio, le envía el diff con `SendUserFile`.
7. Tras unir, `worktrees.ps1 limpiar`. Al abrir sesión (paso 0 del CLAUDE.md raíz), `cuadrilla.ps1 estado` enseña lo interrumpido, que se retoma repitiendo la orden.

## Qué se retira y cómo volver atrás
**Antes de tocar nada:** se confirman los cambios pendientes (`cuota.ps1`, +17/-8, y `diseno\`), se crea la etiqueta local `cuadrilla-v1` y se hace `git bundle create "D:\Respaldos\cuadrilla\cuadrilla-2026-10-25-v1.bundle" --all`, comprobado con `git bundle verify`, como en D-001 (el repo no tiene remoto). El cambio se hace en la rama `ligera`, en un worktree, con dos commits: «se retira» (`git rm`) y «Cuadrilla ligera (D-003)».
- **Residentes:** `supervisor.ps1`, `vigia.ps1`, `tablero.ps1`, `trabajador.ps1`, `esperar-novedades.ps1` y `panel\` entero (servidor, trabajador con Start-Job, `estado.ps1`, oficina y resumen).
- **Hilos y protocolo:** `mesa.ps1` (29 subcomandos), `delegar.ps1`, `ejecutar.ps1`, `plantillas\protocolo.md`, AGENTS.md y GEMINI.md.
- **Lectura de sesiones:** `costes.ps1`, `observatorio.ps1`, `tokens-calibrador.ps1`, `medir-claude.ps1` y `cuota.ps1`. Lo de agy pasa a `cuadrilla.ps1 cuota`.
- **Integraciones:** `hook-claude.ps1` y `.claude\settings.json` (costaban 0,5-0,9 s por mensaje y guardaban el id de sesión), `abrir-claude.cmd`, `herramientas\mcp\` (D-002, nunca conectado) y `Cuadrilla.bat`.
- **Pruebas de lo retirado:** `caos.ps1`, `probar-relevo`, `-vigia-ambito`, `-oficina`, `-panel`, `-resumen`, `-estado`, `-recarga`, `-cierre-panel`, `-cortes`, `-arranque-claude`, `-carpeta-encargo` (su caso pasa a probar-cuadrilla) y `capturar-vistas`. También `datos\personajes.json`, `datos\reclamos\LEEME.md` y `docs\estado-contrato.md`.
- **`datos\`, que no está versionado:** no se borra nada. Lo del sistema viejo se mueve a `datos\archivo\v1-2026-10-25\`: hilos (con los 141 encargos fantasma), actividad, alertas, vigía, panel, cuota, aprobaciones, registro de tokens, latidos, puerto y token. Quedan `mesa.json`, `excluidos.txt`, `encargos\` y `trabajos\`. `sesion-*.txt` y `token.txt` también van al archivo; borrarlos lo decide Daniel.
- **Fuera del repo:** la skill en `~\.claude\skills\cuadrilla`. La memoria `delegar-codex-agy.md` pasa a apuntar a la skill.
- **Volver atrás:** `git checkout cuadrilla-v1` o `git revert` de los dos commits; devolver `datos\archivo\v1-2026-10-25\*` a `datos\`; `npm ci` en `herramientas\mcp` si se quiere el MCP; borrar la carpeta de la skill. También se puede clonar el bundle.

## Fallos reales cubiertos
| Fallo visto | Qué lo evita |
|---|---|
| Panel y supervisor: 34 % y 12-15 % de un núcleo sin trabajo; vigía en bucle 17 h | No queda ningún proceso residente |
| 141 encargos fantasma, avisos de Claude a sí mismo (`mesa.ps1:533-547`) | No hay cola, hilos ni modo por lotes |
| agy colgado dos veces 90 min con un log de 63 bytes (#5, #6) | stream-json siempre y corte tras 20 min sin salida |
| agy marcado «fallo» habiendo entregado la respuesta (#107, #129) | `hecho con aviso` (salida 2); el 503 cuenta como red |
| Tres codex en paralelo sin cuota; «hasta» a las 15:10 en vez de las 18:57 | Un encargo por CLI; hora leída de «try again at»; rechazo inmediato hasta esa hora |
| 3 KB de JSON crudo como respuesta de codex | `item.text` del último `agent_message` |
| 4 CARPETA_INEXISTENTE con `$A` y `$( )`; modelo `gemini-3-flash` | Validación previa, con salida 3 |
| Prefijo `codex-codex-*`; worktree fallido que cae al checkout principal | Nombre de tarea limpio; sin worktree no se lanza |
| Topes alcanzados en silencio: Claude solo se enteraba si miraba el hilo | El aviso de fin de la tarea en segundo plano trae el resultado |
| Push y `.git` prohibidos solo en el prompt; `--add-dir` sobre toda la carpeta | Bloqueo de refs y de push en el entorno del CLI; sandbox limitado al worktree; avisos después |
| Apagón a mitad | `resultado.json` atómico; `estado` lo marca `interrumpido`; la misma orden retoma en el worktree |
| Lectura de transcritos de sesión (vigía, costes, cuota y hook) | Se retira; los tokens salen del evento final del propio CLI |

## Criterios de terminado
1. **`Probar.bat` en verde**, con `probar-cuadrilla` y `caos-procesos`: 0 fallos y sin gastar cuota. Casos mínimos:
   - salidas: codex con `final.txt` y sin él (texto de `item.text`); agy con ERROR y respuesta da salida 2; «try again at 6:57 PM» da hasta las 18:57, y el segundo intento sale con 3 en menos de 2 s sin arrancar el CLI; 503 da red y 401, necesita-login;
   - rechazos: CLI fuera del PATH, carpeta inexistente, ruta con `$(` o modelo inválido salen con 3 en menos de 3 s, sin crear worktree; dos `delegar` al mismo CLI dejan el segundo en `ocupado`; el mismo .md ya hecho se rechaza y `-Tarea` corrige en el mismo worktree;
   - cortes: un falso mudo queda `colgado` con 0 descendientes; con el lanzador matado queda `interrumpido`, con 0 descendientes y reintento con la cabecera REINTENTO; siguen los casos de proceso (40 000 caracteres con tildes, argumentos intactos, límite de tiempo, stdin bloqueada, PID reutilizado);
   - git: `encargo-codex-hdr.md` da `codex-hdr`; en un repo temporal con remoto bare local, el falso intenta `git commit` y `git push`, los dos fallan y HEAD y el remoto quedan intactos; `limpiar` respeta el worktree con candado.
2. **Prueba real de solo lectura** (`pruebas\probar-real.ps1`). Claude la lanza con `run_in_background` y la repite por Remote Control. Van a la vez codex (`-Modelo gpt-6-luna -Esfuerzo low`) y agy (`-Modelo gemini-3.8-flash-low`), con `-Lectura` sobre `D:\Programas de uso libre\Herramientas-IA\Lanzador` y el encargo «Lee README.md y resume en tres líneas qué hace. No modifiques nada.». En los dos deben llegar los avisos de fin sin sondear, con salida 0, estado `hecho`, respuesta no vacía y tokens leídos del evento final; `git status --porcelain` debe quedar idéntico, sin ningún worktree creado, y `cpu_lanzador_s` por debajo de 5.
3. **Bloqueo real.** En un repo temporal con remoto bare, un encargo a cada CLI pide `git commit --allow-empty -m x` y `git push`: los dos fallan y el remoto no cambia. Si un CLI no hereda el bloqueo, queda solo la detección y se anota en D-003.
4. **0 procesos de la mesa en reposo.** `Get-CimInstance Win32_Process | ? CommandLine -match 'mesa-agentes'` devuelve 0 elementos antes de lanzar y 1 minuto después de que acaben los encargos de la prueba real.
5. **Sin lectura de sesiones.** Buscar en `herramientas\` `\.claude\projects`, `\.codex\sessions`, `antigravity-cli` y `sesion-claude` da 0 coincidencias.
6. **Revisión independiente** del bloque por un agente de otro modelo, sin contexto, contra estos criterios. Lo que Daniel note desde el celular (el PushNotification al terminar) va a `pruebas-a-mano.md`, sin parar el plan.

## Orden de construcción
1. Respaldo: commits pendientes, etiqueta `cuadrilla-v1` y bundle comprobado. Worktree con la rama `ligera`.
2. `proceso.ps1` (`UltimaLinea`, `-Inactivo`, 500 ms) y `Mesa-CausaFallo`. `caos-procesos` se adapta a lo que no depende de hilos y suma el caso «Inactivo».
3. `cuadrilla.ps1`: primero `delegar` y `estado` con `probar-cuadrilla`; después `cortar`, `cuota` y el hook `git-bloqueo`.
4. Arreglos de `worktrees.ps1`. Skill, `instalar.ps1`, `mesa.ejemplo.json` y el `CLAUDE.md` de la mesa.
5. Retiro con `git rm`, traslado de `datos\` al archivo y poda de `comun.ps1`. `Probar.bat` en verde.
6. Prueba real, bloqueo real y 0 procesos. README con las cifras, D-003, paso 0 del CLAUDE.md raíz (es una regla: con el visto bueno de Daniel) y memoria.
7. Revisión independiente; unir `ligera` en `main` y quitar su worktree.

## Riesgos abiertos
- **El encargo vive lo que la sesión de Claude Code.** Si la app se cierra, el Job corta el CLI, el encargo queda `interrumpido` y se retoma con la misma orden. Para la cola nocturna, la sesión se deja abierta con `request_keep_awake`. No está comprobado que una tarea en segundo plano aguante 90 min por Remote Control.
- **Bloqueo de git sin comprobar.** No se sabe si codex y agy pasan `GIT_CONFIG_*` a sus órdenes. Codex quita por defecto las variables con KEY en el nombre, así que se le pasan con `-c shell_environment_policy.set`, también sin comprobar. Si llegaran a medias, git fallaría entero en codex. Lo decide el criterio 3.
- **`agy --mode plan`.** Si no responde con `-p`, agy `-Lectura` pasa a `accept-edits` dentro de un worktree.
- **Red y `.entorno`.** Sin red por defecto, restaurar paquetes de NuGet o npm falla: hace falta -Red. Que un build de Rodaje funcione en el worktree con `--add-dir <repo>\.entorno` se comprueba con el primer encargo que compile.
- **Corte por silencio.** Los 20 min sin salida pueden cortar una compilación o una batería de pruebas larga que el CLI no narra; se sube con `inactivo_min` o -Minutos.
- **Lo que se pierde:** la oficina, la charla y el relevo entre agentes, los topes por hora, las alertas del vigía y ver la cuota de codex antes de que se agote, porque leerla exige leer `~\.codex\sessions`.
- **Rama `publicable`.** Se rehace después desde `main`; lo decide Daniel.
