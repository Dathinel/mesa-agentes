---
name: cuadrilla
description: Delegar trabajo mecánico y comprobable (refactors, pruebas, docs, revisiones de lectura) a codex o agy con una sola orden que termina sola y avisa al acabar. Úsala cuando una tarea lleve más de 5 minutos y no exija criterio; se invoca sola o con /cuadrilla.
---

# Cuadrilla: delegar a codex y agy

Claude dirige; `codex` y `agy` hacen lo mecánico. Una orden lanza el encargo, espera y termina: no hay cola, panel ni proceso residente. Herramienta: `D:\Programas de uso libre\mesa-agentes\herramientas\cuadrilla.ps1`.

## Cuándo delegar
- Sí: lo mecánico y comprobable con una orden (compilar, pruebas, renombrados, docs, revisiones de solo lectura, informes).
- No: diseño, revisión final, publicación, licencias y lo irreversible. Lo que lleva menos de 5 min lo haces tú.
- Modelos (lista en `datos\mesa.json`): codex `gpt-6-luna` para lo mecánico, `gpt-6.1-sol` esfuerzo medio para código normal, `gpt-6-astra` solo para lo difícil; agy `gemini-3.8-flash-*` por defecto. Un encargo a codex y otro a agy pueden ir a la vez; dos al mismo CLI no (el segundo sale `NO LANZADO: ocupado`).

## Cómo
1. Escribe el encargo en `<mesa>\datos\encargos\<tarea>.md` (o en `<repo>\.proceso\diseno\encargos\`) con cuatro apartados: **Objetivo**, **Contexto** (rutas absolutas y reglas del repo), **Hecho cuando** (con la orden que lo demuestra) y **No toques**. El nombre del .md es la tarea: `hdr.md` da el worktree `<repo>\.claude\worktrees\codex-hdr` y la rama `codex/hdr`.
2. Lánzalo en segundo plano (`run_in_background: true`) y sigue con otra cosa; Claude Code te avisa al terminar:
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Programas de uso libre\mesa-agentes\herramientas\cuadrilla.ps1" delegar -A codex -Encargo "<md>" -Dir "<repo>" [-Modelo m] [-Esfuerzo low|medium|high] [-Lectura] [-Red] [-Minutos n]
   ```
   Rutas literales, entre comillas dobles, sin `$`, `(` ni acento grave y sin barra final. `-Lectura` para revisar sin tocar (sin worktree); `-Red` solo si hace falta restaurar paquetes; `-Minutos` sube el tope de 90.
3. Salida: `0` hecho, `2` hecho con aviso (léelos), `1` fallo, `124` tiempo o colgado, `3` no lanzado (el motivo va en la primera línea). Imprime una línea de resumen, la ruta de `datos\trabajos\<id>\resultado.json` y la respuesta. En la carpeta quedan `encargo.md`, `prompt.txt`, `log.jsonl` y `final.txt`.
4. Al acabar, revisa tú en el worktree: lee `avisos` del resultado, `git -C <wt> diff`, compila sin advertencias y pasa las pruebas. Si vale: commit, push de la rama y `gh pr create`. Si no: corrígelo tú o escribe `<tarea>-correccion.md` y relanza con `-Tarea <tarea>` (mismo worktree). Tras unir, `worktrees.ps1 limpiar`.
5. `estado` dice en menos de 1 s qué hay (libre, ocupado, sin cuota hasta HH:MM, interrumpido); `cortar <id>` mata el encargo con su árbol; `cuota` consulta `agy -p /usage` (comprobado el 31-oct: tabla de límites en 5 s) y la última señal sin cuota de cada CLI. Un `interrumpido` (apagón, app cerrada) se retoma repitiendo la misma orden.
6. Si Daniel puede no estar delante (Remote Control o encargo de más de 10 min), mándale un `PushNotification` de una línea al terminar; si pide ver el cambio, el diff con `SendUserFile`.

## Reglas que ya aplica la herramienta
Un encargo por CLI; sandbox limitado al worktree (`.entorno` del repo en lectura/escritura); sin red por defecto; `git` del CLI no escribe refs ni hace push; nada bajo `datos\excluidos.txt`; corte a los 20 min sin salida; rechazo inmediato si el CLI está sin cuota.
