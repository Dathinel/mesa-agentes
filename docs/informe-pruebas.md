# Informe de las pruebas de la mañana (20 de octubre)

Arranque: `Cuadrilla.bat cerrar` y después `Cuadrilla.bat` a las 11:00. Antes se pararon a mano los paneles viejos: agy (colgado desde las 10:49, su proceso seguía vivo sin hijos), codex (libre) y el tablero. Después, el supervisor y la oficina se recargaron solos varias veces al cambiar el código; no hubo otro arranque completo.

Capturas: `docs\pruebas-manana\` con `p<n>-antes|durante|despues-<vista>-<ancho>.png`. Vista final del Resumen y de la oficina a 1366x768: `docs\pruebas-manana\p1-despues-resumen-1366.png` y `docs\pruebas-manana\p1-despues-oficina-1366.png`.

## Pruebas

| # | Esperado | Obtenido | Capturas | Estado |
|---|---|---|---|---|
| 1 | Portada con datos reales de menos de 30 s; enlaces Resumen y oficina | Antes: «Datos de hace 13 s». Después: «Datos de hace 10 s». `/`, `/oficina.html` y `/api/ping` responden 200. `localhost` redirige a `127.0.0.1` (302). El Resumen enlaza a la oficina (`resumen.js`) y la oficina tiene «Resumen» (`index.html:25`). Los enlaces no se pulsaron con ratón: se comprobaron en el código y por HTTP. | p1-antes-*, p1-despues-* | Pasa |
| 2 | Encargo corto real a codex: mientras corre, tarjeta con encargo, carpeta y salida en vivo; al terminar, Libre | Encargo #92 en `20261019-ronda-2-pendientes-y-ver`, corre en `D:\Programas de uso libre\mesa-agentes`. Salida en vivo legible (comandos y textos, no JSON). Al terminar: Libre. Codex reportó 88 y 69 líneas (`docs\informe-noche.md`, `docs\estado-contrato.md`) y la espera de 90 s. | p2-antes-*, p2-durante-*, p2-despues-* | Pasa (ver incidencias 2 y 3) |
| 3 | Panel de codex cerrado: Apagado y sin alerta de caída. Reabrir: Libre | Cierre con señal de consola equivalente a Ctrl+C: codex pasa a «apagado», motivo «panel cerrado», sin alerta. Reabrir con `Cuadrilla.bat panel codex`: Libre (panel PID 30224, con el código nuevo). Cierre con la X: ver «Sin resolver». | p3-antes-*, p3-durante-*, p3-despues-* | Pasa en el cierre por señal; la X en la pestaña real queda sin probar aquí |
| 4 | Matar `servidor.ps1`: el supervisor lo reabre en menos de un minuto y lo anota | Servidor PID 20332 detenido a las 11:16. La oficina respondió a los 29 s. Bitácora 11:17: «La oficina no respondía: la volví a abrir.» Con la mesa caída, el Resumen muestra «Sin conexión con la mesa» sin datos de ejemplo. | p4-antes-*, p4-despues-*, p4-mesa-caida-resumen-1366.png | Pasa |
| 5 | Franja de la oficina igual que el tablero | Oficina (DOM renderizado): Trabajando 1, Libre 2, Esperando a Daniel 0, Sin cuota 0, Caído 0, Apagado 0, Te necesito 0. Tablero: las mismas siete cifras. Se comprobó en modo normal; el modo TV usa la misma franja. | p5-franja-vs-tablero.txt, p5-despues-* | Pasa (con todas las cifras a 0 salvo libre y trabajando; los casos con cifras distintas de cero no se han dado en la prueba) |
| 6 | codex y agy interactivos en pestañas nuevas, sin escribirles; nombres de proceso y línea de comandos; el Resumen los detecta | codex: `node.exe` PID 1192 con `@openai\codex\bin\codex.js` (hijo `codex.exe` PID 28184 y dos daemons). Resumen: CLI «node.exe 1192»; tras cerrarlo, CLI «sin proceso». agy: `agy.exe` PID 23304, línea `agy`. Resumen: CLI «agy.exe 23304» mientras estaba abierto. Tras cerrar ambos: CLI null. | p6-antes-*, p6-durante-*, p6-despues-* | Pasa |
| 7 | Con la app de escritorio de Claude abierta y ninguna CLI de Claude: Claude Apagado | No ejecutada. Esta sesión es un proceso `claude.exe` (PID 19872) y hay otro (PID 23000). No hay app de escritorio `Claude.exe` abierta. No puedo cerrar las CLI sin cerrarme. Lo que sí está comprobado: con CLI abierta, Claude sale Libre con «sesión de claude abierta» (sin latido), y el filtro usa `claude.exe` en mayúsculas exactas (`supervisor.ps1`). | p7-antes-* | Pendiente de Daniel |

## Arreglos y commits

Commits locales en `main` (sin push):

| Commit | Qué | Pruebas |
|---|---|---|
| `db02448` | Vigía: lecturas de ámbito excluido sin alerta; temporales propios exentos; alertas repetidas agregadas (entrega de codex) | probar-vigia-ambito 20/20 |
| `edc5195` | mesa: `cortar` deja marca de corte antes de matar la CLI; `aprobar` rechaza lo que no esté pendiente o escalado; `alertas -Revisada` conserva el mapa de motivos | probar-cortes 0 fallos |
| `4296268` | Supervisor: recarga automática con guardia de sintaxis (4.1); Claude por sesión de CLI, sin latido (3.2); identidad de paneles (PID, hora, línea); cortes como alerta «cortado» (3.3) | probar-recarga 0 fallos; probar-cortes 0 fallos |
| `f8dc769` | Panel: el cierre con la X cuenta como cierre limpio (marca de cierre por cierre de consola) | probar-cierre-panel 0 fallos (consola oculta) |
| `4a01d68` | Estado: un solo recuento (franja) para oficina y tablero; salida viva legible; identidad `cli`; bandeja solo de hilos abiertos (3.8, 4.3) | probar-estado 11/11; prueba 5 |
| `77d8338` | Resumen y oficina (entrega de agy, más dos retoques míos): etiqueta de líder con un solo hilo y «(+N)» (3.1); sin datos de ejemplo ni cero engañoso sin conexión (4.2); orden de «Te necesito» (3.6); procesos en la tarjeta (4.3); oficina a 1366 (3.7); textos de alerta y «×N» (3.4) | probar-resumen 15/15; probar-panel 0 fallos |

Sin commit, en la mesa y en los datos:
- **3.5 Copiar orden**: se ejecutó cada orden. `pendientes -Para <agente>`, `leer -Hilo`, `alertas -Revisada <id>` funcionan; `reintentar` rechaza un encargo hecho; `aprobar` rechaza uno que no esté pendiente (commit `edc5195`). La orden `revisar-alerta` que aparecía antes no existe; la interfaz usa `alertas -Revisada`.
- **3.9 agy «Caído» a las 10:51**: no se cerró a mano. El proceso del panel (PID 11380) seguía vivo, sin hijos y sin latido desde las 10:49: estaba colgado. Causa exacta no confirmada. Ahora el motivo dice «el panel sigue abierto (pid N) pero no da latido».
- **3.10 Alertas del vigía de anoche**: las 11 de agy sobre `panel/resumen.*` (00:14 a 00:19, hora local) son mías, de la integración de su entrega. Explicadas en el hilo y marcadas como revisadas. Las de hoy (arranque limpio y limpieza de pruebas) también, con explicación para codex.
- **3.8 Bandeja**: las entregas de `modelado-blender`, `sync-inicio` y `mesa-github` las revisó agy (no yo: nadie revisa su propia entrega) y están aceptadas. Se archivaron los hilos `20261018-cubre-jeringas-10-ml-inf` y `20261019-mesa-lista-para-github-d`. `20261018-prueba-de-coordinacion-p` no se puede archivar: su inventario tiene tareas de una ronda anterior sin entregar.
- **Entregas aceptadas en el hilo**: `manana-vigia-codex`, `manana-prueba2-codex`, `interfaz-agy`, `identidad-agy`.

## Incidencias durante las pruebas (todas mías salvo donde se indica)

1. **Captura de Edge**: Windows PowerShell 5.1 no entrecomilla rutas con espacios. Corregido con la línea de argumentos citada a mano y reintentos.
2. **Encargo de prueba 2 bloqueado**: el primer encargo (#88) chocó con el reclamo `manana-vigia-codex` de codex, que estaba entregado y sin aceptar. Lo acepté (tras probar su vigía 20/20) y relancé la prueba como #92.
3. **Relanzamiento accidental de #92**: `aprobar -N 92` sobre un encargo ya hecho lo volvió a lanzar; el comando se quedó esperando 200 s y codex repitió la espera. Lo corté con `mesa.ps1 cortar` (queda como «cortado por claude», no como fallo). Desde el commit `edc5195`, `aprobar` no admite lo que no esté pendiente.
4. **Codex interactivo**: `codex` en una pestaña no arrancó (es un `.ps1` de npm). Se abrió con `cmd /d /k codex`.
5. **Tablero**: `tablero.ps1` escribe con `Write-Host`, así que la salida a fichero salió vacía en las primeras capturas. Corregido en la captura; las salidas por paso están en este informe.
6. **Franja**: el tablero y la oficina contaban distinto (alertas de 24 h frente a alertas de alto nivel). Ahora los dos leen la misma cuenta de `estado.ps1`.
7. **Vigía, errores de «archivo en uso»**: `Vigia-RegistrarAlerta` reescribe `alertas.jsonl` sin candado. Aparece en `errores-paneles.log`. Pendiente de codex; anotado en el hilo.
8. **Prueba de recarga**: fallaba por la codificación de la lectura de la bitácora en la prueba. Corregido.
9. **Renombrado de temporales**: mis carpetas de prueba en `%TEMP%` tenían nombres que el vigía no eximía. Ahora son `cuadrilla-prueba-*`.

## Sin resolver

- **Prueba 7**: pendiente de Daniel. Cerrar las dos CLI de Claude (PID 19872 y 23000) y abrir la app de escritorio; Claude debe salir Apagado.
- **Prueba 3, cierre con la X en la pestaña de Windows Terminal**: no se puede automatizar desde aquí. Con `taskkill` sin `/F` el panel de la pestaña no reacciona (no tiene ventana propia). El camino de la X se comprobó en consola oculta (`probar-cierre-panel`, 0 fallos). Daniel debe cerrar un panel con la X y confirmar que sale en Apagado.
- **Prueba 3, cierre por señal**: la señal de consola equivalente a Ctrl+C no es una pulsación de teclas, pero tampoco es el ratón. Se hizo con el panel real.
- **Prueba 2, «su panel muestra el encargo»**: la tarjeta y el log del encargo lo muestran. No puedo leer el contenido de la ventana del panel.
- **Encargo #107 de agy**: entregó (`identidad-agy`), pero su registro quedó en «fallo» por el código de salida. Hay que revisar `ejecutar.ps1` en ese caso.
- **Hilos abiertos viejos**: 18 hilos de los que Claude es líder, de octubre 17 a 19. La etiqueta del Resumen muestra «(+18)». Conviene cerrar o archivar los que estén terminados.
- **Salida de agy en la tarjeta**: muestra la salida de su propio comando, con texto de error. No se filtra.
- **Tablero, registros por paso**: los ficheros de salida del tablero de las pruebas 1 a 4 y 6 salieron vacíos (incidencia 5). Los datos de cada paso están en este informe.
- **Enlaces con ratón**: no se pulsaron. Se comprobaron en código y por HTTP.

## Cifras

- Suites al cierre: `caos` 0 fallos; `caos-procesos` 0 fallos; `probar-estado` 11/11; `probar-panel` 0 fallos; `probar-resumen` 15/15; `probar-recarga` 0 fallos; `probar-cortes` 0 fallos; `probar-cierre-panel` 0 fallos; `probar-vigia-ambito` 20/20.
- Resumen y oficina: `node --check` sin errores en `resumen.js`, `oficina.js` y `reclamos.js`.
