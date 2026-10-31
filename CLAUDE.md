# Cuadrilla (mesa-agentes)

Una orden que delega un encargo a `codex` o `agy`, espera y termina. Claude dirige y revisa; no hay supervisor, panel ni proceso residente (D-003, `docs/cuadrilla-ligera.md`). Repo solo local, sin remoto: respaldo con `git bundle` en `D:\Respaldos\cuadrilla\`.

## Orden
`herramientas\cuadrilla.ps1` con `delegar`, `estado [<id>]`, `cortar <id>` y `cuota`. El uso completo está en la skill `plantillas\cuadrilla\SKILL.md` (instalada en `%USERPROFILE%\.claude\skills\cuadrilla\` con `herramientas\instalar.ps1`).

## Dónde está cada cosa
- `herramientas\`: `cuadrilla.ps1`, `proceso.ps1` (Job con KILL_ON_JOB_CLOSE), `comun.ps1`, `worktrees.ps1`, `git-bloqueo\` (hook que impide escribir refs en el CLI), `instalar.ps1`.
- `datos\` (no versionado): `mesa.json`, `excluidos.txt`, `encargos\` y `trabajos\<id>\` (encargo.md, prompt.txt, log.jsonl, final.txt, resultado.json). Lo del sistema viejo está en `datos\archivo\v1-2026-10-25\`.
- `pruebas\`: `probar-cuadrilla.ps1`, `caos-procesos.ps1`, `probar-real.ps1`; `Probar.bat` corre las dos primeras con CLI falsos, sin gastar cuota.

## Reglas
- Solo los binarios oficiales de los CLI con su propia sesión; nada lee, guarda ni intermedia tokens, credenciales ni transcritos de sesión.
- Sin simular teclas ni abrir programas con interfaz. Nada bajo `datos\excluidos.txt`.
- Un cambio de la Cuadrilla se une a `main` con `Probar.bat` en verde. Commits en español.
- Al abrir sesión: `cuadrilla.ps1 estado` enseña lo interrumpido; se retoma repitiendo la orden.

## Siguiente paso
Ver «Pendiente» en `docs/cuadrilla-ligera.md` y D-003 en `docs/decisiones.md`.
