# Contrato de estado de los agentes

Quién lo escribe: el supervisor (`herramientas\supervisor.ps1`), en cada vuelta, en `datos\agentes\<agente>.json`.
Quién lo lee: la vista Resumen y la oficina (`panel\`), el tablero (`herramientas\tablero.ps1`) y el relevo. **Nadie más calcula el estado.** Los detalles de cada vista (tokens, modelo, línea de tiempo) salen del `estado-panel.json`, pero el campo `estado` sale siempre de aquí.

## Los seis estados

| `estado` | Significado | Cuándo |
|---|---|---|
| `trabajando` | Tiene un encargo en curso y el proceso vive | Encargo `ejecutando` con PID vivo |
| `libre` | Listo para recibir trabajo | Ninguna de las demás condiciones |
| `esperando-daniel` | Necesita a la persona para seguir | Encargo `escalado` (3 intentos fallidos) o sesión caducada (`necesita-login`) |
| `sin-cuota` | Sin cuota hasta una hora | Cuota agotada; `hasta` dice cuándo vuelve |
| `caido` | Debería estar activo y no responde | Panel sin latido, o en Claude, no hay proceso `claude` |
| `apagado` | Cerrado a propósito | El panel salió limpio (marca `trabajador-<agente>.cerrado`) |

Prioridad si varias condiciones se cumplen: `caido` > `sin-cuota` > `esperando-daniel` > `trabajando` > `libre`. La causa más reciente del agente manda: una cuota agotada gana a un encargo escalado anterior. `apagado` solo aplica si no hay proceso ni latido y existe la marca de cierre.

## Campos del objeto

```json
{
  "agente": "codex",
  "estado": "trabajando",
  "motivo": "encargo #12 desde 23:10",
  "desde": "2026-10-19T23:10:00-05:00",
  "hasta": null,
  "hilo": "20261019-ronda-2-pendientes-y-ver",
  "n": 12,
  "latido": "2026-10-19T23:45:11-05:00",
  "alerta": null,
  "actualizado": "2026-10-19T23:45:14-05:00"
}
```

- `agente`: `claude`, `codex` o `agy`.
- `estado`: uno de los seis de arriba. Ningún otro valor.
- `motivo`: una frase en español para la persona, sin códigos internos. Es lo que la vista muestra debajo del estado.
- `desde`: cuándo empezó el estado actual. Sirve para «desde hace 12 min».
- `hasta`: solo en `sin-cuota`, hora de vuelta. Si no, `null`.
- `hilo`, `n`: encargo en curso, si lo hay. Si no, `null`.
- `latido`: última señal de vida (ISO), o `null`.
- `alerta`: `null` o `{ "tipo": "huerfano" | "colgado" | "fallido", "texto": "..." }`. Una tarea huérfana o fallida no cambia el `estado` a otro valor: el agente sigue `libre` con la alerta visible en su tarjeta.
- `actualizado`: cuándo calculó el supervisor este objeto.

## Traducción desde los estados internos

| Estado interno del supervisor | `estado` | `alerta` |
|---|---|---|
| `trabajando` | `trabajando` | `null` |
| `colgado` | `trabajando` | `colgado` |
| `huerfano` | `libre` | `huerfano` |
| `fallido` (encargo con error, aún sin escalar) | `libre` | `fallido` |
| `escalado` | `esperando-daniel` | `null` |
| `necesita-login` | `esperando-daniel` | `null` |
| `sin-cuota` | `sin-cuota` | `null` |
| `caido` | `caido` | `null` |
| `libre` con marca de cierre | `apagado` | `null` |
| `libre` | `libre` | `null` |

## Nivel de datos

- `datos\agentes\<agente>.json` se escribe de forma atómica (archivo temporal y renombrado).
- Si el supervisor no ha escrito en más de 3 intervalos, la vista marca los datos como viejos, pero **no** cambia el `estado`.
- El panel web no escribe este archivo. Las rutas del servidor siguen siendo de solo lectura.

## «Te necesito» (la misma regla en la vista Resumen y en la oficina)

Cuenta lo que espera a Daniel: los agentes en `caido` o `esperando-daniel`, las alertas de nivel `alto` sin revisar, y los pendientes cuyo texto pide aprobación o dice «ESCALADO».
