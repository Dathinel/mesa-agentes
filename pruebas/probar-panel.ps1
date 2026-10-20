# Pruebas del panel web (servidor, token, Origin, ETag y resumen ligero).
# Uso: pruebas\probar-panel.ps1 [-Conservar]
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$h = Join-Path (Split-Path -Parent $PSScriptRoot) 'herramientas'
$panelDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'panel'
$raiz = Join-Path $env:TEMP ("mesa-panel-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'hilos'), (Join-Path $raiz 'reclamos') | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'datos\mesa.ejemplo.json') -Destination (Join-Path $raiz 'mesa.json')
$env:MESA_RAIZ_PRUEBA = $raiz; $env:MESA_SIN_AVISOS = '1'; $env:MESA_SIMULAR = '1'
. "$h\comun.ps1"

# Estado inicial para responder /api/estado de inmediato sin esperar al primer cálculo del trabajador
$estadoInicial = [ordered]@{
  actualizado = (Mesa-IsoNow)
  agentes = @()
  hilos = @()
  pendientes = @()
  cuota = $null
  catalogo = @{}
  alertas = @()
  empleado = $null
  topes = @{}
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $raiz 'estado-panel.json'), $estadoInicial, [Text.Encoding]::UTF8)

$script:fallos = 0
function Caso($nombre, $esperado, $obtenido, [bool]$ok) {
  if (-not $ok) { $script:fallos++ }
  Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}

function Enviar-Http($puerto, $metodo, $ruta, $cabeceras = $null) {
  $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', $puerto)
  $client.SendTimeout = 15000; $client.ReceiveTimeout = 15000
  $stream = $client.GetStream()
  $req = "$metodo $ruta HTTP/1.1`r`nHost: 127.0.0.1:$puerto`r`nConnection: close`r`n"
  if ($cabeceras) {
    foreach ($k in $cabeceras.Keys) {
      $req += "$k`: $($cabeceras[$k])`r`n"
    }
  }
  $req += "`r`n"
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($req)
  $stream.Write($bytes, 0, $bytes.Length)
  $ms = New-Object System.IO.MemoryStream
  $buf = New-Object byte[] 4096
  while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
    $ms.Write($buf, 0, $read)
  }
  $client.Close()
  $respStr = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
  $partes = $respStr -split "`r`n`r`n", 2
  $cabecerasResp = $partes[0] -split "`r`n"
  $statusLine = $cabecerasResp[0]
  $statusCode = [int]($statusLine -split ' ')[1]
  $body = if ($partes.Count -gt 1) { $partes[1] } else { '' }
  $etagLine = @($cabecerasResp | Where-Object { $_ -match '(?i)^ETag:\s*(.+)$' })
  $etag = if ($etagLine.Count) { ($etagLine[0] -replace '(?i)^ETag:\s*', '').Trim() } else { $null }
  return [pscustomobject]@{
    Status = $statusCode
    StatusLine = $statusLine
    Body = $body
    Headers = $cabecerasResp
    ETag = $etag
  }
}

$proc = $null
$puertoLibre = $null
try {
  # Hilo de muestra para /api/hilo
  $hiloPrueba = '20261019-hilo-prueba'
  $hiloPruebaDir = Join-Path $Global:Mesa_Hilos $hiloPrueba
  New-Item -ItemType Directory -Force -Path $hiloPruebaDir | Out-Null
  Mesa-EscribirJson (Join-Path $hiloPruebaDir 'hilo.json') ([ordered]@{
    id = $hiloPrueba; titulo = 'Hilo de prueba panel'; lider = 'claude'; participantes = @('claude', 'agy'); estado = 'abierto'; actualizado = (Mesa-IsoNow)
  })
  Mesa-EscribirJson (Join-Path $hiloPruebaDir '0001-claude.json') ([ordered]@{
    n = 1; autor = 'claude'; para = 'agy'; fecha = (Mesa-IsoNow); texto = 'Mensaje 1 de prueba'; tipo = 'encargo'; estado = 'ejecutando'
  })

  $puertoFile = Join-Path $raiz 'puerto.txt'
  if (Test-Path $puertoFile) { Remove-Item $puertoFile -Force }

  $proc = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$panelDir\servidor.ps1`"", '-PuertoInicial', '8890' -PassThru -WindowStyle Hidden

  $listo = $false
  $inicio = Get-Date
  while (((Get-Date) - $inicio).TotalSeconds -lt 25) {
    if (Test-Path $puertoFile) {
      $puertoContenido = (Get-Content $puertoFile -ErrorAction SilentlyContinue | Out-String).Trim()
      if ($puertoContenido -match '^\d+$') {
        $puertoLibre = [int]$puertoContenido
        try {
          $res = Enviar-Http $puertoLibre 'GET' '/api/ping'
          if ($res.Status -eq 200 -and $res.Body -match '"ok":true') {
            $listo = $true; break
          }
        } catch { }
      }
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not $listo) { throw "El servidor de prueba no respondio a tiempo (puerto=$puertoLibre)." }

  $tokenFile = Join-Path $raiz 'token.txt'
  if (-not (Test-Path $tokenFile)) { throw "No se genero token.txt en la carpeta aislada" }
  $token = (Get-Content -Raw $tokenFile).Trim()

  # 1. Peticion a /api/estado sin token -> 403
  $rSinToken = Enviar-Http $puertoLibre 'GET' '/api/estado' @{ 'Origin' = "http://127.0.0.1:$puertoLibre" }
  Caso 'peticion a /api/estado sin token' '403' "$($rSinToken.Status)" ($rSinToken.Status -eq 403)

  # 2. Con token y Origin ajeno -> 403
  $rAjeno = Enviar-Http $puertoLibre 'GET' '/api/estado' @{ 'X-Mesa-Token' = $token; 'Origin' = 'http://sitio-malicioso.com' }
  Caso 'con token y Origin ajeno' '403' "$($rAjeno.Status)" ($rAjeno.Status -eq 403)

  # 3. Con token y Origin propio -> 200
  $rPropio = Enviar-Http $puertoLibre 'GET' '/api/estado' @{ 'X-Mesa-Token' = $token; 'Origin' = "http://127.0.0.1:$puertoLibre" }
  $tieneEtag = -not [string]::IsNullOrEmpty($rPropio.ETag)
  Caso 'con token y Origin propio' '200' "$($rPropio.Status) (ETag=$($rPropio.ETag))" ($rPropio.Status -eq 200 -and $tieneEtag)

  # 4. Segunda peticion con If-None-Match -> 304
  $etag = $rPropio.ETag
  $r304 = Enviar-Http $puertoLibre 'GET' '/api/estado' @{ 'X-Mesa-Token' = $token; 'Origin' = "http://127.0.0.1:$puertoLibre"; 'If-None-Match' = $etag }
  Caso 'segunda peticion con If-None-Match' '304' "$($r304.Status) (cuerpo=$($r304.Body.Length) bytes)" ($r304.Status -eq 304 -and $r304.Body.Length -eq 0)

  # 5. Tamano del resumen con datos reales < 64 KB (subido de 60: el contrato de estado añade ~0,4 KB por agente)
  $bytesReal = & {
    $env:MESA_RAIZ_PRUEBA = $null
    . "$h\comun.ps1"
    . "$panelDir\estado.ps1"
    $j = (Mesa-SanearObjeto (Obtener-EstadoCompleto)) | ConvertTo-Json -Depth 16 -Compress
    [System.Text.Encoding]::UTF8.GetByteCount($j)
  }
  $env:MESA_RAIZ_PRUEBA = $raiz
  $kbReal = [math]::Round($bytesReal / 1KB, 2)
  Caso 'tamano del resumen con los datos reales < 64 KB' '< 64 KB' "$kbReal KB ($bytesReal bytes)" ($bytesReal -lt 64KB)

  # 6. /api/hilo?id= con id que intente salir de la carpeta (..) -> 400
  $rTraversal1 = Enviar-Http $puertoLibre 'GET' '/api/hilo?id=..\escape' @{ 'X-Mesa-Token' = $token; 'Origin' = "http://127.0.0.1:$puertoLibre" }
  $rTraversal2 = Enviar-Http $puertoLibre 'GET' '/api/hilo?id=../escape' @{ 'X-Mesa-Token' = $token; 'Origin' = "http://127.0.0.1:$puertoLibre" }
  $okTraversal = ($rTraversal1.Status -eq 400 -and $rTraversal2.Status -eq 400)
  Caso '/api/hilo?id= con intento de salida (..\)' '400' "..\\ -> $($rTraversal1.Status), ../ -> $($rTraversal2.Status)" $okTraversal

  # 7. /api/hilo?id= bajo demanda valido -> 200
  $rHiloOk = Enviar-Http $puertoLibre 'GET' "/api/hilo?id=$hiloPrueba" @{ 'X-Mesa-Token' = $token; 'Origin' = "http://127.0.0.1:$puertoLibre" }
  Caso '/api/hilo?id= bajo demanda de un hilo existente' '200' "$($rHiloOk.Status)" ($rHiloOk.Status -eq 200 -and $rHiloOk.Body -match 'Mensaje 1 de prueba')

  # 8. Captura Edge headless sin ventana
  $edgeBin = if (Get-Command msedge -ErrorAction SilentlyContinue) {
    (Get-Command msedge).Source
  } elseif (Test-Path "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe") {
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
  } elseif (Test-Path "C:\Program Files\Microsoft\Edge\Application\msedge.exe") {
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
  } else { "msedge" }

  $capturaPng = Join-Path $env:TEMP 'edge-agy\captura-oficina.png'
  $tempUserData = Join-Path $env:TEMP 'edge-agy'
  if (-not (Test-Path $tempUserData)) { New-Item -ItemType Directory -Force -Path $tempUserData | Out-Null }
  if (Test-Path $capturaPng) { Remove-Item $capturaPng -Force }

  $edgeArgs = @(
    '--headless=new',
    '--disable-gpu',
    "--user-data-dir=$tempUserData",
    '--window-size=1600,900',
    '--virtual-time-budget=8000',
    "--screenshot=$capturaPng",
    "http://127.0.0.1:$puertoLibre/"
  )
  $edgeProc = Start-Process -FilePath $edgeBin -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden
  $edgeProc.WaitForExit(20000) | Out-Null

  $pngTam = if (Test-Path $capturaPng) { (Get-Item $capturaPng).Length } else { 0 }
  $pngOk = ($pngTam -gt 10000)
  Caso 'captura sin interfaz de la oficina' '> 10 KB' "$pngTam bytes en $capturaPng" $pngOk

} catch {
  $script:fallos++
  Write-Host "ERROR de la prueba: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)" -ForegroundColor Red
} finally {
  if ($proc) {
    try {
      Get-CimInstance Win32_Process | Where-Object { $_.ParentProcessId -eq $proc.Id } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
      }
    } catch { }
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      $proc.WaitForExit(3000) | Out-Null
    }
  }
  if ($puertoLibre) {
    try {
      Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like "*servidor.ps1*" -and $_.CommandLine -like "*$puertoLibre*" } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
      }
    } catch { }
  }
  Remove-Item Env:MESA_RAIZ_PRUEBA, Env:MESA_SIN_AVISOS, Env:MESA_SIMULAR -ErrorAction SilentlyContinue
  if (-not $Conservar) {
    Remove-Item -LiteralPath $raiz -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Host "Copia conservada en $raiz"
  }
}
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
