# Capturas de la portada (Resumen) y de la oficina, a 1366x768 y 1920x1080, con Edge sin interfaz.
# Uso: capturar-vistas.ps1 -Prueba 2 -Momento antes|despues  →  docs\pruebas-manana\p2-antes-resumen-1366.png, etc.
param(
  [Parameter(Mandatory = $true)][string]$Prueba,
  [Parameter(Mandatory = $true)][ValidateSet('antes', 'durante', 'despues')][string]$Momento,
  [int]$EsperaMs = 6000
)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$puerto = (Get-Content -LiteralPath (Join-Path $base 'datos\puerto.txt') -Raw).Trim()
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edge) { throw 'No encuentro msedge.exe' }
$carpeta = Join-Path $base 'docs\pruebas-manana'
New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
$vistas = @(@{ nombre = 'resumen'; ruta = '/' }, @{ nombre = 'oficina'; ruta = '/oficina.html' })
$tamanos = @(@{ ancho = 1366; alto = 768 }, @{ ancho = 1920; alto = 1080 })
foreach ($v in $vistas) {
  foreach ($t in $tamanos) {
    $salida = Join-Path $carpeta ("p{0}-{1}-{2}-{3}.png" -f $Prueba, $Momento, $v.nombre, $t.ancho)
    $perfil = Join-Path $env:TEMP ("cuadrilla-prueba-edge-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    # El Resumen y la oficina leen la mesa por la misma dirección que usa el navegador: 127.0.0.1, no localhost.
    # Windows PowerShell 5.1 no entrecomilla bien las rutas con espacios: la línea de argumentos va entera y citada a mano.
    $linea = "--headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir=`"$perfil`" --window-size=$($t.ancho),$($t.alto) --virtual-time-budget=$EsperaMs --screenshot=`"$salida`" `"http://127.0.0.1:$puerto$($v.ruta)`""
    # Edge a veces devuelve el control antes de escribir el PNG: se reintenta hasta tres veces.
    for ($intento = 1; $intento -le 3 -and -not (Test-Path -LiteralPath $salida); $intento++) {
      Start-Process -FilePath $edge -ArgumentList $linea -WindowStyle Hidden -Wait
      Start-Sleep -Seconds 2
    }
    Remove-Item -LiteralPath $perfil -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $salida)) { throw "No se generó $salida" }
    Write-Output ("{0}  {1} bytes" -f (Split-Path -Leaf $salida), (Get-Item -LiteralPath $salida).Length)
  }
}
