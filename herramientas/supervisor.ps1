# Supervisor de la Mesa, sin modelo: cada -Intervalo segundos mira si algún agente murió, se colgó o se quedó sin cuota,
# deja su estado en datos\agentes\<agente>.json, avisa al líder en el hilo y a la persona con una notificación de Windows,
# y anota todo en la bitácora del día (datos\bitacora\AAAA-MM-DD.md). No reinicia nada salvo que mesa.json lo active.
# Uso: supervisor.ps1 [-Intervalo 30] [-UnaVez] [-SinAvisos]
param(
  [int]$Intervalo = 30,
  [switch]$UnaVez,
  [switch]$SinAvisos
)
. "$PSScriptRoot\comun.ps1"
if ($env:MESA_SIN_AVISOS -eq '1') { $SinAvisos = [switch]$true }

$cfgSup = (Mesa-LeerJson (Mesa-ConfigPath)).supervisor
function Cfg($nombre, $porDefecto) { if ($cfgSup -and $null -ne $cfgSup.$nombre) { $cfgSup.$nombre } else { $porDefecto } }
$colgadoMin = Cfg 'colgado_min' 30
$reclamoMin = Cfg 'reclamo_min' 60
$latidoSeg = Cfg 'latido_seg' 90
$relanzar = Cfg 'relanzar' $false
$maxRelanzar = Cfg 'max_relanzar' 3
$ventanaMin = Cfg 'ventana_min' 10

$dirAgentes = Join-Path $Global:Mesa_Raiz 'agentes'
$rutaMemoria = Join-Path $Global:Mesa_Raiz 'supervisor-estado.json'
New-Item -ItemType Directory -Force -Path $dirAgentes, (Join-Path $Global:Mesa_Raiz 'bitacora'), (Join-Path $Global:Mesa_Raiz 'archivo') | Out-Null

# Una sola instancia: el candado lo suelta Windows aunque el proceso muera.
try { $unico = [IO.File]::Open((Join-Path $Global:Mesa_Raiz 'supervisor.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { Write-Output 'Ya hay un supervisor en marcha.'; exit 0 }

function Bitacora($texto) {
  Mesa-AnexarLinea (Join-Path $Global:Mesa_Raiz ("bitacora\{0}.md" -f (Get-Date -Format 'yyyy-MM-dd'))) ("- {0} · {1}" -f (Get-Date -Format 'HH:mm'), $texto)
}

function Avisar($titulo, $texto) {
  if ($SinAvisos) { return }
  try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $t = $xml.GetElementsByTagName('text')
    [void]$t.Item(0).AppendChild($xml.CreateTextNode("Mesa · $titulo"))
    [void]$t.Item(1).AppendChild($xml.CreateTextNode($texto))
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show([Windows.UI.Notifications.ToastNotification]::new($xml))
  } catch {}
}

# Cada problema se cuenta una vez, en tres partes: qué pasó, qué hizo el sistema y qué necesita de la persona.
function Informar($clave, $memoria, $hilo, $para, $paso, $hice, $necesito) {
  if ($memoria.avisados.PSObject.Properties[$clave]) { return }
  if ($script:tolerante -and $clave -notlike 'huerfano-*' -and $clave -notlike 'cuota-*' -and $clave -notlike 'login-*') { return }
  $memoria.avisados | Add-Member $clave (Mesa-IsoNow)
  $texto = "Qué pasó: $paso · Qué hice: $hice · Qué necesito: $necesito"
  Bitacora $texto
  Avisar $paso $necesito
  if ($hilo -and (Test-Path -LiteralPath (Join-Path (Join-Path $Global:Mesa_Hilos $hilo) 'hilo.json'))) {
    try { & "$PSScriptRoot\mesa.ps1" enviar -Hilo $hilo -De supervisor -Para $para -Texto "[SUPERVISOR] $texto" -SoloNota | Out-Null } catch {}
  }
}

function Vivo($id) { $id -and (Get-Process -Id $id -ErrorAction SilentlyContinue) }

function Rotar($nombre, $maxMB) {
  $f = Join-Path $Global:Mesa_Raiz $nombre
  if (-not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -lt $maxMB * 1MB) { return }
  $candado = Mesa-Bloquear $f
  try {
    $destino = Join-Path $Global:Mesa_Raiz ("archivo\{0}-{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($nombre), (Get-Date -Format 'yyyyMMdd-HHmm'), [IO.Path]::GetExtension($nombre))
    Move-Item -LiteralPath $f -Destination $destino
    Bitacora "Archivé $nombre (más de $maxMB MB) en $destino."
  } catch {} finally { $candado.Dispose() }
}

function Vuelta {
  # Tras una suspensión del PC (o un supervisor parado) los latidos envejecen de golpe: esa vuelta no avisa de caídas,
  # solo renueva las referencias. Un proceso muerto sigue siendo huérfano: eso no lo causa el reloj.
  $latSup = Join-Path $dirAgentes 'supervisor.latido'
  $salto = if (Test-Path -LiteralPath $latSup) { ((Get-Date) - (Get-Item -LiteralPath $latSup).LastWriteTime).TotalSeconds } else { 0 }
  $script:tolerante = $salto -gt 2 * [Math]::Max($Intervalo, 30)
  if ($script:tolerante) { Bitacora "Vuelta tras un salto de $([int]($salto / 60)) min (suspensión o supervisor parado): no aviso de caídas en esta vuelta." }
  $memoria = Mesa-LeerJson $rutaMemoria
  if (-not $memoria) { $memoria = [pscustomobject]@{ avisados = [pscustomobject]@{}; relanzados = [pscustomobject]@{} } }
  $ahora = Get-Date
  $estado = @{}
  foreach ($a in $Global:Mesa_Agentes) { $estado[$a] = [ordered]@{ agente = $a; estado = 'libre'; motivo = ''; hilo = $null; n = $null; latido = $null; actualizado = (Mesa-IsoNow); hasta = $null } }

  # 1. Encargos en curso: vivos, colgados o huérfanos. Y la última causa de fallo de cada agente (cuota, login).
  $ultimoFin = @{}
  foreach ($d in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue)) {
    $lider = (Mesa-LeerMensaje (Join-Path $d.FullName 'hilo.json')).lider
    foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter '*-*.json' -ErrorAction SilentlyContinue)) {
      $m = Mesa-LeerMensaje $f.FullName
      if (-not $m -or -not $m.llamada -or -not $m.herramienta -or $m.herramienta -notin $Global:Mesa_Agentes) { continue }
      $a = $m.herramienta
      if ($m.tipo -eq 'encargo' -and $m.estado -eq 'ejecutando') {
        $log = $m.llamada.log
        $logEdad = if ($log -and (Test-Path -LiteralPath $log)) { ($ahora - (Get-Item -LiteralPath $log).LastWriteTime).TotalMinutes } else { ($ahora - [datetime]::Parse($m.llamada.inicio)).TotalMinutes }
        $tienePid = $m.llamada.PSObject.Properties['pid'] -and $m.llamada.pid
        $muerto = if ($tienePid) { -not (Vivo $m.llamada.pid) } else { $logEdad -gt 120 }
        $clave = "$($d.Name)#$($m.n)"
        $intento = "$($m.llamada.inicio)"
        if ($muerto) {
          # Releer bajo el candado del hilo: si ejecutar.ps1 terminó entretanto, su resultado no se pisa.
          $candado = Mesa-BloquearHilo $d.FullName
          try {
            $actual = Mesa-LeerMensaje $f.FullName
            if (-not $actual -or $actual.estado -ne 'ejecutando' -or "$($actual.llamada.inicio)" -ne $intento) { continue }
            $actual.estado = 'huerfano'; $actual.llamada.fin = Mesa-IsoNow
            Mesa-EscribirJson $f.FullName $actual
          } finally { $candado.Dispose() }
          $hace = [int](($ahora - [datetime]::Parse($m.llamada.inicio)).TotalHours)
          Informar "huerfano-$clave-$intento" $memoria $(if ($hace -lt 24) { $d.Name }) $m.autor "el encargo $clave de $a quedó huérfano: su proceso ya no existe (empezó hace $hace h)" `
            'lo marqué como huérfano; su reclamo y sus puntos de control siguen en el hilo' "que el líder lo relance con: mesa.ps1 reintentar -Hilo $($d.Name) -N $($m.n) -De <líder>"
          continue
        }
        $estado[$a].estado = 'trabajando'; $estado[$a].hilo = $d.Name; $estado[$a].n = [int]$m.n; $estado[$a].motivo = "encargo #$($m.n) desde $($m.llamada.inicio)"
        $cola = ''
        if ($log -and (Test-Path -LiteralPath $log)) { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); try { [void]$fs.Seek([Math]::Max(0, $fs.Length - 2000), 'Begin'); $cola = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } }
        $sinRed = $cola -match '(?i)waiting for network' -and ($ahora - [datetime]::Parse($m.llamada.inicio)).TotalMinutes -gt 10
        if ($logEdad -gt $colgadoMin -or $sinRed) {
          $estado[$a].estado = 'colgado'; $estado[$a].motivo = if ($sinRed) { 'sin red: el CLI reintenta conectar' } else { "sin salida nueva en $([int]$logEdad) min" }
          Informar "colgado-$clave-$intento" $memoria $d.Name $m.autor "$a lleva $([int]$logEdad) min sin avanzar en $clave ($($estado[$a].motivo))" 'nada todavía: el proceso sigue vivo' `
            "si no responde, córtalo con mesa.ps1 cortar -Hilo $($d.Name) -N $($m.n) -De <líder> y luego reintentar"
        }
      } elseif ($m.llamada.fin -and ($m.tipo -eq 'encargo')) {
        $fin = [datetime]::Parse($m.llamada.fin)
        if (-not $ultimoFin[$a] -or $fin -gt $ultimoFin[$a].fin) { $ultimoFin[$a] = @{ fin = $fin; m = $m; hilo = $d.Name; lider = $lider } }
      }
    }
  }
  foreach ($a in $Global:Mesa_Agentes) {
    $u = $ultimoFin[$a]
    if ($estado[$a].estado -ne 'libre' -or -not $u -or -not $u.m.llamada.PSObject.Properties['causa'] -or -not $u.m.llamada.causa) { continue }
    $causa = $u.m.llamada.causa; $hasta = $u.m.llamada.hasta
    if ($causa -eq 'sin-cuota' -and $hasta -and [datetime]::Parse($hasta) -gt $ahora) {
      $estado[$a].estado = 'sin-cuota'; $estado[$a].hasta = $hasta; $estado[$a].motivo = "cuota agotada hasta $hasta"
      Informar "cuota-$a-$hasta" $memoria $u.hilo $u.lider "$a se quedó sin cuota (vuelve $hasta)" 'lo marqué sin cuota; no es una caída' 'que el líder reasigne sus encargos a otro agente'
    } elseif ($causa -eq 'necesita-login' -and ($ahora - $u.fin).TotalHours -lt 12) {
      $estado[$a].estado = 'necesita-login'; $estado[$a].motivo = 'la sesión del CLI caducó'
      Informar "login-$a-$($u.m.llamada.fin)" $memoria $u.hilo $u.lider "$a no tiene sesión iniciada" 'lo marqué como necesita login' "que inicies sesión en $a (en su consola) y relances el encargo"
    }
  }

  # 2. Señales de vida: paneles de codex y agy por su latido; claude interactivo por su proceso.
  foreach ($a in $Global:Mesa_Agentes) {
    $ult = Mesa-UltimaActividad $a
    $latFile = Join-Path $Global:Mesa_Raiz "trabajador-$a.latido"
    if (Test-Path -LiteralPath $latFile) { $lt = (Get-Item -LiteralPath $latFile).LastWriteTime; if ($lt -gt $ult) { $ult = $lt } }
    if ($ult -gt [datetime]::MinValue) { $estado[$a].latido = $ult.ToString('yyyy-MM-ddTHH:mm:sszzz') }
    $panelCaido = if ($a -eq 'claude') { -not (Get-Process -Name claude -ErrorAction SilentlyContinue) }
                  else { (Test-Path -LiteralPath $latFile) -and ($ahora - (Get-Item -LiteralPath $latFile).LastWriteTime).TotalSeconds -gt $latidoSeg }
    if ($panelCaido -and $estado[$a].estado -eq 'libre' -and -not $script:tolerante) {
      $estado[$a].estado = 'caido'; $estado[$a].motivo = if ($a -eq 'claude') { 'no hay ningún proceso de claude' } else { 'su panel no da latido' }
      $memoria.avisados.PSObject.Properties.Remove("vivo-$a")
      $relanzado = $false
      if ($relanzar -and $a -ne 'claude') {
        $lista = @(@($memoria.relanzados.$a) | Where-Object { $_ -and ($ahora - [datetime]::Parse($_)).TotalMinutes -lt $ventanaMin })
        if ($lista.Count -lt $maxRelanzar) {
          & wt.exe -w mesa new-tab --title $a -d $Global:Mesa_Base powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'trabajador.ps1') -Agente $a
          $memoria.relanzados | Add-Member $a @($lista + (Mesa-IsoNow)) -Force
          $relanzado = $true
          Bitacora "Relancé el panel de $a ($($lista.Count + 1) de $maxRelanzar en $ventanaMin min)."
        }
      }
      if (-not $relanzado) {
        $tarea = @(Mesa-Reclamos | Where-Object { (Mesa-NormalizarHerramienta $_.agente) -eq $a -and $_.tarea -ne 'lider' } | Select-Object -First 1)
        $hilo = if ($tarea.Count) { $tarea[0].hilo }
        $lider = if ($hilo) { (Mesa-LeerMensaje (Join-Path (Join-Path $Global:Mesa_Hilos $hilo) 'hilo.json')).lider }
        $necesito = if ($a -eq 'claude') { 'que abras claude (Mesa.bat lo reanuda con --continue)' } else { "que lo reabras con: Mesa.bat panel $a" }
        Informar "caido-$a-$(Get-Date -Format 'yyyyMMdd')" $memoria $hilo $lider "el panel de $a se cayó ($($estado[$a].motivo))$(if ($tarea.Count) { " con la tarea $($tarea[0].tarea)" })" `
          $(if ($relanzar) { "no lo relancé: ya van $maxRelanzar intentos en $ventanaMin min" } else { 'nada: el relanzado automático está apagado en mesa.json' }) $necesito
      }
    } elseif (-not $panelCaido) {
      foreach ($p in @($memoria.avisados.PSObject.Properties | Where-Object { $_.Name -like "caido-$a-*" })) { $memoria.avisados.PSObject.Properties.Remove($p.Name); Bitacora "El panel de $a volvió." }
    }
  }

  # 3. Reclamos sin señal de vida de su agente: arriendo caducado. El líder decide si lo suelta y lo reasigna.
  foreach ($r in @(Mesa-Reclamos | Where-Object { $_.tarea -ne 'lider' -and $_.tarea -notlike 'archivo-*' })) {
    $a = Mesa-NormalizarHerramienta $r.agente
    if (-not $a -or $estado[$a].estado -eq 'trabajando') { continue }
    $ult = @((Mesa-UltimaActividad $a), [datetime]::Parse($r.fecha)) | Sort-Object | Select-Object -Last 1
    if (($ahora - $ult).TotalMinutes -lt $reclamoMin) { continue }
    $lider = if ($r.hilo) { (Mesa-LeerMensaje (Join-Path (Join-Path $Global:Mesa_Hilos $r.hilo) 'hilo.json')).lider }
    Informar "reclamo-$($r.tarea)-$($r.fecha)" $memoria $r.hilo $lider "el reclamo '$($r.tarea)' de $($r.agente) lleva $([int]($ahora - $ult).TotalMinutes) min sin señal de vida" 'nada: sigue reclamado' `
      "que el líder lo suelte (mesa.ps1 soltar -Tarea $($r.tarea) -De <líder>) y lo reasigne si $($r.agente) no vuelve"
  }

  foreach ($a in $Global:Mesa_Agentes) {
    $previo = Mesa-LeerMensaje (Join-Path $dirAgentes "$a.json")
    if ($previo -and $previo.estado -ne $estado[$a].estado) { Bitacora "$a pasa de $($previo.estado) a $($estado[$a].estado)$(if ($estado[$a].motivo) { ": $($estado[$a].motivo)" })." }
    Mesa-EscribirJson (Join-Path $dirAgentes "$a.json") $estado[$a]
  }
  # Los avisos de más de 7 días se olvidan: la memoria no crece sin límite.
  foreach ($p in @($memoria.avisados.PSObject.Properties)) { if (($ahora - [datetime]::Parse($p.Value)).TotalDays -gt 7) { $memoria.avisados.PSObject.Properties.Remove($p.Name) } }
  Mesa-EscribirJson $rutaMemoria $memoria
  [IO.File]::WriteAllText($latSup, (Mesa-IsoNow))
  # Worktrees de la mesa para el tablero: git es lento, así que cada 5 min y no en cada vuelta del tablero.
  $wtJson = Join-Path $Global:Mesa_Raiz 'worktrees.json'
  if (-not (Test-Path -LiteralPath $wtJson) -or ((Get-Date) - (Get-Item -LiteralPath $wtJson).LastWriteTime).TotalMinutes -ge 5) {
    try { [IO.File]::WriteAllText($wtJson, [string](& "$PSScriptRoot\worktrees.ps1" lista -Json), (New-Object Text.UTF8Encoding $false)) } catch {}
  }
  Rotar 'actividad.jsonl' 5
  Rotar 'alertas.jsonl' 2
  Rotar 'errores-paneles.log' 1
}

try {
  while ($true) {
    try { Vuelta } catch { try { Mesa-AnexarLinea (Join-Path $Global:Mesa_Raiz 'errores-paneles.log') ("{0}`tsupervisor`t{1}" -f (Mesa-IsoNow), $_.Exception.Message) } catch {}; if ($UnaVez) { throw } }
    if ($UnaVez) { break }
    Start-Sleep -Seconds $Intervalo
  }
} finally { $unico.Dispose() }
