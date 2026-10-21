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
