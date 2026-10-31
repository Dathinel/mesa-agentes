<h1 align="center">Cuadrilla</h1>

<p align="center">
  Claude Code dirige; Codex y Antigravity (agy) hacen lo mecánico. Una orden lanza el encargo, espera y termina.<br>
  Sin servidor, sin cuentas nuevas y sin ningún proceso residente: 0 % de CPU en reposo.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-E8833A?style=flat-square&labelColor=1D1D1D" alt="Licencia MIT"></a>
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-E8833A?style=flat-square&labelColor=1D1D1D" alt="Windows 10 y 11">
  <img src="https://img.shields.io/badge/PowerShell-5.1-E8833A?style=flat-square&labelColor=1D1D1D&logo=powershell&logoColor=white" alt="PowerShell 5.1">
  <img src="https://img.shields.io/badge/pruebas-49%2F49-E8833A?style=flat-square&labelColor=1D1D1D" alt="Pruebas 49 de 49">
</p>

## Qué necesitas

Los CLI oficiales `codex` y `agy`, instalados y con la sesión iniciada en tu cuenta, y Claude Code. Cuadrilla no instala nada, no guarda credenciales y no lee transcritos de sesión: cada CLI usa su propia sesión y Cuadrilla solo lee lo que el CLI imprime en el encargo.

## Cómo se usa

1. `herramientas\instalar.ps1`: crea `datos\mesa.json` y `datos\trabajos\` e instala la skill `cuadrilla` en `%USERPROFILE%\.claude\skills\`. Con ella, Claude Code sabe cuándo delegar y cómo.
2. Claude escribe el encargo en un `.md` (objetivo, contexto, hecho cuando, no toques) y lo lanza en segundo plano:
   ```
   herramientas\cuadrilla.ps1 delegar -A codex -Encargo "<md>" -Dir "<repo>" [-Modelo m] [-Esfuerzo low|medium|high] [-Lectura] [-Red] [-Minutos n]
   ```
   En un repositorio el agente trabaja en su propio worktree (`<repo>\.claude\worktrees\<agente>-<tarea>`), sin red por defecto y con `git` sin poder escribir refs ni hacer push: Claude revisa el diff, confirma y abre el PR.
3. Salida `0` hecho, `2` hecho con aviso, `1` fallo, `124` tiempo o colgado, `3` no lanzado (con el motivo). Todo queda en `datos\trabajos\<id>\resultado.json`.
4. `estado` (qué hay en marcha, sin cuota hasta qué hora, interrumpidos), `cortar <id>` y `cuota`.

## Cifras

| Qué | v1 (hilos, supervisor y panel) | Ligera |
|---|---|---|
| Procesos en reposo | supervisor (12-15 % de un núcleo) + trabajador del panel (34 %, 16 000 s en 13 h) | 0 |
| Código activo | ~13 000 líneas | 1 040 (herramientas) + pruebas |
| Encargo rechazado (CLI ausente, ruta mala, modelo inválido, sin cuota) | se encolaba o fallaba a los minutos | salida 3 en menos de 2 s, sin arrancar el CLI |
| agy mudo | 90 min colgado | corte a los 20 min sin salida (`inactivo_min`) |

## Pruebas

`Probar.bat` corre `pruebas\probar-cuadrilla.ps1` (32 casos: salidas, rechazos, cortes, git) y `pruebas\caos-procesos.ps1` (17 casos del lanzador) en copias aisladas de `%TEMP%` con CLI falsos: no gasta cuota. `pruebas\probar-real.ps1` lanza un encargo de solo lectura a cada CLI real con modelos baratos.

## Licencia

Código bajo [MIT](LICENSE). Sin dependencias de terceros: solo PowerShell y las API de Windows. Detalle en [`LICENCIAS.md`](LICENCIAS.md). Decisiones en [`docs/decisiones.md`](docs/decisiones.md).
