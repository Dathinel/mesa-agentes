param(
  [ValidateRange(1, 3600)][int]$Intervalo = 5,
  [switch]$UnaVez
)
. "$PSScriptRoot\comun.ps1"
$ErrorActionPreference = 'Stop'
$esc = [char]27
$colores = @{ DarkYellow = 33; Green = 92; Cyan = 96; Red = 91; Gray = 90 }

function Recortar($texto, [int]$ancho = 100) {
  $t = ([string]$texto -replace '[\x00-\x1f\x7f-\x9f]', ' ').TrimEnd()
  if ($t.Length -gt $ancho) { return $t.Substring(0, $ancho - 1) + '…' }
  return $t
}
function Linea($texto = '', $color = '') {
  $t = Recortar $texto
  if ($color) { $t = "$esc[$($colores[$color])m$t$esc[0m" }
  [void]$script:vista.AppendLine($t)
}
function Leer($ruta) {
  try { Mesa-LeerJson $ruta }
  catch { [void]$script:errores.Add("No se pudo leer $(Split-Path -Leaf $ruta)") }
}
function Fecha($valor) {
  try { if ($valor) { return [DateTimeOffset]::Parse([string]$valor) } } catch {}
  return [DateTimeOffset]::MinValue
}
function Antiguedad($valor) {
  $f = Fecha $valor
  if ($f -eq [DateTimeOffset]::MinValue) { return '?' }
  $s = [Math]::Max(0, [Math]::Floor(($script:ahora - $f).TotalSeconds))
  if ($s -lt 60) { return "hace $s s" }
  if ($s -lt 3600) { return ('hace {0} min' -f [Math]::Floor($s / 60)) }
  if ($s -lt 86400) { return ('hace {0} h' -f [Math]::Floor($s / 3600)) }
  return ('hace {0} días' -f [Math]::Floor($s / 86400))
}

do {
  $script:vista = New-Object System.Text.StringBuilder
  $script:errores = New-Object 'System.Collections.Generic.List[string]'
  $script:ahora = [DateTimeOffset]::Now
  try {
    $hilos = @(); $mensajes = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue)) {
      $h = Leer (Join-Path $dir.FullName 'hilo.json')
      if ($h) { $hilos += $h }
      foreach ($a in @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*.json' -ErrorAction SilentlyContinue)) {
        if ($a.Name -notmatch '^\d+-.*\.json$') { continue }
        $m = Leer $a.FullName
        if ($m) { $mensajes += [pscustomobject]@{ hilo = $dir.Name; mensaje = $m } }
      }
    }
    $reclamos = @(Mesa-Reclamos)
    $entregas = @(Mesa-Entregas -ConArchivadas)
    $cuota = Leer (Join-Path $Global:Mesa_Raiz 'cuota-estado.json')
    $wts = @(Leer (Join-Path $Global:Mesa_Raiz 'worktrees.json'))
    $topeWt = (Leer (Mesa-ConfigPath)).worktrees.max_por_agente
    Linea ('Mesa de agentes · {0:yyyy-MM-dd HH:mm:ss} · cada {1} s' -f $ahora, $Intervalo)
    $latSup = Join-Path $Global:Mesa_Raiz 'agentes\supervisor.latido'
    $edadSup = if (Test-Path -LiteralPath $latSup) { ($ahora - [DateTimeOffset](Get-Item -LiteralPath $latSup).LastWriteTime).TotalSeconds } else { -1 }
    $apr = Mesa-Aprobacion (Leer (Mesa-ConfigPath))
    if ($edadSup -lt 0 -or $edadSup -gt 90) { Linea ("Supervisor: PARADO $(if ($edadSup -ge 0) { '(último latido ' + (Antiguedad (Get-Item -LiteralPath $latSup).LastWriteTime.ToString('o')) + ')' }) · ábrelo con Mesa.bat") 'Red' }
    else { Linea ("Supervisor: vivo ({0}) · aprobación: {1} (sin esperar: {2})" -f (Antiguedad (Get-Item -LiteralPath $latSup).LastWriteTime.ToString('o')), $apr.modo, ($apr.tipos -join ', ')) 'Gray' }
    Linea 'Agentes'
    foreach ($agente in @('claude', 'codex', 'agy')) {
      $color = @{ claude = 'DarkYellow'; codex = 'Green'; agy = 'Cyan' }[$agente]
      $activo = Leer (Join-Path $Global:Mesa_Raiz "agentes\$agente.json")
      $latido = $activo.latido
      $estado = if ($activo.estado) { [string]$activo.estado } else { '?' }
      if (-not $activo) {
        $ruta = Join-Path $Global:Mesa_Raiz "trabajador-$agente.latido"
        try { if (Test-Path -LiteralPath $ruta) { $latido = [IO.File]::ReadAllText($ruta).Trim() } }
        catch { [void]$errores.Add("No se pudo leer trabajador-$agente.latido") }
      }
      $n = @($hilos | Where-Object {
        $_.estado -eq 'abierto' -and $_.lider -eq $agente -and
        (Fecha $_.actualizado) -ge $ahora.AddHours(-24)
      }).Count
      $rol = if ($n) { "líder de $n hilos" } else { 'agente' }
      $tarea = @($reclamos | Where-Object {
        $_.agente -eq $agente -and $_.tarea -ne 'lider' -and $_.tarea -notlike 'archivo-*'
      } | Sort-Object fecha -Descending | Select-Object -First 1)
      $nombreTarea = if ($tarea.Count) { Recortar $tarea[0].tarea 18 } else { '-' }
      $pct = switch ($agente) {
        'claude' { $cuota.claude.semanal_libre_pct_estimado }
        'codex' { if ($null -ne $cuota.codex.cinco_horas_usado_pct) { 100 - $cuota.codex.cinco_horas_usado_pct } }
        'agy' { $cuota.agy.grupos.flash.libre_pct_estimado }
      }
      $libre = if ($null -eq $pct) { '?' } else { '{0:0.#}%' -f [double]$pct }
      $susWt = @($wts | Where-Object { $_.agente -eq $agente })
      $txtWt = if ($susWt.Count) { " | wt $($susWt.Count)$(if ($topeWt) { "/$topeWt" })$(if (@($susWt | Where-Object { $_.sin_confirmar -gt 0 }).Count) { ' sucio' })" } else { '' }
      $texto = '{0,-6} | {1,-16} | {2,-14} | {3,-18} | {4,-12} | cuota {5}{6}' -f $agente, $rol, $estado, $nombreTarea, (Antiguedad $latido), $libre, $txtWt
      # El nombre conserva el color del agente incluso en estados de alarma.
      if ($estado -in @('colgado', 'caido', 'sin-cuota', 'necesita-login')) {
        $texto = Recortar $texto
        [void]$vista.AppendLine("$esc[$($colores[$color])m$($texto.Substring(0,6))$esc[91m$($texto.Substring(6))$esc[0m")
      } else { Linea $texto $color }
    }
    Linea
    Linea "Esperan a $($Global:Mesa_Humano)"
    $pendientes = @($mensajes | Where-Object { $_.mensaje.estado -eq 'pendiente' })
    if (-not $pendientes.Count) { Linea '  Ninguno.' }
    foreach ($p in $pendientes) {
      $m = $p.mensaje
      Linea ("  $($p.hilo) #$($m.n) $($m.autor) -> $($m.para)")
      Linea ('  ' + (Recortar $m.texto 80))
    }
    Linea
    Linea 'Tareas por estado'
    foreach ($estadoEntrega in @('entregada', 'devuelta', 'aceptada')) {
      $grupo = @($entregas | Where-Object { $_.estado -eq $estadoEntrega })
      Linea ("  ${estadoEntrega}: $($grupo.Count)")
      foreach ($e in $grupo) { Linea ("    $($e.hilo) / $($e.tarea) ($($e.autor))") }
    }
    Linea ('  archivada: ' + @($entregas | Where-Object { $_.estado -eq 'archivada' }).Count)
    $ejecutando = @($mensajes | Where-Object { $_.mensaje.tipo -eq 'encargo' -and $_.mensaje.estado -eq 'ejecutando' })
    Linea ("  ejecutando: $($ejecutando.Count)")
    foreach ($p in $ejecutando) {
      $m = $p.mensaje
      $inicio = if ($m.llamada.inicio) { $m.llamada.inicio } else { $m.fecha }
      Linea ("    $($p.hilo) #$($m.n) -> $($m.para) · $(Antiguedad $inicio)")
    }
    Linea
    Linea 'Alertas'
    $revisadas = Leer (Join-Path $Global:Mesa_Raiz 'alertas-revisadas.json')
    $alertas = @(); $ruta = Join-Path $Global:Mesa_Raiz 'alertas.jsonl'
    if (Test-Path -LiteralPath $ruta) {
      foreach ($l in [IO.File]::ReadLines($ruta, [Text.Encoding]::UTF8)) {
        if (-not $l.Trim()) { continue }
        try {
          $a = $l | ConvertFrom-Json -ErrorAction Stop
          if ((Fecha $a.hora) -ge $ahora.AddHours(-24) -and $a.id -notin @($revisadas.ids)) { $alertas += $a }
        } catch { [void]$errores.Add('No se pudo leer una línea de alertas.jsonl') }
      }
    }
    $ultimas = @($alertas | Sort-Object { Fecha $_.hora } -Descending | Select-Object -First 5)
    if (-not $ultimas.Count) { Linea '  Ninguna sin revisar en las últimas 24 h.' }
    foreach ($a in $ultimas) { Linea ("  $($a.hora) $($a.agente): $($a.motivo)") 'Red' }
  } catch { [void]$errores.Add('Error al actualizar: ' + $_.Exception.GetType().Name) }
  foreach ($errorLectura in @($errores | Select-Object -Unique)) { Linea $errorLectura 'Gray' }
  if (-not $UnaVez) { Clear-Host }
  Write-Host $vista.ToString() -NoNewline
  if (-not $UnaVez) { Start-Sleep -Seconds $Intervalo }
} while (-not $UnaVez)
