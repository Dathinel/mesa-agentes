# Cierre de un panel de codex con la X (cierre de ventana, no Ctrl+C), en datos aislados.
# Debe salir limpio: marca de cierre, proceso terminado y el supervisor lo deja en «apagado», sin alerta de caída.
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$t = Join-Path $env:TEMP ("cuadrilla-prueba-cierre-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$datos = Join-Path $t 'datos'
$fallos = 0
function Caso($nombre, [bool]$ok, $detalle = '') {
  if ($ok) { Write-Output "  ok    $nombre" } else { $script:fallos++; Write-Output "  FALLO $nombre $detalle" }
}
$panel = $null
try {
  New-Item -ItemType Directory -Force -Path "$datos\hilos", "$datos\agentes" | Out-Null
  Copy-Item "$base\datos\mesa.json", "$base\datos\personajes.json", "$base\datos\excluidos.txt" $datos -ErrorAction SilentlyContinue
  $env:MESA_DATOS = $datos
  $env:MESA_RAIZ_PRUEBA = $datos
  $env:MESA_SIN_AVISOS = '1'

  $panel = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$base\herramientas\trabajador.ps1`"", '-Agente', 'codex'
  Start-Sleep -Seconds 10
  Caso 'el panel de prueba da latido' (Test-Path -LiteralPath "$datos\trabajador-codex.latido")

  # La X: cierre de ventana. Con taskkill sin /F el sistema pide el cierre a la consola, igual que la X.
  & taskkill.exe /PID $panel.Id 2>&1 | Out-Null
  $t0 = Get-Date
  while (-not $panel.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep -Milliseconds 300 }
  Caso 'la X termina el panel' $panel.HasExited
  Caso 'la X deja la marca de cierre' (Test-Path -LiteralPath "$datos\trabajador-codex.cerrado")

  & "$base\herramientas\supervisor.ps1" -UnaVez -SinAvisos *> $null
  $c = Get-Content -LiteralPath "$datos\agentes\codex.json" -Raw | ConvertFrom-Json
  Caso 'el supervisor lo deja en apagado' ($c.estado -eq 'apagado') "estado=$($c.estado) motivo=$($c.motivo)"
  Caso 'sin alerta de caída' ($null -eq $c.alerta) "alerta=$($c.alerta.tipo)"
}
finally {
  if ($panel -and -not $panel.HasExited) { Stop-Process -Id $panel.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item Env:\MESA_DATOS, Env:\MESA_RAIZ_PRUEBA, Env:\MESA_SIN_AVISOS -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output ''
Write-Output $(if ($fallos -eq 0) { 'probar-cierre-panel: 0 fallos' } else { "probar-cierre-panel: $fallos fallo(s)" })
exit $fallos
