# Pruebas de consola: no leen sesiones ni escriben el historial real.
$ErrorActionPreference = 'Stop'
$raizPrueba = Join-Path $env:TEMP ('mesa-vigia-ambito-' + [guid]::NewGuid().ToString('N'))
$anteriorRaiz = $env:MESA_RAIZ_PRUEBA
try {
  $env:MESA_RAIZ_PRUEBA = $raizPrueba
  $abierto = Join-Path $raizPrueba 'hilos\abierto'
  $cerrado = Join-Path $raizPrueba 'hilos\cerrado'
  New-Item -ItemType Directory -Force -Path $abierto,$cerrado | Out-Null
  . "$PSScriptRoot\..\herramientas\comun.ps1"
  Mesa-EscribirJson (Join-Path $abierto 'hilo.json') @{ estado='abierto' }
  Mesa-EscribirJson (Join-Path $cerrado 'hilo.json') @{ estado='cerrado' }
  Mesa-EscribirJson (Join-Path $abierto '0001-codex.json') @{ tipo='encargo'; dir='C:\trabajo asignado\modelo\..\modelo'; estado='hecho' }
  Mesa-EscribirJson (Join-Path $abierto '0002-codex.json') @{ tipo='nota'; dir='C:\solo-nota' }
  Mesa-EscribirJson (Join-Path $abierto '0003-codex.json') @{ tipo='encargo'; dir='relativa' }
  Mesa-EscribirJson (Join-Path $cerrado '0001-codex.json') @{ tipo='encargo'; dir='C:\cerrado' }
  [IO.File]::WriteAllText((Join-Path $abierto '0004-roto.json'), '{')
  . "$PSScriptRoot\..\herramientas\vigia.ps1" -Biblioteca
  $casos = @(
    @{ nombre='encargo abierto'; ruta='C:\trabajo asignado\modelo\pieza.stl'; nivel='' },
    @{ nombre='raiz exacta'; ruta='C:\trabajo asignado\modelo'; nivel='' },
    @{ nombre='mayusculas y barras'; ruta='c:/TRABAJO ASIGNADO/modelo/pieza.stl'; nivel='' },
    @{ nombre='ruta relativa al encargo'; ruta='pieza.stl'; cwd='C:\trabajo asignado\modelo'; nivel='' },
    @{ nombre='hilo cerrado'; ruta='C:\cerrado\pieza.stl'; nivel='alto' },
    @{ nombre='prefijo hermano'; ruta='C:\trabajo asignado\modelo-ajeno\pieza.stl'; nivel='alto' },
    @{ nombre='escape con puntos'; ruta='C:\trabajo asignado\modelo\..\ajeno\pieza.stl'; nivel='alto' },
    @{ nombre='nota no autoriza'; ruta='C:\solo-nota\pieza.stl'; nivel='alto' },
    @{ nombre='ambito original'; ruta='D:\Programas de uso libre\proyecto\pieza.stl'; nivel='' },
    @{ nombre='temporal original'; ruta=(Join-Path $env:TEMP 'pieza.stl'); nivel='' },
    @{ nombre='cli original'; ruta=(Join-Path $env:USERPROFILE '.codex\resultado.txt'); nivel='' },
    @{ nombre='sensible conserva alerta'; ruta='C:\trabajo asignado\modelo\.env'; nivel='alto' }
  )
  $total = 0
  foreach ($caso in $casos) {
    $r = Vigia-Evaluar 'archivo' $caso.ruta $caso.cwd 'escritura' ''
    if ([string]$r.nivel -ne $caso.nivel) { throw "$($caso.nombre): esperado '$($caso.nivel)', recibido '$($r.nivel)' ($($r.motivo))" }
    if ($caso.nivel -eq 'alto' -and $caso.nombre -ne 'sensible conserva alerta' -and $r.motivo -ne 'Escritura fuera del ámbito de trabajo') { throw "Motivo inesperado: $($r.motivo)" }
    $total++; Write-Output "OK $total - $($caso.nombre)"
  }
  $r = Vigia-Evaluar 'comando' 'Set-Content -LiteralPath "C:\trabajo asignado\modelo\pieza.stl" -Value prueba' '' 'ejecucion' ''
  if ($r) { throw "Escritura shell autorizada: $($r.motivo)" }
  $total++; Write-Output "OK $total - escritura shell en encargo"
  Mesa-EscribirJson (Join-Path $abierto 'hilo.json') @{ estado='cerrado' }
  $r = Vigia-Evaluar 'archivo' 'C:\trabajo asignado\modelo\pieza.stl' '' 'escritura' ''
  if ($r) { throw 'Se recalcularon los directorios por evento' }
  $total++; Write-Output "OK $total - foto estable durante ejecucion"
  . "$PSScriptRoot\..\herramientas\vigia.ps1" -Biblioteca
  $r = Vigia-Evaluar 'archivo' 'C:\trabajo asignado\modelo\pieza.stl' '' 'escritura' ''
  if ($r.nivel -ne 'alto') { throw 'Nueva ejecucion no detecto hilo cerrado' }
  $total++; Write-Output "OK $total - nueva ejecucion respeta cierre"
  if (Test-Path -LiteralPath (Join-Path $raizPrueba 'alertas.jsonl')) { throw 'Biblioteca escribio historial' }
  Write-Output "RESULTADO: $total/$total; Biblioteca sin historial; raiz aislada: $raizPrueba"
} finally {
  $env:MESA_RAIZ_PRUEBA = $anteriorRaiz
}
