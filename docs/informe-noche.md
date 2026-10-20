# Informe de la noche (19 a 20 de octubre)

Punto de control: etiqueta `antes-noche-20oct` (commit `96300a8`) y copia de `datos\` en `datos\archivo\antes-noche\`.

## Qué quedó hecho (commits en `main`, sin push)

| Commit | Qué |
|---|---|
| `fdec149` | Estado unificado: el supervisor escribe los seis estados; vigía en el supervisor; relanzado de la oficina; servidor sin apagado por inactividad. |
| `96300a8` | Detección de procesos: codex como `node.exe` por línea de comandos; `claude` distinto de `Claude.exe`. |
| `878a67c` | Arranque de Claude (trabajo de codex, probado y commiteado). |
| `36cb1a7` | Encargo con carpeta inexistente: queda pendiente con motivo, no se trabaja en otra carpeta (punto 5). |
| `be1adc3` | Hilo con `hilo.json` dañado: sale como «dañado» y conserva sus pendientes (punto 9). |
| `94aa040`, `83fb96f` | Vista Resumen de agy, integrada en `main`. |
| `0aff50b` | Cada tarjeta: encargo en curso, carpeta donde corre, salida reciente y último resultado. |
| `dcf1e1e` | Oficina y Resumen leen el mismo estado: portada Resumen, token bien inyectado, pixel art a resolución real, franja urgente. |
| `4777ef1` | Prioridad: la cuota agotada gana a un escalado anterior (corrige un fallo de `caos.ps1`). |
| `51bcf10` | Lanzador de codex (`lanzador-r2`): identidad no fatal, log y final por intento, causa por evento final, stdin. Aceptado tras revisión. |
| `3e6b979` | Regla de aplicar el plan completo, en la plantilla; resumen bajo 60 KB. |
| `7c707ad` | Servidor: `localhost` redirige a `127.0.0.1`; el token solo viaja por cabecera. |
| `9023ddc` | Tarjetas en vivo y capturas. |

Puntos del encargo:

- **1 (una sola fuente de estado):** hecho. El supervisor decide; `estado.ps1`, la oficina y el tablero lo leen. Contrato en `docs\estado-contrato.md`.
- **2 (identificación del proceso):** parcial. codex por línea de comandos y claude por nombre exacto. No se identifica por PID en el panel.
- **3 (vigía fuera del navegador):** hecho.
- **4, 6, 7, 10, 11, 12, 13, 14 (lanzador):** hechos por codex y aceptados. El 13 (arranque suspendido) queda como riesgo bajo documentado.
- **5 (carpeta inexistente), 9 (hilo dañado):** hechos, con pruebas.
- **8 (lectura incremental):** parcial. Hay `generado` y `error_trabajador`, y la oficina se actualiza cada ~12 s (criterio < 30 s cumplido). La lectura incremental no está hecha: medí 10 s por cálculo y el cuello está en la ventana de siete días y los tokens, no en el archivo de sesión.
- **15 (servidor):** hecho.
- **Oficina (bloque 3B):** un cartel por estado, caído en rojo, sin VUELVO PRONTO, sala sin contradicción, lienzo a devicePixelRatio, texto que no llega a 9 px real se quita, franja urgente en HTML, máximo 30 fotogramas/s.
- **Vista Resumen:** integrada con el estado unificado. Si la mesa no responde, dice «datos de ejemplo» en rojo.
- **0a:** parcial. En este PC `claude.exe` es la CLI en `.local\bin`; la app de escritorio no estaba abierta. codex y agy no estaban en ejecución, así que sus nombres no se han confirmado en una sesión interactiva.
- **0b:** hecho. Codex lanzó un `Start-Sleep 900` (PID 26280). Corté el encargo #68 con `mesa.ps1 cortar` y el proceso dejó de existir. El Job sí cubre el árbol.
- **0c:** hecho. La consola usa CP850. `node` escribe UTF-8 correcto con redirección UTF-8. Un proceso hijo de PowerShell escribe en CP850 y sale revuelto. El lanzador solo arranca CLIs, así que hoy no afecta; queda anotado.
- **0d:** escalado 100% (AppliedDPI 96).

## Qué no y por qué

- **Lectura incremental del cálculo (8):** no hecha; el criterio de 30 s ya se cumple.
- **Identidad del proceso por PID en el panel (2):** no hecha.
- **Pruebas con una ventana real de codex y agy:** no hechas; los nombres de proceso de esos dos no están confirmados.
- **`caos.ps1`, caso «Encargo colgado»:** la comprobación cambió. Antes esperaba el estado `colgado`; ahora espera `trabajando` con la alerta `colgado`, porque el vocabulario son seis estados. Es un cambio deliberado.
- **Alertas del vigía:** salen escrituras en archivos reclamados por otro agente, algunas de mis ediciones sobre archivos que agy tenía reclamados. No las he marcado como revisadas.
- **Alerta «fallido» tras un corte a propósito:** #68 y #51 se cortaron a mano y siguen apareciendo como «sin éxito» hasta que el agente complete otro encargo o se relance con `reintentar`. Es el comportamiento previsto, pero puede confundir.

## Qué se borró y si se recuperó algo

- **No se borró ninguna rama ni ningún worktree.** `main`, `publicable` y `agy/vista-resumen-agy` existen, y la historia de `main` es lineal.
- **Lo que marcó el vigía:** el registro muestra commits y búsquedas de historial en esas horas, no borrados de ramas. Las entradas `branch -D` del registro son de sesiones de Rodaje, no de esta franja.
- **El borrado recursivo (04:13 UTC):** el comando del registro está truncado. Era un `Remove-Item` sobre carpetas `%TEMP%\cuadrilla-limpio-*`. Esas carpetas ya no existen. No puedo afirmar con el registro qué contenían.
- **Commits sin referencia:** tres versiones anteriores del `initial` de `publicable` (`43acae9`, `7810e50`, `d988392`). Las protegí con `refs\rescate\*`.
- **Trabajo sin integrar:** no he encontrado ninguno perdido. Todo lo que estaba en worktrees está integrado o commiteado.

## Capturas

Están en `docs\capturas-noche\`:

- `resumen-1366.png`, `resumen-1920.png`: vista Resumen.
- `oficina-1366.png`, `oficina-1920.png`: oficina pixel art.

Se tomaron en modo sin interfaz con Edge. La prueba `pruebas\probar-resumen.ps1` (15 de 15) y las de `probar-panel` también pasan.

## Pruebas al cierre

| Suite | Resultado |
|---|---|
| `pruebas\caos.ps1` | 0 fallos |
| `pruebas\caos-procesos.ps1` | 39 de 39 |
| `pruebas\probar-estado.ps1` | 11 de 11 |
| `pruebas\probar-panel.ps1` | 0 fallos (resumen 56,3 KB, bajo el techo de 60 KB) |
| `pruebas\probar-resumen.ps1` | 15 de 15 |

## Cinco cosas que debes probar tú por la mañana

1. **Abre `http://127.0.0.1:8790/` (no `localhost`) y mira la portada.** Debe redirigir a `127.0.0.1`, la portada tiene que mostrar datos reales con «Datos de hace N s» menor de 30, y el botón «Ver Oficina Pixel Art» debe llevar a `/oficina.html`. Vuelve a `/` desde la oficina con el enlace «Resumen».
2. **Lanza un encargo corto a un agente** (por ejemplo `delegar.ps1 -A codex` con algo que tarde un minuto). Mientras corre, en su tarjeta debe aparecer «Encargo #n en <hilo> · corre en <carpeta>» con la salida que va diciendo.
3. **Cierra el panel de codex (Ctrl+C en su ventana) y espera 2 minutos.** En la oficina y en el Resumen debe pasar a «Apagado» (no «Caído»), y no debe aparecer ninguna alerta de caída. Luego vuelve a abrirlo con `Cuadrilla.bat` y debe volver a «Libre».
4. **Mata el proceso de la oficina** (`servidor.ps1` en el Administrador de tareas) y espera un minuto. El supervisor debe volverlo a abrir, y la bitácora (`datos\bitacora\2026-10-20.md`) debe decirlo.
5. **Mira la franja inferior de la oficina en modo TV** (botón Modo TV): los contadores (Trabajando, Libre, Esperando a Daniel, Sin cuota, Caído, Apagado) y «Te necesito» deben coincidir con el tablero (`herramientas\tablero.ps1 -UnaVez`). Si no coinciden, dilo: es un fallo.

## Decisiones tomadas sin preguntar

- El techo del resumen queda en 60 KB: se quitaron dos campos sin lector (`calibracion_mensaje` y `ultimos_archivos`).
- La regla de la mesa vive en `plantillas\protocolo.md`, y `CLAUDE.md`, `AGENTS.md` y `GEMINI.md` se regeneraron con `instalar.ps1 -Regenerar`. Los tres siguen ignorados por git, como antes.
- El reclamo `publicable` sigue siendo mío. El de `lanzador-r2` se soltó al aceptar la entrega, y el de `vista-resumen` al integrarla.
- Se cortaron a mano los encargos #51 (agy) y #68 (codex) porque agy llevaba 20 minutos sin avance con su entrega ya hecha (#56), y el 0b lo exigía.
