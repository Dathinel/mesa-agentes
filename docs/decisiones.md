# Decisiones de Cuadrilla

## D-001: Cuadrilla vive solo en local (20-oct-2026)

**Decisión.** Se retira de GitHub el repositorio privado `Dathinel/mesa-agentes`. La copia de trabajo es `D:\Programas de uso libre\mesa-agentes` y el respaldo completo, `D:\Respaldos\cuadrilla\cuadrilla-<fecha>.bundle` (`git bundle create --all`, comprobado con `git bundle verify`).

**Por qué.** El repo llevaba datos personales y no aportaba nada que no estuviera en local: una sola rama, ya contenida en `main`, y ningún issue, PR, release ni wiki (lista en `docs/exportado-github/`). La versión publicable sigue en la rama local `publicable`.

**Consecuencias.**
- Un cambio de la propia Cuadrilla se une a `main` con `Probar.bat` en verde; la regla de PR con CI sigue valiendo para los demás repos (`plantillas/protocolo.md`).
- `worktrees.ps1` ya funciona sin remoto: sin `origin` toma `main` como base y el `fetch` falla en silencio.
- `.github/workflows/ci.yml` se conserva para el día que se publique `publicable`.

## D-002: Servidor MCP para la app de escritorio de Claude (20-oct-2026)

**Decisión.** `herramientas\mcp\servidor.mjs` expone la mesa por stdio a la app de escritorio con ocho herramientas: `ver_hilos`, `leer_hilo`, `ver_pendientes`, `abrir_hilo`, `enviar_mensaje`, `pasar_liderazgo`, `aprobar` y `rechazar`.

**Lenguaje.** JavaScript sobre Node con el SDK oficial de TypeScript (`@modelcontextprotocol/sdk` 1.32.1), que es el de referencia, y Node ya está instalado; no hay SDK de PowerShell y uno en C# obligaría a compilar.

**Cómo envuelve sin duplicar.** Cada herramienta ejecuta `mesa.ps1` con PowerShell 5.1, como los agentes. Los parámetros viajan como JSON en una variable de entorno, así que nunca se interpretan como código. No hay herramientas para ejecutar comandos ni leer archivos arbitrarios: los ids de hilo se validan con `^[A-Za-z0-9][A-Za-z0-9-]*$` y los destinos son una lista cerrada.

**Cola de aprobación.**
- El autor de todo lo que envía la app es `claude-app`, que no está en `autoaprobar` de `mesa.json`. Por eso un mensaje a `codex`, `agy` o `claude` siempre queda como encargo **pendiente**, de cualquier tipo. Con `solo_nota` es una nota que no lanza nada.
- `aprobar` hace `mesa.ps1 aprobar -NoLanzar` y lanza `ejecutar.ps1` oculto con `mcp\lanzar.ps1`, igual que `delegar.ps1` sin `-Visible`: la app no se queda bloqueada mientras trabaja el agente, y los topes de `mesa.json` se aplican igual.
- `aprobar` y `rechazar` llevan `destructiveHint: true` para que la app pida permiso en cada uso.

**Registro.** Cada llamada deja una línea JSON en `datos\claude-app.log` (`fecha`, `origen: claude-app`, herramienta, argumentos y si salió bien). Además, los mensajes llevan autor `claude-app` y `aprobaciones.log` lleva `claude-app` en el motivo.

**Lo que no se hace.**
- No se registra `codex mcp-server` en la app, porque se saltaría la cola. En codex 0.163.0 ese subcomando ni siquiera existe.
- La app habla con Codex y agy solo a través de Cuadrilla.

**Comprobado el 20-oct.**

| Qué | Resultado |
|---|---|
| Config de la app | `%APPDATA%\Claude\claude_desktop_config.json` (instalación clásica, no MSIX); no tenía `mcpServers`. Copia previa en `claude_desktop_config.antes-cuadrilla-2026-10-20.json` |
| `agy --help` (1.4.3) | Tiene `-p/--print`, `--output-format text/json/stream-json`, `--model`, `--effort`, `--mode`, `--sandbox`, `--dangerously-skip-permissions` y el subcomando `mcp` |
| `codex mcp-server` (0.163.0) | No existe: solo `mcp` (gestionar servidores externos), `app-server` y `exec-server`, ambos experimentales |
| Prueba | `node herramientas\mcp\probar.mjs`: mesa aislada en `%TEMP%`, sin lanzar agentes |

**Instalación en otra máquina.** Ejecuta `npm ci` en `herramientas\mcp`. Después añade a `mcpServers` de la config: `"cuadrilla": { "command": "<node.exe>", "args": ["<ruta>\\herramientas\\mcp\\servidor.mjs"] }`.

## D-003: Cuadrilla ligera (25-oct-2026, construida el 31-oct)

**Decisión.** Se sustituye la Cuadrilla de hilos, supervisor y panel (D-001, D-002) por una sola orden, `herramientas\cuadrilla.ps1`, que lanza un encargo a `codex exec` o `agy -p`, espera y termina. Claude la ejecuta en segundo plano y Claude Code le avisa al acabar: no hay cola, hook, sondeo ni proceso residente. Plan completo en `docs/cuadrilla-ligera.md`.

**Por qué.** El panel y el supervisor gastaban un 34 % y un 12-15 % de un núcleo sin trabajo; había 141 encargos fantasma; agy se colgó dos veces 90 min con un log de 63 bytes; tres codex en paralelo agotaron la cuota; y la cuota, los costes y el vigía exigían leer transcritos de sesión. Lo mecánico lo resuelve una orden que valida antes de lanzar, un candado por CLI, un corte por silencio y un `resultado.json` atómico.

**Lo que cambia.**
- Código activo: de unas 13 000 líneas (herramientas 4 400 + panel 8 600) a 1 040 (`cuadrilla.ps1` 270, `proceso.ps1` 190, `comun.ps1` 105, `worktrees.ps1` 95, `instalar.ps1` 16, hook 4; pruebas aparte).
- Datos: solo `datos\mesa.json`, `excluidos.txt`, `encargos\` y `trabajos\<id>\`. Lo de la v1 está en `datos\archivo\v1-2026-10-25\`.
- Git en el CLI: hook `reference-transaction` por `GIT_CONFIG_COUNT` (solo en el entorno del proceso) que aborta commit, rama, reset, stash y el push a un remoto local; `pushInsteadOf` desvía https://, git@ y ssh://. Comprobado con CLI falsos (`probar-cuadrilla`); el resultado con los CLI reales está en «Bloqueo real» de `docs/cuadrilla-ligera.md`.
- Se pierde: oficina, charla y relevo entre agentes, topes por hora, alertas del vigía y ver la cuota de codex antes de agotarla.

**Vuelta atrás.** `git checkout cuadrilla-v1`, o `git revert` de los commits «Se retira…» y «Cuadrilla ligera (D-003)»; devolver `datos\archivo\v1-2026-10-25\*` a `datos\`; borrar `%USERPROFILE%\.claude\skills\cuadrilla`. Bundle: `D:\Respaldos\cuadrilla\cuadrilla-2026-10-25-v1.bundle`.
