# Prueba del contrato de estado (docs\estado-contrato.md) con una Mesa temporal: el supervisor corre una vuelta
# y se comprueba que cada agente sale con uno de los seis estados y la alerta o el motivo que le toca.
$ErrorActionPreference = 'Stop'
$raiz = Join-Path $env:TEMP "mesa-estado-$(Get-Random)"
$env:MESA_RAIZ_PRUEBA = $raiz
$env:MESA_SIN_AVISOS = '1'
New-Item -ItemType Directory -Force (Join-Path $raiz 'reclamos'), (Join-Path $raiz 'hilos') | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\datos\mesa.ejemplo.json') (Join-Path $raiz 'mesa.json')
$fallos = 0
function Comprobar($nombre, $ok) { if ($ok) { "OK    $nombre" } else { "FALLO $nombre"; $script:fallos++ } }

# Encargo sintético en un hilo: el supervisor solo mira el tipo, el estado, el agente y la llamada.
function Encargo($hilo, $n, $agente, $estado, $fin) {
  $dir = Join-Path $raiz "hilos\$hilo"
  New-Item -ItemType Directory -Force $dir | Out-Null
  if (-not (Test-Path (Join-Path $dir 'hilo.json'))) { [IO.File]::WriteAllText((Join-Path $dir 'hilo.json'), (@{ id = $hilo; titulo = 'prueba'; lider = 'claude'; participantes = @('claude', $agente); estado = 'abierto'; actualizado = (Get-Date).ToString('o') } | ConvertTo-Json)) }
  $m = @{ tipo = 'encargo'; n = $n; herramienta = $agente; para = $agente; autor = 'claude'; estado = $estado; fecha = (Get-Date).ToString('o'); llamada = @{ inicio = (Get-Date).AddMinutes(-5).ToString('o'); fin = $fin; log = $null } }
  [IO.File]::WriteAllText((Join-Path $dir ('{0:D4}-{1}.json' -f $n, $agente)), ($m | ConvertTo-Json -Depth 5))
}
function Estado($a) { Get-Content -LiteralPath (Join-Path $raiz "agentes\$a.json") -Raw | ConvertFrom-Json }

Encargo 'prueba-escalada' 1 'codex' 'escalado' $null
Encargo 'prueba-fallida' 2 'agy' 'fallo' ((Get-Date).AddMinutes(-3).ToString('o'))
New-Item -ItemType Directory -Force (Join-Path $raiz 'agentes') | Out-Null
[IO.File]::WriteAllText((Join-Path $raiz 'trabajador-claude.cerrado'), 'x')

$supervisor = Join-Path $PSScriptRoot '..\herramientas\supervisor.ps1'
& $supervisor -UnaVez -SinAvisos *> $null

$seis = @('trabajando', 'libre', 'esperando-daniel', 'sin-cuota', 'caido', 'apagado')
foreach ($a in @('claude', 'codex', 'agy')) {
  $e = Estado $a
  Comprobar "$a tiene uno de los seis estados ($($e.estado))" ($e.estado -in $seis)
  Comprobar "$a trae motivo, desde y actualizado" ([bool]$e.motivo -and [bool]$e.desde -and [bool]$e.actualizado)
}
$codex = Estado 'codex'
$claude = Estado 'claude'
Comprobar 'claude con marca de cierre y sin encargo es apagado' ($claude.estado -eq 'apagado')
$agy = Estado 'agy'
Comprobar 'agy con encargo fallido es libre con alerta fallido' ($agy.estado -eq 'libre' -and $agy.alerta.tipo -eq 'fallido')
Comprobar 'el encargo escalado lleva a esperando-daniel con su número' ($codex.motivo -match '#1 escalado')

Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue
"Fallos: $fallos"
if ($fallos) { exit 1 }
