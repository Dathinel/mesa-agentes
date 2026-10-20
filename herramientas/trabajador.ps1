# Panel de un agente en la Mesa: ejecuta a la vista los encargos que delegar.ps1 -Visible deja en cola para él
# y, mientras espera, lo que escribe la persona se le envía como charla, continuando su última conversación.
# Uso: trabajador.ps1 -Agente codex|agy|claude [-Intervalo <s>]. Sin -Agente atiende la cola de todos (sin charla).
# Ctrl+C lo detiene; el encargo en curso queda en el hilo como «ejecutando».
param(
  [ValidateSet('codex','agy','claude')][string]$Agente,
  [int]$Intervalo = 3,
  [int]$RelevoMin = 15
)
. "$PSScriptRoot\comun.ps1"
$sufijo = if ($Agente) { "-$Agente" } else { '' }
$latido = Join-Path $Global:Mesa_Raiz "trabajador$sufijo.latido"
$archSesion = Join-Path $Global:Mesa_Raiz "sesion$sufijo.txt"
$Host.UI.RawUI.WindowTitle = if ($Agente) { $Agente } else { 'Encargos' }
$charla = "charla-$Agente"
$sesion = if ($Agente -and (Test-Path -LiteralPath $archSesion)) { ([IO.File]::ReadAllText($archSesion)).Trim() } else { $null }

function Siguiente-EnCola {
  $cola = foreach ($d in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue)) {
    foreach ($f in @(Get-ChildItem -LiteralPath $d.FullName -Filter '*-*.json' -ErrorAction SilentlyContinue)) {
      $m = try { Mesa-LeerJson $f.FullName } catch { $null }
      if ($m -and $m.tipo -eq 'encargo' -and $m.estado -eq 'aprobado' -and $m.PSObject.Properties['cola'] -and $m.cola -and (-not $Agente -or $m.herramienta -eq $Agente)) {
        [pscustomobject]@{ hilo = $d.Name; n = [int]$m.n; fecha = $m.fecha; para = $m.para; modelo = $m.modelo; texto = $m.texto }
      }
    }
  }
  @($cola | Sort-Object fecha) | Select-Object -First 1
}

# El id de conversación queda en el log: thread_id (codex), conversation_id (agy), session_id (claude).
function Sesion-DelMensaje($hilo, $n) {
  $m = Mesa-LeerJson (Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Hilos $hilo) -Filter ('{0:D4}-*.json' -f $n) | Select-Object -First 1).FullName
  if (-not $m.llamada.log -or -not (Test-Path -LiteralPath $m.llamada.log)) { return $null }
  $x = [regex]::Match([IO.File]::ReadAllText($m.llamada.log), '"(?:thread_id|conversation_id|session_id)"\s*:\s*"([^"]+)"')
  if ($x.Success) { $x.Groups[1].Value } else { $null }
}

function Correr($hilo, $n, [string]$conSesion) {
  # El latido sigue en otro proceso mientras el agente trabaja, para que delegar.ps1 vea el panel vivo.
  $pulso = Start-Job -ArgumentList $latido -ScriptBlock { param($r) while ($true) { try { [IO.File]::WriteAllText($r, (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')) } catch {}; Start-Sleep 5 } }
  $Host.UI.RawUI.WindowTitle = "$(if ($Agente) { $Agente } else { 'Encargos' }) · trabajando #$n"
  try {
    $p = @{ Hilo = $hilo; N = $n; Ver = $true }
    if ($conSesion) { $p['Sesion'] = $conSesion }
    & "$PSScriptRoot\ejecutar.ps1" @p
  } finally {
    Stop-Job $pulso -ErrorAction SilentlyContinue; Remove-Job $pulso -Force -ErrorAction SilentlyContinue
    $Host.UI.RawUI.WindowTitle = "$(if ($Agente) { $Agente } else { 'Encargos' }) · esperando"
  }
  if ($Agente) {
    $id = Sesion-DelMensaje $hilo $n
    if ($id) { $script:sesion = $id; [IO.File]::WriteAllText($archSesion, $id) }
  }
}

# Si un hilo espera al líder (entrega o bloqueo sin respuesta) y el líder lleva $RelevoMin sin actividad, este agente toma el liderazgo.
function Vigilar-Lideres {
  foreach ($d in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Where-Object Name -notlike 'charla-*')) {
    $h = Mesa-LeerJson (Join-Path $d.FullName 'hilo.json')
    $lider = if ($h) { Mesa-NormalizarHerramienta $h.lider }
    if (-not $h -or $h.estado -ne 'abierto' -or -not $lider -or $lider -eq $Agente) { continue }
    $msgs = @(Get-ChildItem -LiteralPath $d.FullName -Filter '*-*.json' | Sort-Object Name | ForEach-Object { Mesa-LeerMensaje $_.FullName } | Where-Object { $_ })
    $ultLider = (@($msgs | Where-Object { (Mesa-NormalizarHerramienta $_.autor) -eq $lider } | ForEach-Object { [int]$_.n }) + 0 | Measure-Object -Maximum).Maximum
    $espera = @($msgs | Where-Object { [int]$_.n -gt $ultLider -and $_.tipo -in @('entrega', 'avance-bloqueo') -and (Mesa-NormalizarHerramienta $_.autor) -ne $lider })
    if (-not $espera.Count) { continue }
    $ahora = Get-Date
    $edad = ($ahora - [datetime]::Parse($espera[0].fecha)).TotalMinutes
    # Más de un día esperando no es una operación en curso: es un hilo olvidado.
    if ($edad -lt $RelevoMin -or $edad -gt 1440 -or ($ahora - (Mesa-UltimaActividad $lider)).TotalMinutes -lt $RelevoMin) { continue }
    # Un solo relevo por hilo: gana el primer panel que crea el candado.
    $candado = Join-Path $Global:Mesa_Raiz "reclamos\relevo-$($d.Name).lock"
    try { [IO.File]::Open($candado, 'CreateNew', 'Write').Dispose() } catch { continue }
    $h2 = Join-Path $PSScriptRoot 'mesa.ps1'
    & $h2 lider -Hilo $d.Name -Nuevo $Agente -De $Agente | Out-Null
    $ruta = Join-Path $d.FullName "relevo-$Agente.md"
    [IO.File]::WriteAllText($ruta, @"
# Relevo de liderazgo: $($d.Name)

El líder $lider no responde: $($espera.Count) mensaje(s) esperándolo desde $($espera[0].fecha) y sin actividad en $RelevoMin min. Ahora el líder eres tú ($Agente).
1. ``mesa.ps1 leer -Hilo $($d.Name)`` y ``mesa.ps1 entregas``: entiende el objetivo, el reparto y lo que falta.
2. Atiende lo que esperaba: revisa las entregas (``revisar``; la tuya propia la revisa otro), resuelve los bloqueos y sigue el plan delegando con ``delegar.ps1 -Visible``.
3. Si $lider vuelve a escribir en el hilo, devuélvele el liderazgo con ``mesa.ps1 lider -Hilo $($d.Name) -Nuevo $lider -De $Agente`` y un traspaso de lo hecho.
4. Al terminar, borra ``$candado``.
"@, (New-Object System.Text.UTF8Encoding $false))
    & "$PSScriptRoot\delegar.ps1" -A $Agente -Encargo $ruta -Hilo $d.Name -De $Agente -Dir $Global:Mesa_Base -Tipo relevo -Visible | Out-Null
    Write-Host ("`n━━ {0} · RELEVO: {1} lidera {2} ({3} no responde)" -f (Get-Date -Format 'HH:mm'), $Agente, $d.Name, $lider) -ForegroundColor Red
  }
}

function Charlar([string]$texto) {
  $h = Join-Path $PSScriptRoot 'mesa.ps1'
  if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $Global:Mesa_Hilos $charla) 'hilo.json'))) {
    & $h abrir -Hilo $charla -Titulo "Charla de $($Global:Mesa_Humano) con $Agente" -Lider $Global:Mesa_Humano -Participantes "$($Global:Mesa_Humano),$Agente" | Out-Null
  }
  $salida = (& $h enviar -Hilo $charla -De $Global:Mesa_Humano -Para $Agente -Texto $texto | Select-Object -Last 1)
  if ($salida -notmatch '^(\d+)-') { Write-Host "No se pudo registrar el mensaje: $salida" -ForegroundColor Red; return }
  $n = [int]$Matches[1]
  & $h aprobar -Hilo $charla -N $n -NoLanzar -Motivo 'charla en el panel' | Out-Null
  Correr $charla $n $script:sesion
}

$aviso = if ($Agente) { "Panel de $Agente`: ejecuta sus encargos y, mientras espera, escribe aquí para hablarle (Enter envía). Ctrl+C para parar." } else { 'Encargos de la Mesa: esperando trabajo. Ctrl+C para parar.' }
Write-Host $aviso -ForegroundColor DarkGray
if ($sesion) { Write-Host "Conversación que continúa: $sesion" -ForegroundColor DarkGray }
$proxima = Get-Date
$proximoRelevo = Get-Date
while ($true) {
  # Nada de lo que falle en una vuelta (JSON corrupto, archivo bloqueado, error del agente) puede cerrar el panel.
  try {
    try { [IO.File]::WriteAllText($latido, (Mesa-IsoNow)) } catch {}
    if ($Agente -and [Console]::KeyAvailable) {
      $t = Read-Host "Tú → $Agente"
      if ($t.Trim()) {
        Write-Host ("`n━━ {0} · {2} → {1}" -f (Get-Date -Format 'HH:mm'), $Agente, $Global:Mesa_Humano) -ForegroundColor Magenta
        Charlar $t
        Write-Host "━━ fin · esperando" -ForegroundColor DarkGray
      }
    }
    if ($Agente -and (Get-Date) -ge $proximoRelevo) {
      $proximoRelevo = (Get-Date).AddMinutes(1)
      try { Vigilar-Lideres } catch { Write-Host "Relevo: $($_.Exception.Message)" -ForegroundColor DarkGray }
      # Quién vigila al supervisor: cada panel, una vez por caída.
      $latSup = Join-Path $Global:Mesa_Raiz 'agentes\supervisor.latido'
      $supParado = (Test-Path -LiteralPath $latSup) -and ((Get-Date) - (Get-Item -LiteralPath $latSup).LastWriteTime).TotalMinutes -gt 3
      if ($supParado -and -not $script:avisoSupervisor) { Write-Host ("`n━━ {0} · El supervisor no da señales desde hace más de 3 min: vuelve a abrir la mesa con Mesa.bat." -f (Get-Date -Format 'HH:mm')) -ForegroundColor Red }
      $script:avisoSupervisor = $supParado
    }
    if ((Get-Date) -ge $proxima) {
      $proxima = (Get-Date).AddSeconds($Intervalo)
      $sig = Siguiente-EnCola
      if ($sig) {
        Write-Host ("`n━━ {0} · {1} ({2}) · {3} #{4}" -f (Get-Date -Format 'HH:mm'), $sig.para, $sig.modelo, $sig.hilo, $sig.n) -ForegroundColor Yellow
        Write-Host "   $($sig.texto)" -ForegroundColor DarkYellow
        Correr $sig.hilo $sig.n $null
        Write-Host "━━ fin #$($sig.n) · esperando" -ForegroundColor DarkGray
      }
    }
  } catch {
    Write-Host ("`n━━ {0} · error, el panel sigue: {1}" -f (Get-Date -Format 'HH:mm'), $_.Exception.Message) -ForegroundColor Red
    try { Mesa-AnexarLinea (Join-Path $Global:Mesa_Raiz 'errores-paneles.log') ("{0}`t{1}`t{2}" -f (Mesa-IsoNow), $Agente, $_.Exception.Message) } catch {}
    Start-Sleep -Seconds 2
  }
  Start-Sleep -Milliseconds 200
}
