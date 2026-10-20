# Pruebas de caos de la Mesa en una copia aislada (MESA_RAIZ_PRUEBA en %TEMP%): agentes simulados, sin gastar cuota
# ni tocar la mesa real. Cada caso imprime lo esperado y lo obtenido. Sale con el número de fallos.
# Uso: pruebas\caos.ps1 [-Conservar]
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
$h = Join-Path (Split-Path -Parent $PSScriptRoot) 'herramientas'
$raiz = Join-Path $env:TEMP ("mesa-caos-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'hilos'), (Join-Path $raiz 'reclamos') | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'datos\mesa.json') -Destination $raiz
$env:MESA_RAIZ_PRUEBA = $raiz; $env:MESA_SIN_AVISOS = '1'; $env:MESA_SIMULAR = '1'
. "$h\comun.ps1"
$script:fallos = 0
function Caso($nombre, $esperado, $obtenido, [bool]$ok) {
  if (-not $ok) { $script:fallos++ }
  Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
function Msg($hilo, $n) { Mesa-LeerJson (Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Hilos $hilo) -Filter ('{0:D4}-*.json' -f $n)).FullName }
function Encargo($hilo, $para) {
  $s = & "$h\mesa.ps1" enviar -Hilo $hilo -De claude -Para $para -Texto "Prueba de caos para $para" | Select-Object -Last 1
  [int]($s -replace '^(\d+)-.*', '$1')
}
function Poner($hilo, $n, [scriptblock]$cambio) { $f = (Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Hilos $hilo) -Filter ('{0:D4}-*.json' -f $n)).FullName; $m = Mesa-LeerJson $f; & $cambio $m; Mesa-EscribirJson $f $m }
function Supervisar { & "$h\supervisor.ps1" -UnaVez -SinAvisos | Out-Null }
function Agente($a) { Mesa-LeerJson (Join-Path $raiz "agentes\$a.json") }

try {
  $hilo = & "$h\mesa.ps1" abrir -Titulo 'Caos' -Lider claude -Participantes 'claude,codex,agy'

  # 1. Un agente muere a mitad de un encargo: el supervisor lo marca huérfano y avisa al líder; reintentar lo relanza con sus puntos de control.
  $n1 = Encargo $hilo codex
  & "$h\mesa.ps1" reclamar -Tarea caos-a -De codex -Hilo $hilo -Texto 'x' | Out-Null
  & "$h\mesa.ps1" avance -Hilo $hilo -Tarea caos-a -De codex -Fase hito -Texto 'paso 1 hecho' | Out-Null
  $muerto = Start-Process cmd.exe -ArgumentList '/c', 'exit' -PassThru -WindowStyle Hidden; $muerto.WaitForExit()
  Poner $hilo $n1 { param($m) $m.estado = 'ejecutando'; $m.llamada = [pscustomobject]@{ inicio = (Mesa-IsoNow); fin = $null; salida = $null; log = $null; pid = $muerto.Id } }
  Supervisar
  $nota = @(Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Hilos $hilo) -Filter '*-supervisor.json').Count
  Caso 'Agente muerto a mitad' 'encargo huerfano y nota del supervisor al líder' "estado=$((Msg $hilo $n1).estado), notas del supervisor=$nota" ((Msg $hilo $n1).estado -eq 'huerfano' -and $nota -ge 1)

  $r = & "$h\mesa.ps1" reintentar -Hilo $hilo -N $n1 -De claude
  $fin = (Get-Date).AddSeconds(40)
  while ((Msg $hilo $n1).estado -ne 'hecho' -and (Get-Date) -lt $fin) { Start-Sleep -Milliseconds 500 }
  $prompt = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Global:Mesa_Hilos "$hilo\logs\$('{0:D4}' -f $n1)-codex-prompt.txt") -ErrorAction SilentlyContinue
  Caso 'Reintento tras la muerte' 'se relanza, termina y el prompt trae REINTENTO y el punto de control' "$r; estado=$((Msg $hilo $n1).estado); reintento en prompt=$($prompt -match 'REINTENTO 1'); punto de control=$($prompt -match 'paso 1 hecho')" ((Msg $hilo $n1).estado -eq 'hecho' -and $prompt -match 'REINTENTO 1' -and $prompt -match 'paso 1 hecho')

  # 2. Tras N fallos se escala a Daniel en vez de seguir reintentando.
  Poner $hilo $n1 { param($m) $m.estado = 'fallo'; $m.intentos = 2 }
  $r = & "$h\mesa.ps1" reintentar -Hilo $hilo -N $n1 -De claude
  Caso 'Escalado tras 3 intentos' 'estado escalado y nota a daniel' "$r; estado=$((Msg $hilo $n1).estado)" ((Msg $hilo $n1).estado -eq 'escalado' -and $r -match 'ESCALADO')

  # 3. Archivo de estado dañado: los comandos y el supervisor lo saltan con aviso, sin caerse.
  [IO.File]::WriteAllText((Join-Path $Global:Mesa_Hilos "$hilo\0099-roto.json"), '{"n": 99, "texto": "cortado a medi')
  $err = @()
  foreach ($c in @({ & "$h\mesa.ps1" pendientes -Para claude 3>$null }, { & "$h\mesa.ps1" hilos }, { & "$h\mesa.ps1" leer -Hilo $hilo 3>$null }, { & "$h\supervisor.ps1" -UnaVez -SinAvisos 3>$null }, { & "$h\esperar-novedades.ps1" -Para claude -MaxMin 0 -Intervalo 0 3>$null })) {
    try { & $c | Out-Null } catch { $err += $_.Exception.Message }
  }
  Caso 'JSON dañado en un hilo' 'pendientes, hilos, leer, supervisor y esperar-novedades siguen' $(if ($err.Count) { $err -join ' | ' } else { 'ninguno falló' }) ($err.Count -eq 0)

  # 4. El panel de un agente no se cae con un JSON dañado y sigue ejecutando su cola (agente simulado).
  $n4 = Encargo $hilo agy
  Poner $hilo $n4 { param($m) $m | Add-Member cola $true -Force }
  $panel = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$h\trabajador.ps1`"", '-Agente', 'agy', '-Intervalo', '1' -PassThru -WindowStyle Hidden
  $fin = (Get-Date).AddSeconds(40)
  while ((Msg $hilo $n4).estado -ne 'hecho' -and (Get-Date) -lt $fin) { Start-Sleep -Milliseconds 500 }
  Start-Sleep -Seconds 3
  $vivo = -not $panel.HasExited
  Caso 'Panel con JSON dañado al lado' 'ejecuta el encargo simulado y el panel sigue vivo' "estado=$((Msg $hilo $n4).estado), panel vivo=$vivo" ((Msg $hilo $n4).estado -eq 'hecho' -and $vivo)

  # 5. Cerrar la pestaña del panel: el latido envejece y el supervisor lo da por caído (sin relanzar: está apagado).
  Stop-Process -Id $panel.Id -Force; Start-Sleep -Milliseconds 300
  (Get-Item -LiteralPath (Join-Path $raiz 'trabajador-agy.latido')).LastWriteTime = (Get-Date).AddMinutes(-5)
  Supervisar
  $bit = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $raiz ("bitacora\{0}.md" -f (Get-Date -Format 'yyyy-MM-dd')))
  Caso 'Pestaña cerrada' 'agy caido y en la bitácora en tres partes' "estado=$((Agente agy).estado); bitácora=$($bit -match 'panel de agy se cayó.*Qué necesito')" ((Agente agy).estado -eq 'caido' -and $bit -match 'panel de agy se cayó.*Qué necesito')

  # 6. Cuota agotada: se reconoce por el mensaje y el agente queda sin cuota hasta la hora que dice, no muerto.
  $c = Mesa-CausaFallo '{"status":"RESOURCE_EXHAUSTED","error_code":429,"message":"... Resets in 134h28m38s."}'
  $n6 = Encargo $hilo codex
  Poner $hilo $n6 { param($m) $m.estado = 'fallo'; $m.llamada = [pscustomobject]@{ inicio = (Mesa-IsoNow); fin = (Mesa-IsoNow); salida = 1; log = $null; causa = $c.causa; hasta = $c.hasta } }
  [IO.File]::WriteAllText((Join-Path $raiz 'trabajador-codex.latido'), (Mesa-IsoNow))
  Supervisar
  $horas = [int]([datetime]::Parse($c.hasta) - (Get-Date)).TotalHours
  Caso 'Cuota agotada' 'codex sin-cuota durante ~134 h' "causa=$($c.causa), horas=$horas, estado=$((Agente codex).estado)" ($c.causa -eq 'sin-cuota' -and $horas -ge 133 -and (Agente codex).estado -eq 'sin-cuota')
  $l = Mesa-CausaFallo 'Error: 401 Unauthorized. Please run /login'
  Caso 'Sesión caducada' 'necesita-login' "$($l.causa)" ($l.causa -eq 'necesita-login')

  # 7. Encargo colgado: proceso vivo pero sin salida nueva más allá del límite.
  $n7 = Encargo $hilo claude
  $log7 = Join-Path $raiz 'colgado.log'; [IO.File]::WriteAllText($log7, 'sin novedades'); (Get-Item $log7).LastWriteTime = (Get-Date).AddMinutes(-45)
  Poner $hilo $n7 { param($m) $m.estado = 'ejecutando'; $m.llamada = [pscustomobject]@{ inicio = (Get-Date).AddMinutes(-50).ToString('yyyy-MM-ddTHH:mm:sszzz'); fin = $null; salida = $null; log = $log7; pid = $PID } }
  Supervisar
  Caso 'Encargo colgado' 'claude colgado, encargo sigue en curso' "estado=$((Agente claude).estado), encargo=$((Msg $hilo $n7).estado)" ((Agente claude).estado -eq 'colgado' -and (Msg $hilo $n7).estado -eq 'ejecutando')

  # 8. Reclamo cuyo agente no da señales: arriendo caducado, se avisa al líder sin soltarlo solo.
  $rec = [ordered]@{ tarea = 'caos-b'; agente = 'agy'; fecha = (Get-Date).AddHours(-3).ToString('yyyy-MM-ddTHH:mm:sszzz'); hilo = $hilo; toca = 'x' }
  Mesa-EscribirJson (Join-Path $raiz 'reclamos\caos-b.json') $rec
  Supervisar
  $aviso = @(Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Hilos $hilo) -Filter '*-supervisor.json' | ForEach-Object { Mesa-LeerJson $_.FullName } | Where-Object { $_.texto -match "reclamo 'caos-b'" }).Count
  Caso 'Arriendo de reclamo caducado' 'nota al líder y el reclamo sigue' "notas=$aviso, reclamo sigue=$(Test-Path (Join-Path $raiz 'reclamos\caos-b.json'))" ($aviso -eq 1 -and (Test-Path (Join-Path $raiz 'reclamos\caos-b.json')))

  # 9. Reinicio seguro: limpiar archiva (no borra) los reclamos caducados.
  $r = & "$h\mesa.ps1" limpiar -Horas 1
  $archivado = @(Get-ChildItem -Path (Join-Path $raiz 'archivo\limpieza-*\*caos-b.json')).Count
  Caso 'Reinicio seguro' 'el reclamo caducado pasa a archivo\limpieza-*' "archivados=$archivado" ($archivado -eq 1 -and -not (Test-Path (Join-Path $raiz 'reclamos\caos-b.json')))

  # 10. El líder deja de responder: relevo del liderazgo por otro panel (prueba existente).
  $relevo = & "$PSScriptRoot\probar-relevo.ps1" 2>&1 | Select-Object -Last 1
  Caso 'Arriendo del líder caduca' 'otro agente toma el liderazgo (probar-relevo.ps1)' "$relevo" ($relevo -match 'fallos=0')
} catch {
  $script:fallos++; Write-Host "ERROR de la prueba: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
} finally {
  Remove-Item Env:MESA_RAIZ_PRUEBA, Env:MESA_SIN_AVISOS, Env:MESA_SIMULAR -ErrorAction SilentlyContinue
  if (-not $Conservar) { Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue } else { Write-Host "Copia conservada en $raiz" }
}
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
