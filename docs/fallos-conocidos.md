# Fallos conocidos

Cada problema real que aparece se anota aquí con su síntoma, su causa y qué hacer. Lo más reciente, arriba.

| Fecha | Síntoma | Causa | Qué hacer |
|---|---|---|---|
| 19-oct | `Cuadrilla.bat` lanza decenas de «no se reconoce como un comando» | El `.bat` se guardó con finales LF; cmd solo entiende CRLF. | `.gitattributes` lo fija en CRLF. Si se edita fuera de git: guardar con CRLF. |
| 19-oct | Un `echo` o `start` de cmd corta la orden en `\|\|` y ejecuta el resto | `\|\|` y `&` son operadores de cmd aunque vayan dentro de una variable expandida. | El arranque de Claude va en `herramientas\abrir-claude.cmd`, sin operadores en la orden de `wt`. |
| 19-oct | El panel de codex o agy se cierra solo | Una excepción (JSON dañado, candado ocupado más de 10 s, archivo bloqueado por el antivirus) salía del bucle de `trabajador.ps1`. | Arreglado: cada vuelta va en `try/catch` y el error queda en `datos\errores-paneles.log`. Si se cierra igualmente: `Cuadrilla.bat panel <agente>`. |
| 18-oct | Un encargo se queda «ejecutando» para siempre | El CLI murió (pestaña cerrada, apagón) o se quedó esperando red (`Reconnecting... waiting for network`). | El supervisor lo marca `huerfano` o el agente `colgado` y avisa. Colgado: `mesa.ps1 cortar -Hilo <id> -N <n> -De <líder>`. Huérfano o cortado: `mesa.ps1 reintentar ...`. |
| 18-oct | agy falla con `RESOURCE_EXHAUSTED` / 429 | Cuota de su grupo de modelos agotada («Resets in 134h…»). | El supervisor lo marca `sin-cuota` hasta esa hora. Reasignar a otro agente o cambiar a un modelo de otro grupo (`-Modelo`). |
| 18-oct | agy avisa `--mode auto is not available for this account` | La cuenta no tiene el modo automático. | `ejecutar.ps1` usa `--mode accept-edits`. |
| 18-oct | Un reclamo sigue después de entregar | El reclamo solo se suelta al **aceptar** la entrega; si nadie la revisa, sigue. | Revisar la entrega (`mesa.ps1 revisar`) o soltarlo (`soltar`). El supervisor avisa a los 60 min sin actividad. |
| 18-oct | `probar-oficina.ps1` fallaba con `cd ..` | Tras los ajustes de falsos positivos, el vigía ya no marca `cd ..`. | Prueba actualizada. |
| 17-oct | Un encargo con comillas llega partido al agente | PowerShell 5.1 no escapa las comillas al pasar argumentos a un `.exe`. | `ejecutar.ps1` las escapa con la regla de Windows. Límite: el prompt de claude y agy va por argumento (~32 000 caracteres); un encargo más largo, en archivo (`-Encargo`). |
