# Prueba del relevo de líder de trabajador.ps1 en una Mesa temporal (no toca datos\ ni lanza agentes).
$ErrorActionPreference = 'Stop'
$env:MESA_RAIZ_PRUEBA = Join-Path $env:TEMP "mesa-relevo-$(Get-Random)"
New-Item -ItemType Directory -Force (Join-Path $env:MESA_RAIZ_PRUEBA 'reclamos') | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\datos\mesa.ejemplo.json') (Join-Path $env:MESA_RAIZ_PRUEBA 'mesa.json')
. "$PSScriptRoot\..\herramientas\comun.ps1"
$RaizHerramientas = Join-Path (Split-Path -Parent $PSScriptRoot) 'herramientas'
$ast = [Management.Automation.Language.Parser]::ParseFile("$PSScriptRoot\..\herramientas\trabajador.ps1", [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ $args[0] -is [Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Vigilar-Lideres' }, $true)) {
  # Creadas desde texto pierden $PSScriptRoot: se fija la carpeta real.
  . ([scriptblock]::Create($f.Extent.Text.Replace('$PSScriptRoot', '$RaizHerramientas')))
}
$fallos = 0
function Comprobar($nombre, $ok) { if ($ok) { "OK    $nombre" } else { "FALLO $nombre"; $script:fallos++ } }
$mesa = "$PSScriptRoot\..\herramientas\mesa.ps1"
function Hilo-ConEntrega([int]$minutos) {
  $o = & $mesa abrir -Titulo prueba -Lider claude -Participantes 'claude,codex,agy' | Out-String
  $h = [regex]::Match($o, '\d{8}-[a-z0-9-]+').Value
  & $mesa enviar -Hilo $h -De agy -Para claude -Texto 'entrega de prueba' | Out-Null
  $f = Get-ChildItem (Join-Path $Global:Mesa_Hilos $h) -Filter '*-agy.json' | Select-Object -First 1
  $m = Mesa-LeerJson $f.FullName
  $m.tipo = 'entrega'; $m.fecha = (Get-Date).AddMinutes(-$minutos).ToString('yyyy-MM-ddTHH:mm:sszzz')
  Mesa-EscribirJson $f.FullName $m
  $h
}
try {
  $Agente = 'codex'; $RelevoMin = 15
  [IO.File]::WriteAllText((Join-Path $Global:Mesa_Raiz 'trabajador-codex.latido'), (Mesa-IsoNow))

  $h = Hilo-ConEntrega 20
  Vigilar-Lideres | Out-Null
  $hj = Mesa-LeerJson (Join-Path $Global:Mesa_Hilos "$h\hilo.json")
  Comprobar 'líder caído 20 min con entrega esperando → codex toma el liderazgo' ($hj.lider -eq 'codex')
  $enc = @(Get-ChildItem (Join-Path $Global:Mesa_Hilos $h) -Filter '*-*.json' | ForEach-Object { Mesa-LeerJson $_.FullName } | Where-Object { $_.tipo -eq 'encargo' -and $_.cola })
  Comprobar 'deja el encargo de relevo en la cola de su panel, sin ejecutarlo' ($enc.Count -eq 1 -and $enc[0].estado -eq 'aprobado')

  $Agente = 'agy'
  Vigilar-Lideres | Out-Null
  $hj = Mesa-LeerJson (Join-Path $Global:Mesa_Hilos "$h\hilo.json")
  Comprobar 'un segundo panel no hace otro relevo' ($hj.lider -eq 'codex')

  $Agente = 'codex'
  $h2 = Hilo-ConEntrega 20
  Mesa-AnexarLinea (Join-Path $Global:Mesa_Raiz 'actividad.jsonl') ('{"agente":"claude","hora":"' + (Mesa-IsoNow) + '","tipo":"archivo"}')
  Vigilar-Lideres | Out-Null
  Comprobar 'líder con actividad reciente → no se le releva' ((Mesa-LeerJson (Join-Path $Global:Mesa_Hilos "$h2\hilo.json")).lider -eq 'claude')

  Remove-Item (Join-Path $Global:Mesa_Raiz 'actividad.jsonl')
  $h3 = Hilo-ConEntrega 2000
  Vigilar-Lideres | Out-Null
  Comprobar 'entrega de hace más de un día → no hay relevo' ((Mesa-LeerJson (Join-Path $Global:Mesa_Hilos "$h3\hilo.json")).lider -eq 'claude')
} finally { Remove-Item -Recurse -Force $env:MESA_RAIZ_PRUEBA -ErrorAction SilentlyContinue; Remove-Item Env:\MESA_RAIZ_PRUEBA }
"fallos=$fallos"
if ($fallos) { exit 1 }
