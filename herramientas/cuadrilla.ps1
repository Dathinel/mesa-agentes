# Cuadrilla ligera: una orden que lanza un encargo a codex o agy, espera y termina. Sin procesos residentes.
#   cuadrilla.ps1 delegar -A codex|agy -Encargo <md> -Dir <carpeta> [-Tarea t] [-Modelo m] [-Esfuerzo low|medium|high] [-Lectura] [-Red] [-Minutos n]
#   cuadrilla.ps1 estado [<id>]        cuadrilla.ps1 cortar <id>        cuadrilla.ps1 cuota
# Salidas de delegar: 0 hecho, 2 hecho con aviso, 1 fallo, 124 tiempo o colgado, 3 no lanzado.
param(
  [Parameter(Position = 0, Mandatory = $true)][ValidateSet('delegar', 'estado', 'cortar', 'cuota')][string]$Comando,
  [Parameter(Position = 1)][string]$Id,
  [ValidateSet('codex', 'agy')][string]$A,
  [string]$Encargo, [string]$Dir, [string]$Tarea, [string]$Modelo,
  [ValidateSet('low', 'medium', 'high')][string]$Esfuerzo = 'medium',
  [switch]$Lectura, [switch]$Red, [double]$Minutos = 0
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
$trabajos = Join-Path $Global:Mesa_Raiz 'trabajos'
New-Item -ItemType Directory -Force $trabajos | Out-Null
$cfg = Mesa-LeerJson (Mesa-ConfigPath)
$utf8 = New-Object Text.UTF8Encoding $false

function Ruta-Cli($a) {
  $c = Get-Command $a -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($c) { return $c.Source }
  $exe = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
  if ($a -eq 'agy' -and (Test-Path -LiteralPath $exe)) { return $exe }
}
function Resultados {
  @(Get-ChildItem -LiteralPath $trabajos -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $f = Join-Path $_.FullName 'resultado.json'
    if (Test-Path -LiteralPath $f) { try { Mesa-LeerJson $f } catch {} }
  } | Sort-Object inicio)
}
# Un ejecutando cuyo lanzador ya no vive (apagón, app cerrada) pasa a interrumpido; la misma orden lo retoma.
function Refrescar-Interrumpidos {
  foreach ($r in Resultados) {
    if ($r.estado -eq 'ejecutando' -and -not (Mesa-ProcesoVivo $r.lanzador.pid $r.lanzador.inicio $r.lanzador.nombre)) {
      $r.estado = 'interrumpido'; $r.fin = Mesa-IsoNow; Mesa-EscribirJson (Join-Path $trabajos "$($r.id)\resultado.json") $r
    }
  }
}
# Continue solo aquí: en PowerShell 5.1 el stderr de git, aunque vaya a $null, se volvería una excepción con Stop.
function Orden-Git($d) { $ErrorActionPreference = 'Continue'; $s = & git -C $d @args 2>$null; if ($LASTEXITCODE -eq 0) { @($s) -join "`n" } }
function Raiz-Repo($d) { $r = Orden-Git $d rev-parse --show-toplevel; if ($r) { [IO.Path]::GetFullPath($r) } }
function Hora($iso) { ([datetime]::Parse($iso)).ToString('HH:mm') }

switch ($Comando) {
  'estado' {
    Refrescar-Interrumpidos
    $todos = Resultados
    if ($Id) { $r = $todos | Where-Object id -eq $Id; if (-not $r) { throw "No existe el encargo $Id." }; $r | ConvertTo-Json -Depth 6; return }
    foreach ($a in 'codex', 'agy') {
      $mios = @($todos | Where-Object agente -eq $a)
      $vivo = $mios | Where-Object estado -eq 'ejecutando' | Select-Object -Last 1
      $ultimo = $mios | Select-Object -Last 1
      $linea = if (-not (Ruta-Cli $a)) { 'no instalado' }
        elseif ($vivo) {
          $log = Join-Path $trabajos "$($vivo.id)\log.jsonl"
          $edad = if (Test-Path -LiteralPath $log) { [int]((Get-Date) - (Get-Item -LiteralPath $log).LastWriteTime).TotalMinutes } else { '?' }
          "ocupado $($vivo.id) ($([int]((Get-Date) - [datetime]::Parse($vivo.inicio)).TotalMinutes) min; log hace $edad min)"
        } elseif ($ultimo.causa -eq 'sin-cuota' -and $ultimo.hasta -and [datetime]::Parse($ultimo.hasta) -gt (Get-Date)) { "sin cuota hasta $(Hora $ultimo.hasta)" }
        else { 'libre' }
      "{0,-6} {1}" -f $a, $linea
    }
    foreach ($r in @($todos | Select-Object -Last 10)) {
      "{0}  {1,-13} salida={2} {3} {4}" -f $r.id, $r.estado, $r.salida, $(if ($r.causa) { "causa=$($r.causa)" } else { '' }), $(if ($r.avisos) { "avisos=$(@($r.avisos).Count)" } else { '' })
    }
    $plantilla = Join-Path $Global:Mesa_Base 'plantillas\cuadrilla\SKILL.md'
    $instalada = Join-Path $env:USERPROFILE '.claude\skills\cuadrilla\SKILL.md'
    if (-not (Test-Path -LiteralPath $instalada) -or (Get-FileHash $plantilla).Hash -ne (Get-FileHash $instalada).Hash) { 'AVISO: la skill instalada no coincide con plantillas\cuadrilla\SKILL.md: ejecuta herramientas\instalar.ps1' }
    return
  }
  'cortar' {
    if (-not $Id) { throw 'Uso: cuadrilla.ps1 cortar <id>' }
    $f = Join-Path $trabajos "$Id\resultado.json"
    $r = Mesa-LeerJson $f
    if (-not $r) { throw "No existe el encargo $Id." }
    if ($r.estado -ne 'ejecutando') { "No se corta nada: $Id está $($r.estado)."; return }
    if (-not (Mesa-ProcesoVivo $r.lanzador.pid $r.lanzador.inicio $r.lanzador.nombre)) { Refrescar-Interrumpidos; "No se corta nada: el lanzador de $Id ya no vive (queda interrumpido)."; return }
    # Matar al lanzador cierra su Job y el Job se lleva el árbol del CLI (KILL_ON_JOB_CLOSE).
    Stop-Process -Id $r.lanzador.pid -Force
    $r.estado = 'interrumpido'; $r.causa = 'cortado'; $r.fin = Mesa-IsoNow; Mesa-EscribirJson $f $r
    "CORTADO $Id"
    return
  }
  'cuota' {
    foreach ($a in 'codex', 'agy') {
      $u = Resultados | Where-Object { $_.agente -eq $a -and $_.causa -eq 'sin-cuota' } | Select-Object -Last 1
      if ($u) { "$a`: última señal sin cuota $($u.fin) (hasta $($u.hasta))" } else { "$a`: sin señal de falta de cuota" }
    }
    $agy = Ruta-Cli 'agy'
    if (-not $agy) { 'agy: no instalado'; return }
    . "$PSScriptRoot\proceso.ps1"
    $log = Join-Path $trabajos 'cuota-agy.txt'
    $r = Invocar-ProcesoMesa -Ejecutable $agy -Argumentos @('-p', '/usage', '--output-format', 'text') -Directorio $Global:Mesa_Base -Log $log -Segundos 90
    if ($r.salida -ne 0) { "agy -p /usage salió con $($r.salida)" }
    Mesa-Ocultar ([IO.File]::ReadAllText($log, $utf8))
    return
  }
}

# ---- delegar ----
$reloj = [Diagnostics.Stopwatch]::StartNew()
function NoLanzado($motivo) { Write-Output "NO LANZADO: $motivo"; exit 3 }
if (-not $A -or -not $Encargo -or -not $Dir) { NoLanzado 'faltan -A, -Encargo o -Dir' }
foreach ($p in $Encargo, $Dir) { if ($p -match '[$(`]') { NoLanzado "la ruta lleva `$, ( o acento grave: $p" } }
if (-not (Test-Path -LiteralPath $Encargo -PathType Leaf)) { NoLanzado "no existe el encargo $Encargo" }
if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { NoLanzado "no existe la carpeta $Dir" }
$Encargo = (Resolve-Path -LiteralPath $Encargo).Path; $Dir = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
foreach ($p in $Encargo, $Dir) { if ($p -match $Global:Mesa_Excluidos) { NoLanzado 'ruta excluida (datos\excluidos.txt)' } }
$cli = Ruta-Cli $A
if (-not $cli) { NoLanzado "$A no está en el PATH" }
if (-not $Modelo) { $Modelo = Mesa-ModeloPorDefecto $A $cfg }
if ($Modelo -notin @($cfg.modelos.$A)) { NoLanzado "modelo $Modelo no está en mesa.json (modelos.$A)" }
$repo = Raiz-Repo $Dir
if (-not $repo -and -not $Lectura) {
  $hijos = @(Get-ChildItem -LiteralPath $Dir -Directory -Depth 1 -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') })
  if ($hijos.Count) { NoLanzado "$Dir contiene repositorios sin ser uno: pide -Lectura o apunta a un repo" }
}
if (-not $Tarea) {
  $Tarea = [IO.Path]::GetFileNameWithoutExtension($Encargo).ToLowerInvariant() -replace '^encargo-', '' -replace "^$A-", '' -replace "-$A$", ''
}
if ($Tarea -notmatch '^[a-z0-9][a-z0-9-]*$') { NoLanzado "tarea «$Tarea»: solo minúsculas, cifras y guiones (usa -Tarea)" }
$hash = (Get-FileHash -LiteralPath $Encargo -Algorithm SHA256).Hash
Refrescar-Interrumpidos
$previos = @(Resultados | Where-Object agente -eq $A)
$ultimo = $previos | Select-Object -Last 1
if ($ultimo.causa -eq 'sin-cuota' -and $ultimo.hasta -and [datetime]::Parse($ultimo.hasta) -gt (Get-Date)) { NoLanzado "$A sin cuota hasta $(Hora $ultimo.hasta)" }
$vivo = $previos | Where-Object estado -eq 'ejecutando' | Select-Object -Last 1
if ($vivo -and $vivo.tarea -eq $Tarea) { NoLanzado "la tarea $Tarea ya está viva ($($vivo.id))" }
$hecho = $previos | Where-Object { $_.estado -eq 'hecho' -and $_.tarea -eq $Tarea -and $_.encargo_hash -eq $hash } | Select-Object -Last 1
if ($hecho) { NoLanzado "ese .md ya se hizo ($($hecho.id)); escribe una corrección y relanza con -Tarea $Tarea" }
# Candado: uno a la vez por CLI (el 24-oct, tres codex en paralelo agotaron la cuota). Windows lo suelta si el proceso muere.
try { $candado = [IO.File]::Open((Join-Path $trabajos "$A.lock"), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { NoLanzado "$A ocupado$(if ($vivo) { " ($($vivo.id))" })" }
$anterior = $previos | Where-Object { $_.tarea -eq $Tarea -and $_.estado -in @('fallo', 'interrumpido') } | Select-Object -Last 1
$id = "$A-$Tarea-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
$carpeta = Join-Path $trabajos $id
$wt = $null; $rama = $null
if ($repo -and -not $Lectura) {
  # Si el worktree falla no se lanza (antes caía al checkout principal con un aviso). Si ya existe, se reutiliza.
  try { $wt = @(& "$PSScriptRoot\worktrees.ps1" crear -Dir $repo -Agente $A -Tarea $Tarea 2>&1 | ForEach-Object { "$_" }) | Select-Object -Last 1 } catch { $wt = $_.Exception.Message }
  if (-not $wt -or -not (Test-Path -LiteralPath $wt)) { $candado.Dispose(); NoLanzado "no se pudo crear el worktree: $wt" }
  $rama = "$A/$Tarea"
}
$trabajo = if ($wt) { $wt } else { $Dir }
New-Item -ItemType Directory -Force $carpeta | Out-Null
Copy-Item -LiteralPath $Encargo -Destination (Join-Path $carpeta 'encargo.md')
$texto = [IO.File]::ReadAllText($Encargo, [Text.Encoding]::UTF8)
if ($wt) {
  # Las rutas del repo que existen en el worktree se cambian a él; lo no versionado (.entorno) sigue en el original.
  $texto = [regex]::Replace($texto, [regex]::Escape($repo) + '[\\/][^\s"''`<>)\]]*', {
    param($m); $rel = $m.Value.Substring($repo.Length + 1); $cand = Join-Path $wt $rel
    if (Test-Path -LiteralPath $cand) { $cand } else { $m.Value }
  }, 'IgnoreCase')
}
$cabecera = if ($wt) { "Trabajas en $wt (rama $rama). Solo cambias archivos ahí. No haces commit, push, merge, rebase ni cambias de rama: Claude revisa y confirma." }
  elseif ($Lectura) { "Trabajas en $trabajo en modo de solo lectura: no modificas nada." }
  else { "Trabajas en $trabajo. Solo cambias archivos ahí." }
$cabecera += " No abres programas con interfaz ni dejas procesos en segundo plano. Si algo te bloquea, para y dilo. Termina con: Hecho / Archivos tocados / Cómo lo probaste / Pendiente."
if ($anterior) { $cabecera += "`nREINTENTO: el intento $($anterior.id) terminó $($anterior.estado); log $(Join-Path $trabajos "$($anterior.id)\log.jsonl"); mira git status y no repitas lo hecho." }
$prompt = "$cabecera`n`n$texto"
$promptTxt = Join-Path $carpeta 'prompt.txt'; $log = Join-Path $carpeta 'log.jsonl'; $final = Join-Path $carpeta 'final.txt'
[IO.File]::WriteAllText($promptTxt, $prompt, $utf8)

$limite = if ($Minutos -gt 0) { $Minutos } elseif ($cfg.limites.encargo_min) { [double]$cfg.limites.encargo_min } else { 90 }
$inactivo = if ($cfg.limites.inactivo_min) { [double]$cfg.limites.inactivo_min } else { 20 }
$hooks = Join-Path $PSScriptRoot 'git-bloqueo'
# Bloqueo de refs y de push solo en el entorno del CLI: no toca la configuración del repo.
$gitPares = @(@('core.hooksPath', $hooks), @('url.cuadrilla-sin-push://.pushInsteadOf', 'https://'), @('url.cuadrilla-sin-push://.pushInsteadOf', 'git@'), @('url.cuadrilla-sin-push://.pushInsteadOf', 'ssh://'))
switch ($A) {
  'codex' {
    $argumentos = @('exec', '--skip-git-repo-check', '-C', $trabajo, '-s', $(if ($Lectura) { 'read-only' } else { 'workspace-write' }))
    if ($repo -and (Test-Path -LiteralPath (Join-Path $repo '.entorno'))) { $argumentos += @('--add-dir', (Join-Path $repo '.entorno')) }
    if ($Red) { $argumentos += @('-c', 'sandbox_workspace_write.network_access=true') }
    # Codex quita del entorno de sus órdenes las variables con KEY en el nombre: las GIT_CONFIG_KEY_n se le pasan aparte.
    for ($i = 0; $i -lt $gitPares.Count; $i++) { $argumentos += @('-c', "shell_environment_policy.set.GIT_CONFIG_KEY_$i=`"$($gitPares[$i][0])`"") }
    $argumentos += @('--json', '-m', $Modelo, '-c', "model_reasoning_effort=`"$Esfuerzo`"", '-o', $final, '-')
    $entrada = $prompt
  }
  'agy' {
    $argumentos = @('-p', "Lee el encargo completo en el archivo UTF-8 $promptTxt y ejecuta sus instrucciones.", '--model', $Modelo, '--mode', $(if ($Lectura) { 'plan' } else { 'accept-edits' }), '--output-format', 'stream-json')
    $entrada = ''
  }
}
$yo = Get-Process -Id $PID
$resultado = [ordered]@{
  id = $id; agente = $A; tarea = $Tarea; modelo = $Modelo; esfuerzo = $Esfuerzo; dir = $Dir; worktree = $wt; rama = $rama; lectura = [bool]$Lectura
  encargo = $Encargo; encargo_hash = $hash; estado = 'ejecutando'; inicio = Mesa-IsoNow; fin = $null; salida = $null; causa = $null; hasta = $null
  lanzador = @{ pid = $PID; inicio = $yo.StartTime.ToUniversalTime().ToString('o'); nombre = $yo.ProcessName }; cli = $null
  tokens = $null; avisos = @(); cambios = $null; respuesta = $null; cpu_lanzador_s = $null
}
$rutaResultado = Join-Path $carpeta 'resultado.json'
Mesa-EscribirJson $rutaResultado $resultado
$antes = @{ head = $(if ($wt) { Orden-Git $wt rev-parse HEAD }); origen = $(if ($wt) { Orden-Git $wt rev-parse "refs/remotes/origin/$rama" }); principal = $(if ($repo) { Orden-Git $repo status --porcelain }) }
. "$PSScriptRoot\proceso.ps1"
try {
  for ($i = 0; $i -lt $gitPares.Count; $i++) { Set-Item "env:GIT_CONFIG_KEY_$i" $gitPares[$i][0]; Set-Item "env:GIT_CONFIG_VALUE_$i" $gitPares[$i][1] }
  $env:GIT_CONFIG_COUNT = $gitPares.Count
  $r = Invocar-ProcesoMesa -Ejecutable $cli -Argumentos $argumentos -Entrada $entrada -Directorio $trabajo -Log $log -Segundos ($limite * 60) -Inactivo ($inactivo * 60) -AlIniciar {
    param($identidad); $resultado.cli = $identidad; Mesa-EscribirJson $rutaResultado $resultado; $true
  }
} finally {
  $env:GIT_CONFIG_COUNT = $null
  for ($i = 0; $i -lt $gitPares.Count; $i++) { Remove-Item "env:GIT_CONFIG_KEY_$i", "env:GIT_CONFIG_VALUE_$i" -ErrorAction SilentlyContinue }
}

# Recoger: texto, tokens y causa salen del propio log del CLI; nunca de transcritos de sesión.
$eventos = @(); $texto = ''; $tokens = $null; $evFinal = $null; $agyStatus = $null
if (Test-Path -LiteralPath $log) {
  foreach ($l in [IO.File]::ReadLines($log, [Text.Encoding]::UTF8)) { if ($l.Trim().StartsWith('{')) { try { $eventos += ($l | ConvertFrom-Json -ErrorAction Stop) } catch {} } }
}
if ($A -eq 'codex') {
  if (Test-Path -LiteralPath $final) { $texto = [IO.File]::ReadAllText($final, [Text.Encoding]::UTF8).Trim() }
  foreach ($ev in $eventos) {
    if ($ev.type -eq 'item.completed' -and $ev.item.type -eq 'agent_message' -and -not (Test-Path -LiteralPath $final)) { $texto = [string]$ev.item.text }
    if ($ev.type -eq 'turn.completed' -and $ev.usage) { $u = $ev.usage; $tokens = @{ entrada = [int64]$u.input_tokens + [int64]$u.cached_input_tokens; salida = [int64]$u.output_tokens } }
    if ($ev.type -in @('turn.failed', 'error', 'turn.completed')) { $evFinal = $ev }
  }
} else {
  $ev = $eventos | Where-Object { $_.event -eq 'result' -or $_.type -eq 'result' -or $_.status } | Select-Object -Last 1
  if ($ev) {
    $evFinal = $ev; $res = if ($ev.result -and $ev.result -isnot [string]) { $ev.result } else { $ev }
    $agyStatus = $res.status
    $texto = if ($res.response -is [string]) { $res.response } elseif ($ev.result -is [string]) { $ev.result } else { '' }
    if ($res.usage) { $u = $res.usage; $tokens = @{ entrada = [int64]$u.input_tokens; salida = [int64]$u.output_tokens; total = [int64]$u.total_tokens } }
  }
}
if ($tokens -and -not $tokens.total) { $tokens.total = $tokens.entrada + $tokens.salida }
$causa = $r.causa; $hasta = $null; $avisos = @(); $fallo = $false
if (-not $causa -and $evFinal) { $f = Mesa-CausaFallo ($evFinal | ConvertTo-Json -Depth 20 -Compress); if ($f) { $causa = $f.causa; $hasta = $f.hasta; $fallo = $true } }
$estado = if ($r.salida -eq 124) { $causa } elseif ($r.salida -ne 0 -or $fallo) { 'fallo' } else { 'hecho' }
if ($A -eq 'agy' -and $estado -eq 'fallo' -and $agyStatus -eq 'ERROR' -and $texto -and $causa -notin @('sin-cuota', 'necesita-login')) {
  # #107 y #129: agy marcó ERROR habiendo entregado la respuesta.
  $estado = 'hecho'; $avisos += "agy terminó con status ERROR pero entregó respuesta$(if ($causa) { " (causa $causa)" })"; $causa = $null
}
if ($estado -eq 'hecho' -and -not $texto) { $avisos += 'respuesta vacía' }
$cambios = $null
if ($wt) {
  $cambios = @{ status = Orden-Git $wt status --short; diff = Orden-Git $wt diff --stat }
  if ((Orden-Git $wt rev-parse HEAD) -ne $antes.head) { $avisos += 'HEAD del worktree se movió' }
  if ((Orden-Git $wt rev-parse "refs/remotes/origin/$rama") -ne $antes.origen) { $avisos += "cambió refs/remotes/origin/$rama" }
}
if ($repo -and (Orden-Git $repo status --porcelain) -ne $antes.principal) { $avisos += "cambió el status de $(if ($Lectura) { 'la carpeta' } else { 'el checkout principal' })" }
if (-not $texto) { $texto = "(sin texto de salida; log en $log)" }
if ($texto.Length -gt 3000) { $texto = '…' + $texto.Substring($texto.Length - 3000) }
$texto = Mesa-Ocultar $texto
$resultado.estado = $estado; $resultado.fin = Mesa-IsoNow; $resultado.causa = $causa; $resultado.hasta = $hasta; $resultado.tokens = $tokens
$resultado.avisos = $avisos; $resultado.cambios = $cambios; $resultado.respuesta = $texto
$resultado.cpu_lanzador_s = [Math]::Round((Get-Process -Id $PID).TotalProcessorTime.TotalSeconds, 2)
$codigo = if ($estado -eq 'hecho') { $(if ($avisos.Count) { 2 } else { 0 }) } elseif ($r.salida -eq 124) { 124 } else { 1 }
$resultado.salida = $codigo
Mesa-EscribirJson $rutaResultado $resultado
$candado.Dispose()
"$id $estado salida=$codigo$(if ($causa) { " causa=$causa" })$(if ($hasta) { " hasta=$(Hora $hasta)" }) $([int]$reloj.Elapsed.TotalSeconds) s tokens=$(if ($tokens) { $tokens.total } else { '?' })$(if ($avisos.Count) { " AVISOS: $($avisos -join '; ')" })"
$rutaResultado
$texto
exit $codigo
