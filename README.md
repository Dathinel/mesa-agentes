<h1 align="center">Cuadrilla</h1>

<p align="center">
  Claude Code, Codex y Antigravity trabajando juntos en un mismo PC con Windows: uno lidera, reparte y revisa; los otros ejecutan a la vista.<br>
  Se coordinan por archivos JSON en una carpeta, sin servidor ni cuentas nuevas, con un supervisor que detecta y recupera a un agente caído.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-E8833A?style=flat-square&labelColor=1D1D1D" alt="Licencia MIT"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-E8833A?style=flat-square&labelColor=1D1D1D" alt="Windows 10 y 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1-E8833A?style=flat-square&labelColor=1D1D1D&logo=powershell&logoColor=white" alt="PowerShell 5.1">
  <img src="https://img.shields.io/badge/pruebas_de_caos-21%2F21-E8833A?style=flat-square&labelColor=1D1D1D" alt="Pruebas de caos 21 de 21">
</p>

## Qué necesitas

Solo los tres CLI oficiales, instalados y con la sesión iniciada en tu cuenta: `claude` (Claude Code), `codex` (Codex CLI) y `agy` (Antigravity CLI). Además, Windows 10 u 11 con Windows Terminal; PowerShell 5.1 ya viene con Windows. Ninguno de los tres CLI es obligatorio: sin uno, su panel no trabaja y el resto sigue. Cuadrilla no instala nada, no guarda credenciales y no habla con ningún servicio: los CLI usan sus propias sesiones.

## Cómo se usa

1. Copia esta carpeta junto a tus proyectos (los agentes trabajan en la carpeta que la contiene; otra, con `MESA_TRABAJO`).
2. Ejecuta `Cuadrilla.bat`. La primera vez crea `datos\mesa.json` con tu nombre de usuario, `datos\excluidos.txt` (carpetas que ningún agente debe tocar, una expresión regular por línea) y las instrucciones de los agentes (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, desde `plantillas\protocolo.md`). Nada de eso se versiona.
3. Se abre una ventana de Windows Terminal con Claude (el líder, interactivo), los paneles de Codex y agy y un tablero. Le pides la tarea a Claude: abre un hilo, la reparte con encargos escritos y revisa cada entrega.

```cmd
Cuadrilla.bat                  abre todo y reanuda la conversación de Claude de la mesa
Cuadrilla.bat nuevo            igual, con una conversación nueva de Claude
Cuadrilla.bat panel codex      reabre el panel de un agente que se cerró
Cuadrilla.bat diagnostico      resumen pegable en un chat: estados, versiones, errores, sin secretos
Cuadrilla.bat cerrar           para el supervisor y la oficina; todo queda listo para retomar
```

## Qué hace

- **Hilos con líder.** Cada tarea es un hilo con un líder que reparte, revisa y acepta o devuelve cada entrega. Si el líder deja de responder con trabajo esperando, otro agente lo releva.
- **Reclamos y puntos de control.** Nadie toca archivos sin reclamarlos; antes de editar se avisa del plan y en cada hito se informa, con el estado de git del worktree. Un reintento parte de esos puntos de control, no de la memoria del agente que murió.
- **Un worktree por agente y tarea** en los repositorios git (`<repo>\.claude\worktrees\<agente>-<tarea>`), con tope por agente. La limpieza solo quita los integrados y limpios; los demás te los lista.
- **Tú apruebas lo que importa.** Se autoaprueba lo de solo lectura, lo que escribe dentro de la mesa y los relevos; lo que escribe en un repositorio o carpeta de fuera, usa la red para algo más que leer o es irreversible (push, merge, release, borrado) te espera.
- **Supervisor sin modelo.** Distingue un agente libre, caído, colgado, sin cuota o sin sesión; marca huérfano el encargo de un proceso muerto, avisa al líder y a ti (notificación de Windows) en tres partes —qué pasó, qué hice, qué necesito— y lo cuenta en una bitácora diaria. Tras una suspensión del PC no da falsas alarmas.
- **Tablero y oficina.** Un tablero de consola y una oficina en pixel art en el navegador (solo en `127.0.0.1`, con token), que leen los mismos archivos.
- **Vigía.** Marca lo peligroso en las sesiones de los agentes: borrados fuera de su sitio, push forzado, escribir fuera de la carpeta de trabajo o en lo excluido.

El protocolo que siguen los agentes está en [`plantillas/protocolo.md`](plantillas/protocolo.md); cómo funciona por dentro, en [docs/arquitectura.md](docs/arquitectura.md); los fallos conocidos y su solución, en [docs/fallos-conocidos.md](docs/fallos-conocidos.md).

## Pruebas

`Probar.bat` lo corre todo en copias aisladas en `%TEMP%`, con agentes simulados que no gastan cuota:

| Prueba | Qué comprueba |
|---|---|
| `pruebas\caos.ps1` | agente muerto a mitad y su reintento con puntos de control, escalado tras 3 intentos, JSON dañado, pestaña cerrada, cuota agotada, sesión caducada, encargo colgado, reclamo caducado, reinicio seguro, cortar sin tocar otro encargo, notas de desconocidos, exclusiones, autoaprobación por tipo, salto de reloj por suspensión, líder con dos fuentes, worktree sucio de un agente muerto, archivo de hilos viejos y relevo del líder |
| `pruebas\caos-procesos.ps1` | lanzador de procesos con un CLI falso: árbol entero al cortar, encargos de más de 40 000 caracteres, salida en UTF-8, tiempo máximo y PID reutilizado |
| `pruebas\probar-panel.ps1` | panel web: token, origen, 304 sin cambios y tamaño del resumen |
| `pruebas\probar-relevo.ps1`, `probar-vigia-ambito.ps1`, `probar-oficina.ps1` | relevo del líder y reglas del vigía |

## Licencia

Código bajo [MIT](LICENSE). Sin dependencias de terceros: solo PowerShell y las API de Windows. Detalle en [`LICENCIAS.md`](LICENCIAS.md).
