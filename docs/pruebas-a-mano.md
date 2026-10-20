# Pruebas a mano (las que solo puede juzgar una persona)

Lo automático pasa (`Probar.bat`). Esto necesita tus ojos y tu ventana:

1. **Abrir.** Cierra las ventanas de la mesa y ejecuta `Cuadrilla.bat`. Esperado: una sola ventana de Windows Terminal con Claude a la izquierda y Codex, agy y el tablero a la derecha; Claude retoma la conversación de la mesa (`datos\sesion-claude.txt`) y nada más empezar te muestra «[Mesa] Eres claude… Tus reclamos…». En el tablero, «Supervisor: vivo». Con `Cuadrilla.bat nuevo`, conversación nueva.
2. **Cerrar una pestaña.** Cierra el panel de agy con la X. En menos de 2 min: notificación de Windows «Cuadrilla · el panel de agy se cayó…», agy en rojo en el tablero y una línea en `mesa.ps1 bitacora`. `Cuadrilla.bat panel agy` lo reabre en la misma ventana y el tablero vuelve a «libre».
3. **Suspender el PC y volver.** Suspende con la mesa abierta, espera unos minutos y vuelve. Esperado: **ninguna** notificación de caída al despertar; en la bitácora, «Vuelta tras un salto de N min… no aviso de caídas». Si algo sigue caído de verdad, avisa en la vuelta siguiente (30 s después).
4. **Aprobar un encargo desde la cola.** Pídele a Claude que delegue algo que escriba fuera de la mesa (por ejemplo, en un repositorio). Esperado: el encargo sale en «Esperan a <tu nombre>» del tablero con su tipo (`repo`). Apruébalo con `.\mesa.ps1 aprobar -Hilo <id> -N <n>` (o recházalo con `rechazar -Motivo`); al aprobarlo, el panel del agente lo ejecuta a la vista.
5. **Parar el supervisor.** `Cuadrilla.bat cerrar` dejando abiertos los paneles: a los 3 min cada panel avisa en rojo de que el supervisor no da señales y el tablero lo marca PARADO.
6. **Oficina.** Se abre sola en el navegador y se ve como siempre; abrir un hilo carga sus mensajes al momento.
