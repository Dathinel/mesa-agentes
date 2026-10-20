# Para retomar la mesa

## Estado (20 oct, 12:10)
- Mesa cerrada: supervisor, servidor, paneles de codex y agy y tablero parados. Sin encargos en ejecución.
- Últimos commits en `main` (locales, sin push): `6ad158b` (cerrar hilos), `348bffe` (etiqueta de líder), `3da2e5f` (informe de pruebas), `77d8338` (Resumen y oficina), `4a01d68` (franja única), `f8dc769` (cierre con la X), `4296268` (supervisor), `edc5195` (mesa), `db02448` (vigía).
- Informes: `docs\informe-pruebas.md` (pruebas de la mañana), `docs\informe-noche.md`.

## Pendientes
1. **Candado de `alertas.jsonl` en el vigía.** `Vigia-RegistrarAlerta` reescribe el fichero sin `Mesa-Bloquear`; causa los errores de archivo en uso en `datos\errores-paneles.log`. Dueño: codex. No empezado.
2. **#107 de agy marcado «fallo» aunque entregó** (`identidad-agy`). Revisar el código de salida en `herramientas\ejecutar.ps1`. No empezado.
3. **Prueba 7**: Claude debe salir Apagado con la app de escritorio abierta y ninguna CLI. Hay que cerrar las CLI de Claude (PID 23000 y la sesión donde se retoma esto) y abrir la app. Para Daniel.
4. **Cerrar un panel con la X real** en la pestaña de Windows Terminal debe salir en Apagado. El camino se probó en consola oculta (`pruebas\probar-cierre-panel.ps1`), no en la pestaña. Para Daniel.
5. **Hilos abiertos y por qué**:
   - `20261018-prueba-de-coordinacion-p`: #1 (codex) y #64 (agy) huérfanos sin relanzar; seis tareas del inventario sin entregar. Decidir si se relanzan o se dan por cancelados.
   - `20261017-encargo-encargo-oficina-2`, `-oficina-3` y `20261018-encargo-encargo-v3-visua`: encargo #2 de agy (entrega de octubre) pendiente de decisión de Daniel.
   - `20261019-ronda-2-pendientes-y-ver` (esta ronda): `publicable` (claude) y `vista-resumen` (agy) sin aceptar.
6. **Doce hilos terminados ya cerrados** con `mesa.ps1 cerrar`. Ver el registro de cada hilo.

## Cómo arrancar la próxima vez
1. `Cuadrilla.bat` desde la carpeta de la mesa. Abre Claude, los paneles de codex y agy, el tablero, el supervisor y la oficina en `http://127.0.0.1:<puerto>/` (el puerto está en `datos\puerto.txt`).
2. Si ya hay paneles viejos abiertos, ciérralos antes (Ctrl+C en su ventana) o `Cuadrilla.bat cerrar` para el supervisor y la oficina; los paneles hay que cerrarlos a mano.
3. El supervisor se recarga solo cuando cambia un script; no hace falta reiniciarlo tras cada cambio.
4. Comprobación rápida: `herramientas\tablero.ps1 -UnaVez` y `pruebas\caos.ps1`.
