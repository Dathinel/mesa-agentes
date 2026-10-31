> Lo de abajo describe la Cuadrilla v1 (etiqueta `cuadrilla-v1`); la ligera está en `cuadrilla-ligera.md` y D-003.

# Pruebas a mano (las que solo puede juzgar una persona)

## Cuadrilla ligera (D-003)
1. **Desde el celular (Remote Control).** Pide a Claude que delegue algo mecánico de más de 10 min a codex o agy. Esperado: Claude sigue respondiendo mientras el encargo corre, y al terminar te llega un `PushNotification` de una línea con el resultado (hecho / fallo / causa). Si no llega, anota la hora y el id de `cuadrilla.ps1 estado`.
2. **Cerrar la app a mitad.** Con un encargo en marcha, cierra Claude Code. Esperado: `cuadrilla.ps1 estado` lo enseña `interrumpido`, no queda ningún proceso de codex ni agy (Administrador de tareas), y repetir la misma orden lo retoma en el mismo worktree con la cabecera REINTENTO.
3. **Un encargo que compile Rodaje.** Esperado: compila en el worktree con `--add-dir <repo>\.entorno`; si falla al restaurar paquetes, vuelve a lanzarlo con `-Red`.

## Cuadrilla v1 (etiqueta `cuadrilla-v1`; ya retirada)

Lo automático pasa (`Probar.bat`). Esto necesita tus ojos y tu ventana:

1. **Abrir.** Cierra las ventanas de la mesa y ejecuta `Cuadrilla.bat`. Esperado: una sola ventana de Windows Terminal con Claude a la izquierda y Codex, agy y el tablero a la derecha; Claude retoma la conversación de la mesa (`datos\sesion-claude.txt`) y nada más empezar te muestra «[Mesa] Eres claude… Tus reclamos…». En el tablero, «Supervisor: vivo». Con `Cuadrilla.bat nuevo`, conversación nueva.
2. **Cerrar una pestaña.** Cierra el panel de agy con la X. En menos de 2 min: notificación de Windows «Cuadrilla · el panel de agy se cayó…», agy en rojo en el tablero y una línea en `mesa.ps1 bitacora`. `Cuadrilla.bat panel agy` lo reabre en la misma ventana y el tablero vuelve a «libre».
3. **Suspender el PC y volver.** Suspende con la mesa abierta, espera unos minutos y vuelve. Esperado: **ninguna** notificación de caída al despertar; en la bitácora, «Vuelta tras un salto de N min… no aviso de caídas». Si algo sigue caído de verdad, avisa en la vuelta siguiente (30 s después).
4. **Aprobar un encargo desde la cola.** Pídele a Claude que delegue algo que escriba fuera de la mesa (por ejemplo, en un repositorio). Esperado: el encargo sale en «Esperan a <tu nombre>» del tablero con su tipo (`repo`). Apruébalo con `.\mesa.ps1 aprobar -Hilo <id> -N <n>` (o recházalo con `rechazar -Motivo`); al aprobarlo, el panel del agente lo ejecuta a la vista.
5. **Parar el supervisor.** `Cuadrilla.bat cerrar` dejando abiertos los paneles: a los 3 min cada panel avisa en rojo de que el supervisor no da señales y el tablero lo marca PARADO.
6. **Oficina.** Se abre sola en el navegador y se ve como siempre; abrir un hilo carga sus mensajes al momento.
7. **App de escritorio de Claude (D-002).** Cierra la app del todo (también el icono de la bandeja) y vuelve a abrirla. En un chat nuevo, el botón de herramientas debe listar el servidor `cuadrilla` con 8 herramientas. Pide «lee el hilo 20261020-prueba-de-la-app-de-escr de Cuadrilla»: debe mostrar la nota de `claude-app`. Pide luego «envía a codex en ese hilo: lista los archivos de docs». Esperado: el encargo queda pendiente y sale en `ver_pendientes`. Al pedir que lo rechace, la app te pide permiso antes de hacerlo, y cada acción queda en `datos\claude-app.log`. Si no aparece el servidor, mira `%APPDATA%\Claude\logs\mcp-server-cuadrilla.log`.
