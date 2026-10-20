# Prueba del corte a propósito (mesa.ps1 cortar), en una copia aislada de datos.
# Un proceso de prueba hace de CLI de un encargo. Cortar debe dejar un marcador y el supervisor debe decir «cortado»,
# no «fallido». Sin marcador, el mismo fallo sí sale como «fallido».
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$herr = Join-Path $base 'herramientas'
$t = Join-Path $env:TEMP ("cuadrilla-prueba-cortes-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$datos = Join-Path $t 'datos'
$fallos = 0
function Caso($nombre, [bool]$ok, $detalle = '') {
  if ($ok) { Write-Output "  ok    $nombre" } else { $script:fallos++; Write-Output "  FALLO $nombre $detalle" }
}
$proc = $null
try {
  New-Item -ItemType Directory -Force -Path "$datos\hilos\hilo-corte", "$datos\agentes", "$datos\cortes" | Out-Null
  Copy-Item "$base\datos\mesa.json", "$base\datos\personajes.json", "$base\datos\excluidos.txt" $datos -ErrorAction SilentlyContinue
  $env:MESA_DATOS = $datos
  $env:MESA_SIN_AVISOS = '1'

  # Hilo con líder claude y un encargo de agy en ejecución, con su proceso (CLI) de prueba.
  [IO.File]::WriteAllText("$datos\hilos\hilo-corte\hilo.json", (@{ id = 'hilo-corte'; titulo = 'prueba de cortes'; lider = 'claude'; participantes = @('claude', 'agy'); estado = 'abierto'; actualizado = (Get-Date).ToString('o') } | ConvertTo-Json))
  $proc = Start-Process ping -ArgumentList '-n', '300', '127.0.0.1' -WindowStyle Hidden -PassThru
  Start-Sleep -Milliseconds 500
  $inicio = $proc.StartTime.ToUniversalTime().ToString('o')
  $intento = 'intento-prueba'
  $llamada = [ordered]@{ inicio = (Get-Date).AddMinutes(-2).ToString('o'); log = $null; pid = $proc.Id; pid_inicio = $inicio; pid_nombre = 'PING'; intento = $intento; cli_pid = $proc.Id; cli_inicio = $inicio; cli_nombre = 'PING' }
  $mensaje = [ordered]@{ tipo = 'encargo'; n = 1; herramienta = 'agy'; para = 'agy'; autor = 'claude'; estado = 'ejecutando'; fecha = (Get-Date).ToString('o'); llamada = $llamada }
  [IO.File]::WriteAllText("$datos\hilos\hilo-corte\0001-agy.json", ($mensaje | ConvertTo-Json -Depth 5))
  [IO.File]::WriteAllText("$datos\agentes\en-curso-$($proc.Id).json", (@{ hilo = 'hilo-corte'; n = 1; intento = $intento; cli_pid = $proc.Id; cli_inicio = $inicio; cli_nombre = 'PING' } | ConvertTo-Json))

  # 1. Cortar: deja el marcador y mata la CLI.
  $salida = & "$herr\mesa.ps1" cortar -Hilo hilo-corte -N 1 -De claude 2>&1 | Out-String
  $marca = Join-Path $datos 'cortes\hilo-corte-1.json'
  Start-Sleep -Milliseconds 800
  Caso 'cortar mata la CLI de prueba' (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) $salida
  Caso 'cortar deja el marcador con quién lo cortó' ((Test-Path -LiteralPath $marca) -and ((Get-Content -LiteralPath $marca -Raw | ConvertFrom-Json).por -eq 'claude')) $salida
  Caso 'la salida dice que es un corte a propósito' ($salida -match 'a propósito') $salida

  # 2. ejecutar.ps1 registraría el fallo por el corte: se simula el resultado final.
  $mensaje.estado = 'fallo'; $mensaje.llamada.fin = (Get-Date).ToString('o'); $mensaje.llamada.salida = 1
  [IO.File]::WriteAllText("$datos\hilos\hilo-corte\0001-agy.json", ($mensaje | ConvertTo-Json -Depth 5))
  & "$herr\supervisor.ps1" -UnaVez -SinAvisos *> $null
  $agy = Get-Content -LiteralPath "$datos\agentes\agy.json" -Raw | ConvertFrom-Json
  Caso 'con marcador: alerta cortado, no fallido' ($agy.alerta.tipo -eq 'cortado' -and $agy.alerta.texto -match 'cortado por claude') "alerta=$($agy.alerta.tipo) texto=$($agy.alerta.texto)"

  # 3. Control: sin marcador, el mismo fallo es fallido.
  Remove-Item -LiteralPath $marca -Force
  & "$herr\supervisor.ps1" -UnaVez -SinAvisos *> $null
  $agy = Get-Content -LiteralPath "$datos\agentes\agy.json" -Raw | ConvertFrom-Json
  Caso 'sin marcador: el mismo fallo es fallido' ($agy.alerta.tipo -eq 'fallido') "alerta=$($agy.alerta.tipo)"
}
finally {
  if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item Env:\MESA_DATOS, Env:\MESA_SIN_AVISOS -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output ''
Write-Output $(if ($fallos -eq 0) { 'probar-cortes: 0 fallos' } else { "probar-cortes: $fallos fallo(s)" })
exit $fallos
