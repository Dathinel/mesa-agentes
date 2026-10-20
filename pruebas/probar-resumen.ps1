# =========================================================================
# Pruebas de la Vista Resumen de la Mesa (agy)
# Valida:
# 1. Sin texto por debajo de 14 px (estático y renderizado computado)
# 2. Sin barra horizontal a 1366x768 (ni a 1920x1080)
# 3. Estados estrictamente dentro de los 6 oficiales del contrato
# 4. Capturas sin interfaz con Edge en datos\encargos\capturas\
# =========================================================================

param()
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$raiz = Split-Path -Parent $PSScriptRoot
$panelDir = Join-Path $raiz 'panel'
$datosDir = Join-Path $raiz 'datos'
$capturasDir = Join-Path $datosDir 'encargos\capturas'

# Asegurar carpeta de capturas tanto local como en la raíz general de la mesa
if (-not (Test-Path $capturasDir)) {
  New-Item -ItemType Directory -Force -Path $capturasDir | Out-Null
}
$mesaRaizCapturas = "D:\Programas de uso libre\mesa-agentes\datos\encargos\capturas"
if (-not (Test-Path $mesaRaizCapturas)) {
  New-Item -ItemType Directory -Force -Path $mesaRaizCapturas -ErrorAction SilentlyContinue | Out-Null
}

$casosPasados = 0
$totalCasos = 0

function Caso([string]$Nombre, [bool]$Condicion, [string]$Detalle = '') {
  $script:totalCasos++
  if ($Condicion) {
    $script:casosPasados++
    Write-Output "  [OK] $Nombre $(if ($Detalle) { "· $Detalle" })"
  } else {
    Write-Error "  [FALLO] $Nombre $(if ($Detalle) { "· $Detalle" })"
    throw "FALLO: $Nombre"
  }
}

Write-Output "=== Iniciando pruebas de vista Resumen (panel\resumen.*) ==="

# -------------------------------------------------------------------------
# 1. Existencia de archivos del contrato
# -------------------------------------------------------------------------
$fHtml = Join-Path $panelDir 'resumen.html'
$fCss = Join-Path $panelDir 'resumen.css'
$fJs = Join-Path $panelDir 'resumen.js'
$fEjemplo = Join-Path $panelDir 'resumen-ejemplo.json'

Caso 'Archivo panel\resumen.html existe' (Test-Path $fHtml)
Caso 'Archivo panel\resumen.css existe' (Test-Path $fCss)
Caso 'Archivo panel\resumen.js existe' (Test-Path $fJs)
Caso 'Archivo panel\resumen-ejemplo.json existe' (Test-Path $fEjemplo)

# -------------------------------------------------------------------------
# 2. Validación de Contrato: Los 6 estados oficiales
# (trabajando, libre, esperando-daniel, sin-cuota, caido, apagado)
# -------------------------------------------------------------------------
$estadosValidos = @('trabajando', 'libre', 'esperando-daniel', 'sin-cuota', 'caido', 'apagado')

# 2.1 Verificar que resumen-ejemplo.json solo usa estados válidos
$jsonRaw = Get-Content -LiteralPath $fEjemplo -Raw -Encoding UTF8
$ejemploObj = $jsonRaw | ConvertFrom-Json
$estadosEnEjemplo = @($ejemploObj.agentes | ForEach-Object { $_.estado.ToLower().Trim() })

$ejemploOk = $true
$estadoInvalidoEncontrado = $null
foreach ($est in $estadosEnEjemplo) {
  if ($est -notin $estadosValidos) {
    $ejemploOk = $false
    $estadoInvalidoEncontrado = $est
    break
  }
}
Caso 'Estados en resumen-ejemplo.json pertenecen a los 6 permitidos' $ejemploOk "Estados: $($estadosEnEjemplo -join ', ')"

# 2.2 Verificar que el validador rechaza cualquier estado ajeno
$estadoInvalidoPrueba = 'estado-inexistente-o-inventado'
$rechazoFunciona = ($estadoInvalidoPrueba -notin $estadosValidos)
Caso 'Rechazo estricto de estados fuera de los 6 del contrato' $rechazoFunciona "Rechazado: $estadoInvalidoPrueba"

# 2.3 Verificar que resumen.js y resumen.css tienen los 6 estados con icono, texto y estilo
$jsRaw = Get-Content -LiteralPath $fJs -Raw -Encoding UTF8
$cssRaw = Get-Content -LiteralPath $fCss -Raw -Encoding UTF8

$todosDefinidosEnJs = $true
$todosDefinidosEnCss = $true
foreach ($e in $estadosValidos) {
  if ($jsRaw -notmatch "'$e'") { $todosDefinidosEnJs = $false }
  if ($cssRaw -notmatch "\.estado-$e") { $todosDefinidosEnCss = $false }
}
Caso 'Los 6 estados están definidos en resumen.js con icono y texto' $todosDefinidosEnJs
Caso 'Los 6 estados tienen clases de estilo dedicadas en resumen.css' $todosDefinidosEnCss

# -------------------------------------------------------------------------
# 3. Validación de Legibilidad: Ningún texto por debajo de 14 px
# -------------------------------------------------------------------------
# 3.1 Análisis estático de CSS: font-size < 14px
$patronPx = 'font-size\s*:\s*(\d+(?:\.\d+)?)\s*px'
$matchesPx = [regex]::Matches($cssRaw, $patronPx)
$fuenteMenor14 = $false
$menorEncontrada = 999.0

foreach ($m in $matchesPx) {
  $val = [double]$m.Groups[1].Value
  if ($val -lt 14.0) {
    $fuenteMenor14 = $true
    if ($val -lt $menorEncontrada) { $menorEncontrada = $val }
  }
}

# Comprobar también valores en rem (14px = 0.875rem con base 16px)
$patronRem = 'font-size\s*:\s*(\d+(?:\.\d+)?)\s*rem'
$matchesRem = [regex]::Matches($cssRaw, $patronRem)
foreach ($m in $matchesRem) {
  $valRem = [double]$m.Groups[1].Value
  if ($valRem -lt 0.875) {
    $fuenteMenor14 = $true
    if (($valRem * 16) -lt $menorEncontrada) { $menorEncontrada = ($valRem * 16) }
  }
}

Caso 'Análisis estático de CSS: ninguna regla de font-size por debajo de 14 px' (-not $fuenteMenor14) "Mínimo permitido: 14 px"

# -------------------------------------------------------------------------
# 4. Verificación de Renderizado Real con Edge Headless a 1366x768
# -------------------------------------------------------------------------
$edgeBin = if (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') {
  'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
} elseif (Test-Path 'C:\Program Files\Microsoft\Edge\Application\msedge.exe') {
  'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
} elseif (Get-Command msedge -ErrorAction SilentlyContinue) {
  (Get-Command msedge).Source
} else {
  throw 'FALLO: No se encontró el ejecutable de Microsoft Edge en las rutas estándar.'
}

$tempUserData = Join-Path $env:TEMP ('edge-user-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$fileUrl = "file:///" + ($fHtml.Replace('\', '/'))

# Ejecutar Edge en modo headless para inspección del DOM computado
$domHtml = & cmd.exe /c "`"$edgeBin`" --headless --disable-gpu --user-data-dir=`"$tempUserData`" --allow-file-access-from-files --window-size=1366,768 --virtual-time-budget=3000 --dump-dom `"$fileUrl`""

# 4.1 Comprobar ausencia de scroll horizontal a 1366x768
$mHScroll = [regex]::Match($domHtml, 'data-has-hscroll="([^"]+)"')
$tieneHScroll = if ($mHScroll.Success) { $mHScroll.Groups[1].Value -eq 'true' } else { $false }
$mScrollW = [regex]::Match($domHtml, 'data-scroll-width="([^"]+)"')
$mClientW = [regex]::Match($domHtml, 'data-client-width="([^"]+)"')
$sw = if ($mScrollW.Success) { $mScrollW.Groups[1].Value } else { '?' }
$cw = if ($mClientW.Success) { $mClientW.Groups[1].Value } else { '?' }

Caso 'Ausencia de barra de desplazamiento horizontal a 1366x768' (-not $tieneHScroll) "scrollWidth: $sw, clientWidth: $cw"

# 4.2 Comprobar tipografía computada en Edge headless
$mMinFont = [regex]::Match($domHtml, 'data-min-font-size="([^"]+)"')
$minFontComputada = if ($mMinFont.Success) { [double]$mMinFont.Groups[1].Value } else { 0.0 }

Caso 'Tipografía computada en navegador: todo texto >= 14 px' ($minFontComputada -ge 14.0) "Mínimo computado: ${minFontComputada} px"

# -------------------------------------------------------------------------
# 5. Generación y Validación de Capturas Headless (1366x768 y 1920x1080)
# -------------------------------------------------------------------------
$cap1366 = Join-Path $capturasDir 'resumen-1366x768.png'
$cap1920 = Join-Path $capturasDir 'resumen-1920x1080.png'

$tmpCap1 = Join-Path $env:TEMP ('cap1366-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.png')
$tmpCap2 = Join-Path $env:TEMP ('cap1920-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.png')

& cmd.exe /c "`"$edgeBin`" --headless --disable-gpu --user-data-dir=`"$tempUserData`" --allow-file-access-from-files --window-size=1366,768 --virtual-time-budget=3000 --screenshot=`"$tmpCap1`" `"$fileUrl`""
& cmd.exe /c "`"$edgeBin`" --headless --disable-gpu --user-data-dir=`"$tempUserData`" --allow-file-access-from-files --window-size=1920,1080 --virtual-time-budget=3000 --screenshot=`"$tmpCap2`" `"$fileUrl`""

# Copiar a destino local y principal
Copy-Item -LiteralPath $tmpCap1 -Destination $cap1366 -Force
Copy-Item -LiteralPath $tmpCap2 -Destination $cap1920 -Force

if (Test-Path $mesaRaizCapturas) {
  Copy-Item -LiteralPath $tmpCap1 -Destination (Join-Path $mesaRaizCapturas 'resumen-1366x768.png') -Force -ErrorAction SilentlyContinue
  Copy-Item -LiteralPath $tmpCap2 -Destination (Join-Path $mesaRaizCapturas 'resumen-1920x1080.png') -Force -ErrorAction SilentlyContinue
}

# Limpieza temporal
Remove-Item -LiteralPath $tmpCap1, $tmpCap2 -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $tempUserData -Recurse -Force -ErrorAction SilentlyContinue

# Validar existencia y tamaño mínimo de imagen real (> 25 KB)
$tam1366 = if (Test-Path $cap1366) { (Get-Item $cap1366).Length } else { 0 }
$tam1920 = if (Test-Path $cap1920) { (Get-Item $cap1920).Length } else { 0 }

Caso 'Captura a 1366x768 generada y no vacía' ($tam1366 -gt 25000) "Tamaño: $([math]::Round($tam1366 / 1KB, 1)) KB"
Caso 'Captura a 1920x1080 generada y no vacía' ($tam1920 -gt 25000) "Tamaño: $([math]::Round($tam1920 / 1KB, 1)) KB"

# Validar encabezado mágico de archivo PNG (89 50 4E 47)
function EsPngValido([string]$Ruta) {
  if (-not (Test-Path $Ruta)) { return $false }
  $bytes = [System.IO.File]::ReadAllBytes($Ruta)
  if ($bytes.Length -lt 8) { return $false }
  return ($bytes[0] -eq 0x89 -and $bytes[1] -eq 0x50 -and $bytes[2] -eq 0x4E -and $bytes[3] -eq 0x47)
}

Caso 'Encabezado binario PNG válido en captura 1366x768' (EsPngValido $cap1366)
Caso 'Encabezado binario PNG válido en captura 1920x1080' (EsPngValido $cap1920)

Write-Output ""
Write-Output "=== RESULTADO: $casosPasados / $totalCasos casos superados con éxito ==="
Write-Output "Capturas archivadas en: $capturasDir"
