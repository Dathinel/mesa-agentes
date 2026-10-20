# Prueba de la recarga automática del supervisor, en una copia aislada de la mesa (no toca la mesa viva).
# Comprueba: un cambio en un script reinicia el supervisor con código nuevo; un script con errores no lo reinicia.
$ErrorActionPreference = 'Stop'
$origen = Split-Path -Parent $PSScriptRoot
$t = Join-Path $env:TEMP ("cuadrilla-prueba-recarga-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$fallos = 0
function Caso($nombre, [bool]$ok, $detalle = '') {
  if ($ok) { Write-Output "  ok    $nombre" } else { $script:fallos++; Write-Output "  FALLO $nombre $detalle" }
}
function Supervisores { ,@(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match [regex]::Escape("$t\herramientas\supervisor.ps1") }) }
function Bitacora { $f = Join-Path $t 'datos\bitacora\*.md'; (Get-Content -LiteralPath (Get-ChildItem $f | Select-Object -Last 1).FullName -Raw -Encoding UTF8) }

try {
  New-Item -ItemType Directory -Force -Path "$t\herramientas", "$t\panel", "$t\datos\bitacora", "$t\datos\agentes" | Out-Null
  Copy-Item "$origen\herramientas\*" "$t\herramientas" -Recurse -Force
  Copy-Item "$origen\panel\*" "$t\panel" -Recurse -Force
  Copy-Item "$origen\datos\mesa.json", "$origen\datos\personajes.json", "$origen\datos\excluidos.txt" "$t\datos" -ErrorAction SilentlyContinue
  $env:MESA_DATOS = "$t\datos"
  $env:MESA_RAIZ_PRUEBA = "$t\datos"
  $env:MESA_SIN_AVISOS = '1'

  Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$t\herramientas\supervisor.ps1`"", '-Intervalo', '3'
  Start-Sleep -Seconds 8
  $antes = Supervisores
  Caso 'arranca un supervisor en la copia' ($antes.Count -eq 1) "procesos=$($antes.Count)"

  # 1. Cambio válido: debe reiniciarse con el código nuevo.
  Add-Content -LiteralPath "$t\herramientas\tablero.ps1" -Value '# cambio de prueba'
  $reinicio = $false
  for ($i = 0; $i -lt 40 -and -not $reinicio; $i++) { Start-Sleep -Seconds 1; $ahora = Supervisores; $reinicio = $ahora.Count -eq 1 -and $ahora[0].ProcessId -ne $antes[0].ProcessId }
  Caso 'un cambio en un script reinicia el supervisor' $reinicio "antes=$($antes[0].ProcessId) ahora=$(@(Supervisores | ForEach-Object { $_.ProcessId }) -join ',')"
  Caso 'la bitácora lo anota' ((Bitacora) -match 'Cambió el código de la mesa')

  # 2. Script con errores de sintaxis: no se recarga; se anota y el supervisor sigue.
  $tras = Supervisores
  Set-Content -LiteralPath "$t\herramientas\zz-roto.ps1" -Value 'function {' -Encoding utf8
  Start-Sleep -Seconds 12
  $sigue = Supervisores
  Caso 'un script con errores no reinicia el supervisor' ($sigue.Count -eq 1 -and $sigue[0].ProcessId -eq $tras[0].ProcessId) "antes=$($tras[0].ProcessId) ahora=$(@($sigue | ForEach-Object { $_.ProcessId }) -join ',')"
  Caso 'la bitácora dice que hay errores de sintaxis' ((Bitacora) -match 'errores de sintaxis')
  Remove-Item -LiteralPath "$t\herramientas\zz-roto.ps1" -Force
}
finally {
  Supervisores | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Remove-Item Env:\MESA_DATOS, Env:\MESA_RAIZ_PRUEBA, Env:\MESA_SIN_AVISOS -ErrorAction SilentlyContinue
  if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output ''
Write-Output $(if ($fallos -eq 0) { 'probar-recarga: 0 fallos' } else { "probar-recarga: $fallos fallo(s)" })
exit $fallos
