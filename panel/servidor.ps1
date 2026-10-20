# Servidor web local para el panel de la Mesa de agentes.
# TCP/HTTP mínimo de solo lectura en 127.0.0.1; compatible con PowerShell 5.1.
param([int]$PuertoInicial = 8790)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$panelDir = $PSScriptRoot
$mesaBase = Split-Path -Parent $panelDir
$datosDir = Join-Path $mesaBase 'datos'
$hilosDir = Join-Path $datosDir 'hilos'
$puertoArchivo = Join-Path $panelDir 'puerto.txt'
. (Join-Path $mesaBase 'herramientas\comun.ps1')

# Una sola instancia: si el panel ya responde en su puerto, no se arranca otro. Si arrancara en otro puerto,
# la página abierta seguiría preguntando al viejo y se quedaría «Sin conexión» hasta pulsar F5.
try {
  $r = Invoke-WebRequest "http://127.0.0.1:$PuertoInicial/api/ping" -UseBasicParsing -TimeoutSec 2
  if ($r.Content -match '"ok"') { Write-Output "El panel ya está en http://127.0.0.1:$PuertoInicial/"; return }
} catch { }

. (Join-Path $panelDir 'estado.ps1')
$cacheArchivo = Join-Path $datosDir 'estado-panel.json'

# Calcular el estado tarda de 15 a 25 s (recorre las sesiones): lo hace un trabajador aparte que deja el último
# resultado en un archivo, y el servidor solo lo lee. Así la página y la API responden al momento.
$trabajador = {
  param($panelDir, $mesaBase, $cacheArchivo)
  $ErrorActionPreference = 'Continue'
  $datosDir = Join-Path $mesaBase 'datos'; $hilosDir = Join-Path $datosDir 'hilos'
  . (Join-Path $mesaBase 'herramientas\comun.ps1')
  . (Join-Path $panelDir 'estado.ps1')
  . (Join-Path $mesaBase 'herramientas\vigia.ps1') -Biblioteca
  $ultimaCuota = [datetime]::MinValue
  while ($true) {
    try { Invocar-Vigia } catch { }
    if (((Get-Date) - $ultimaCuota).TotalSeconds -ge 60) {
      try { & (Join-Path $mesaBase 'herramientas\cuota.ps1') | Out-Null } catch { }
      $ultimaCuota = Get-Date
    }
    try {
      $json = (Mesa-SanearObjeto (Obtener-EstadoCompleto)) | ConvertTo-Json -Depth 16 -Compress
      $tmp = "$cacheArchivo.tmp"
      [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
      Move-Item -LiteralPath $tmp -Destination $cacheArchivo -Force
    } catch { }
    Start-Sleep -Seconds 3
  }
}
$script:job = $null
function Asegurar-Trabajador {
  if (!$script:job -or $script:job.State -ne 'Running') {
    if ($script:job) { Remove-Job $script:job -Force -ErrorAction SilentlyContinue }
    $script:job = Start-Job -ScriptBlock $trabajador -ArgumentList $panelDir, $mesaBase, $cacheArchivo
  }
}
Asegurar-Trabajador
$script:ultimaRevision = Get-Date

$listener=$null; $listeningPort=$null
for ($port=$PuertoInicial; $port -lt $PuertoInicial+10; $port++) {
  try {
    $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port)
    $listener.Start(); $listeningPort=$port; break
  } catch { if ($listener) { $listener.Stop() } }
}
if (!$listeningPort) { throw 'No hay puerto local disponible.' }
[IO.File]::WriteAllText($puertoArchivo,[string]$listeningPort,[Text.Encoding]::ASCII)
Write-Output "Panel disponible en http://127.0.0.1:$listeningPort/"
$ultimaVisita=Get-Date
try {
  while ($true) {
    if (((Get-Date) - $script:ultimaRevision).TotalSeconds -ge 15) { Asegurar-Trabajador; $script:ultimaRevision = Get-Date }
    if (!$listener.Pending()) {
      if (((Get-Date)-$ultimaVisita).TotalMinutes -ge 30) { break }
      Start-Sleep -Milliseconds 100; continue
    }
    $client=$listener.AcceptTcpClient(); $client.ReceiveTimeout=1500; $client.SendTimeout=3000
    try {
      $stream=$client.GetStream(); $buf=New-Object byte[] 16384; $count=0; $headers=''
      while ($count -lt $buf.Length) {
        $n=$stream.Read($buf,$count,$buf.Length-$count)
        if (!$n) { break }; $count+=$n
        $headers=[Text.Encoding]::ASCII.GetString($buf,0,$count)
        if ($headers.Contains("`r`n`r`n")) { break }
      }
      if (!$headers.Contains("`r`n`r`n")) { continue }
      $primera=($headers -split "`r`n")[0] -split ' '
      if ($primera.Count -ne 3) { continue }
      $metodo=$primera[0]; $path=($primera[1] -split '\?')[0]
      $body=''; $contentType='text/plain; charset=utf-8'; $status=200; $ultimaVisita=Get-Date
      try {
        if ($headers -notmatch ('(?im)^Host:\s*127\.0\.0\.1:'+ $listeningPort +'\s*$')) { $status=403; $body='Host no permitido' }
        elseif ($metodo -notin @('GET','HEAD')) { $status=405; $body='Solo lectura' }
        elseif ($path -in @('/','/index.html','/oficina.js','/oficina.css','/arte-v1.js','/reclamos.js')) {
          $archivo=if ($path -eq '/') { 'index.html' } else { $path.TrimStart('/') }
          $body=[IO.File]::ReadAllText((Join-Path $panelDir $archivo),[Text.Encoding]::UTF8)
          $contentType=switch ([IO.Path]::GetExtension($archivo)) { '.js' { 'application/javascript; charset=utf-8' }; '.css' { 'text/css; charset=utf-8' }; default { 'text/html; charset=utf-8' } }
        } elseif ($path -eq '/api/estado') {
          # Solo la primera vez, antes de que el trabajador escriba su primer resultado, se calcula aquí.
          if (Test-Path -LiteralPath $cacheArchivo) { $body=[IO.File]::ReadAllText($cacheArchivo,[Text.Encoding]::UTF8) }
          else { $body=(Mesa-SanearObjeto (Obtener-EstadoCompleto)) | ConvertTo-Json -Depth 16 -Compress }
          $contentType='application/json; charset=utf-8'
        } elseif ($path -eq '/api/ping') { $body='{"ok":true}'; $contentType='application/json; charset=utf-8' }
        else { $status=404; $body='No encontrado' }
      } catch {
        $status=500; $body='{"error":"No se pudo leer el estado local"}'; $contentType='application/json; charset=utf-8'
        Write-Warning (Mesa-Ocultar ($_.Exception.Message+' en '+$_.InvocationInfo.PositionMessage))
      }
      $bytes=[Text.Encoding]::UTF8.GetBytes($body)
      $reason=switch ($status) { 200 {'OK'}; 403 {'Forbidden'}; 404 {'Not Found'}; 405 {'Method Not Allowed'}; default {'Internal Server Error'} }
      $cabecera="HTTP/1.1 $status $reason`r`nContent-Type: $contentType`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nAllow: GET, HEAD`r`nX-Content-Type-Options: nosniff`r`nContent-Security-Policy: default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'`r`n`r`n"
      $hb=[Text.Encoding]::ASCII.GetBytes($cabecera); $stream.Write($hb,0,$hb.Length)
      if ($metodo -ne 'HEAD') { $stream.Write($bytes,0,$bytes.Length) }
    } catch { } finally { $client.Close() }
  }
} finally {
  if ($script:job) { Stop-Job $script:job -ErrorAction SilentlyContinue; Remove-Job $script:job -Force -ErrorAction SilentlyContinue }
  $listener.Stop()
  if ((Test-Path -LiteralPath $puertoArchivo) -and ([IO.File]::ReadAllText($puertoArchivo) -eq [string]$listeningPort)) { Remove-Item -LiteralPath $puertoArchivo -Force }
}
