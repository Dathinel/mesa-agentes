# Reclamos

Un archivo `<tarea>.json` por tarea en curso: `{"tarea","agente","fecha","hilo","toca"}`. Se crea solo con `mesa.ps1 reclamar` (CreateNew, atómico: de dos agentes a la vez, solo uno lo consigue) y se suelta con `soltar` o al aceptarse la entrega. El reclamo especial `lider` dice quién coordina. Los `relevo-<hilo>.lock` evitan dos relevos del mismo hilo.

Si el agente de un reclamo no da señales de vida en `supervisor.reclamo_min` minutos (mesa.json), el supervisor avisa al líder; `mesa.ps1 limpiar` archiva los de más de 12 h en `datos\archivo\`.
