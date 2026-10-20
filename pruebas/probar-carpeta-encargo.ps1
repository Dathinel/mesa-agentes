# Prueba de ejecutar.ps1: un encargo con una carpeta que no existe queda pendiente, con el motivo, y no se lanza.
$ErrorActionPreference = 'Stop'
$raiz = Join-Path $env:TEMP "mesa-carpeta-$(Get-Random)"
$env:MESA_RAIZ_PRUEBA = $raiz
$env:MESA_SIMULAR = '1'
New-Item -ItemType Directory -Force (Join-Path $raiz 'reclamos'), (Join-Path $raiz 'hilos\prueba-carpeta') | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\datos\mesa.ejemplo.json') (Join-Path $raiz 'mesa.json')
$fallos = 0
function Comprobar($nombre, $ok) { if ($ok) { "OK    $nombre" } else { "FALLO $nombre"; $script:fallos++ } }
$dir = Join-Path $raiz 'hilos\prueba-carpeta'
[IO.File]::WriteAllText((Join-Path $dir 'hilo.json'), (@{ id = 'prueba-carpeta'; titulo = 'prueba'; lider = 'claude'; participantes = @('claude', 'codex'); estado = 'abierto'; actualizado = (Get-Date).ToString('o') } | ConvertTo-Json))
$m = @{ tipo = 'encargo'; n = 1; herramienta = 'codex'; para = 'codex'; autor = 'claude'; estado = 'aprobado'; fecha = (Get-Date).ToString('o'); texto = 'prueba'; modelo = 'gpt-6.1-sol'; dir = (Join-Path $raiz 'carpeta-que-no-existe'); cola = $false }
[IO.File]::WriteAllText((Join-Path $dir '0001-codex.json'), ($m | ConvertTo-Json -Depth 5))
& "$PSScriptRoot\..\herramientas\ejecutar.ps1" -Hilo prueba-carpeta -N 1 *> $null
$r = Get-Content -LiteralPath (Join-Path $dir '0001-codex.json') -Raw | ConvertFrom-Json
Comprobar 'el encargo queda pendiente' ($r.estado -eq 'pendiente')
Comprobar 'el motivo explica que no existe la carpeta' ($r.traspaso.falta -match 'No existe la carpeta del encargo')
Comprobar 'no se creó registro de llamada (no se lanzó nada)' (-not $r.llamada)
Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue
"Fallos: $fallos"
if ($fallos) { exit 1 }
