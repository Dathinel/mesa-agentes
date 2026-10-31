# Informe de limpieza del 24-oct

**Cola de la nube** (`.proceso/nube/cola.md`, commit 271deb7 en gemini-flujo y main)
- 351 tareas numeradas: 26 abiertas se quedan; 325 van a `nube/archivo/cola-cerrada-2026-10.md` (269 ya «hecha» más 56 cerradas con su PR). Además, 31 secciones de notas y listas de «PR sin revisar» pasan al archivo. cola.md baja de 3563 a 213 líneas.
- Las 56 cerradas llevan la línea «Cerrada el 24-oct» con el PR (por ejemplo 312-331 con #296 a #336, y las cazas 350-381 con #340 a #389). La 12 se cierra porque `ReverseFrameReader` y sus pruebas ya están en main.
- Se quedan abiertas a propósito: 360, 370, 373, 374 y 382 (cazas sin PR), 285, 286, 292, 293, 306, 311 (sin PR), 332 (PR #330 cerrado sin unir), 333, 290 speeddrift (PR #285 cerrado sin unir), 294 (rama de Gemini sin PR), 36, 38, 282, 288 (a medias) y 335-341 (BACKLOG-1.0.2 las mantiene abiertas).
- Aviso: los scripts de la nube (`generar-cola-nube-caza.ps1`) toman el número máximo de cola.md más uno. La 382 sigue abierta, así que no se reutilizan números. Si se cierra, hay que anotar el siguiente número.
- `BACKLOG-1.0.1.md` pasa a `.proceso/agentes/archivo/`; la ruta se actualizó en `LIDER.md` y `lider-estado.md`, que están sin versionar.

**Ramas remotas de Dathinel/rodaje** (19 aparte de main, no 18)
- Borrada 1: `claude/caza-paquete-archivo-h9lf3l` (su único archivo es idéntico al de main por el PR #370).
- Ninguna otra está contenida en main ni tiene PR MERGED. Para Daniel, con lo que tienen de distinto:
  - Duplicadas de lo ya unido en otro PR (1 commit, 1 archivo de pruebas cada una): `caza-formato-proyecto-je8zju` (#338 cerrado; unido #334), `caza-nucleo-modelo-model-g01rps` (sin PR; unido #308), `caza-paquete-catalogo-aukq0b` (#354 cerrado; unido #347), `caza-contenido-paquetes-be6qx9` (#301 cerrado; unido #298; toca además PresetReader).
  - Con trabajo que parece propio: `ci-speeddrift` (medios largos en un paso de la nocturna), `fix-shutdown-report-flaky-test-qb6pr1` (ModuleProcess y su prueba, tarea 332), `gemini/safezone-preset-tests` (tarea 294), `rev-cola-biblioteca-sincronia-linksync` (LinkSync), `main-verde-traducir` (1 archivo), `titulo-shaders-ci` (2), `congelado-descargas` (8 archivos, 4 ya en main), `prueba-externa` (6 commits de máquinas limpias, 11 archivos), `revision/interfaz-biblioteca` (1 doc).
  - Con varios commits: `defectos-pruebas-v1` (8 commits, 18 archivos, 12 idénticos a main), `dep-inestables-4` (7 commits, 6 archivos), `rev-protocol-pool-minthreads` (2 commits, 6 archivos).
  - `cola-revision-bloque-9-10`: solo toca la cola vieja `docs/nube/cola.md`; probablemente sin uso.
  - `docs/estado-24oct`: PR #441 abierto, no tocar.

**Worktrees**
- Quitados 4: `distribucion`, `hallazgos-agy`, `pistas` (clean, tip igual al de su PR unido #439, #440, #437) y `.proceso/.claude/worktrees/agent-a8695510ee1f5f87b` (clean, sin trabajo).
- Se dejan: `agent-a99d…`, `agent-ab15…`, `complementos-v1`, `copilot-ui-step17/18` (su rama está en main pero tienen cambios sin confirmar), `docs-estado-24oct` (PR abierto), la raíz de Rodaje (rama `codex/ia-aplicar-auto`, de otra sesión) y los de hoy (`codex-codex-*`, `agy-agy-*`, `claude-hdr-plan`).
- Los 3 de unos 3 GB de `.proceso` (`agent-a4b8…`, `agent-a52d…`, `agent-ad8a…`, 3,1 GB en total) se dejan: dentro llevan worktrees de Rodaje con ramas sin unir de 12-oct (`prueba-formatos` 5 commits, `docs-guia-usuario` 3, `pulido-estetico` 2; 4, 3 y 2 sin equivalente en main). Quitarlos libera los 3,1 GB sin perder commits (las ramas quedan), pero decide Daniel.

**Datos de la Cuadrilla**
- `mesa.ps1 limpiar` no rota los .jsonl; el supervisor solo los mueve enteros al pasar de 5 MB (actividad) o 2 MB (alertas). Se rotó a mano, con el mismo candado (`Mesa-Bloquear`): `actividad.jsonl` pasa de 14531 a 4563 líneas (4,9 MB a 1,4 MB); 9968 líneas anteriores a 7 días van a `datos\archivo\actividad-20261024.jsonl` (3,5 MB). `alertas.jsonl` no tiene nada anterior a 7 días (416 líneas), no se tocó.
- Comprobado después: `/api/ping` del panel (puerto 8790) responde `{"ok":true}` y `mesa.ps1 hilos` lista los hilos.

**Pendiente de Daniel:** decidir las ramas de arriba, los 3,1 GB de worktrees de `.proceso` y si se borra la rama `cola-revision-bloque-9-10`.
