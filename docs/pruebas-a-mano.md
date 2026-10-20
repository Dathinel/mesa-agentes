# Pruebas a mano (solo Daniel puede juzgarlas)

Lo automático pasa (`Probar.bat`). Esto necesita tus ojos y tu ventana:

1. **Abrir.** Cierra las ventanas de la mesa y ejecuta `Mesa.bat`. Esperado: una sola ventana de Windows Terminal con Claude a la izquierda y Codex, agy y el tablero a la derecha; Claude retoma tu última conversación. Con `Mesa.bat nuevo`, conversación nueva.
2. **Tablero.** Que se lea bien de un vistazo a tu tamaño de ventana: una línea por agente, sin parpadeo molesto cada 5 s.
3. **Panel caído.** Cierra el panel de agy con la X. En menos de 2 min te llega una notificación de Windows «Mesa · el panel de agy se cayó…». `Mesa.bat panel agy` lo reabre en la misma ventana.
4. **Título del panel.** Mientras codex trabaja, su panel se titula «codex · trabajando #N»; al acabar, «codex · esperando».
5. **Cerrar.** `Mesa.bat cerrar` para el supervisor y la oficina; al volver a abrir, los hilos siguen donde estaban.
6. **Oficina.** La oficina en el navegador sigue igual de fluida tras aligerar `estado-panel.json`.
