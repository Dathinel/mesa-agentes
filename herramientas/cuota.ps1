# Calcula y escribe datos\cuota-estado.json y muestra tabla de cuotas y uso.
# Solo para Claude, Codex y Antigravity (agy).
# Uso: cuota.ps1 [-Json] [-MesaJson <ruta>]
param(
  [switch]$Json,
  [string]$MesaJson,
  [switch]$Forzar
)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\comun.ps1"
. "$PSScriptRoot\costes.ps1"

function Invoke-CuotaCommand([string]$Nombre, [string]$Argumentos, [int]$TimeoutSegundos = 30) {
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = $Nombre
  $psi.Arguments = $Argumentos
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = New-Object Diagnostics.Process
  $p.StartInfo = $psi
  if (-not $p.Start()) { throw "No se pudo iniciar $Nombre" }
  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()
  if (-not $p.WaitForExit($TimeoutSegundos * 1000)) {
    try { $p.Kill() } catch {}
    throw "Timeout de $TimeoutSegundos s: $Nombre"
  }
  $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "$Nombre terminó con código $($p.ExitCode): $($errTask.Result)" }
  return $outTask.Result
}

function Convert-CuotaClaudeReset([string]$Fecha, [DateTime]$Base) {
  $culture = [Globalization.CultureInfo]::GetCultureInfo('en-US')
  foreach ($fmt in @('MMM d, h:mmtt','MMM d, h:mm tt','MMM d, htt','MMM d, h tt')) {
    try {
      $parsed = [DateTime]::ParseExact($Fecha.Trim(), $fmt, $culture, [Globalization.DateTimeStyles]::AllowWhiteSpaces)
      $dt = New-Object DateTime($Base.Year, $parsed.Month, $parsed.Day, $parsed.Hour, $parsed.Minute, 0)
      if ($dt -lt $Base.AddDays(-180)) { $dt = $dt.AddYears(1) }
      return ([DateTimeOffset]::new($dt, [TimeSpan]::FromHours(-5))).ToString('yyyy-MM-ddTHH:mm:sszzz')
    } catch {}
  }
  throw "Fecha de reinicio no reconocida: $Fecha"
}

$cuotaEstadoPrevio = Mesa-LeerJson $Global:Mesa_CuotaEstado

$ahora = Get-Date
$ahoraIso = Mesa-IsoNow
$cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)

# 1. Codex: última línea con rate_limits del JSONL más reciente en ~/.codex/sessions
$codex5hPct = $null
$codex5hIso = $null
$codexSemPct = $null
$codexSemIso = $null
$codexDir = Join-Path $env:USERPROFILE '.codex\sessions'
if (Test-Path -LiteralPath $codexDir) {
  $archivosCodex = @(Mesa-Sesiones 'codex' | Select-Object -First 24)
  foreach ($f in $archivosCodex) {
    $ultimaLinea = $null
    foreach ($l in (Mesa-Cola $f.FullName).lineas) {
      if ($l -match '"rate_limits"') { $ultimaLinea = $l }
    }
    if ($ultimaLinea) {
      try {
        $obj = $ultimaLinea | ConvertFrom-Json
        $rl = if ($obj.payload -and $obj.payload.rate_limits) { $obj.payload.rate_limits } elseif ($obj.rate_limits) { $obj.rate_limits } else { $null }
        if ($rl) {
          $codexObservado=$obj.timestamp
          if ($rl.primary) {
            $codex5hPct = [double]$rl.primary.used_percent
            if ($rl.primary.resets_at) {
              $codex5hIso = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rl.primary.resets_at).ToLocalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')
            }
          }
          if ($rl.secondary) {
            $codexSemPct = [double]$rl.secondary.used_percent
            if ($rl.secondary.resets_at) {
              $codexSemIso = [DateTimeOffset]::FromUnixTimeSeconds([int64]$rl.secondary.resets_at).ToLocalTime().ToString('yyyy-MM-ddTHH:mm:sszzz')
            }
          }
          break
        }
      } catch {}
    }
  }
}
# La ventana de 5h y semanal se recuperan si ya pasó su reinicio (requisito 4b y 4c)
$codex5hTrasReinicio = $false
if ($codex5hIso -and ([DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($codex5hIso))) {
  $codex5hPct = 0.0
  $codex5hTrasReinicio = $true
}
$codexSemTrasReinicio = $false
if ($codexSemIso -and ([DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($codexSemIso))) {
  $codexSemPct = 0.0
  $codexSemTrasReinicio = $true
}

# 2. Cargar fotos de datos\cuota-fotos.jsonl
$fotosPorGrupo = @{
  flash      = New-Object System.Collections.Generic.List[object]
  argon      = New-Object System.Collections.Generic.List[object]
  claude_gpt = New-Object System.Collections.Generic.List[object]
  claude     = New-Object System.Collections.Generic.List[object]
}
if (Test-Path -LiteralPath $Global:Mesa_CuotaFotos) {
  foreach ($l in [System.IO.File]::ReadLines($Global:Mesa_CuotaFotos, [System.Text.Encoding]::UTF8)) {
    if (-not $l.Trim()) { continue }
    try {
      $fo = $l | ConvertFrom-Json
      $g = $fo.grupo
      if ($g -and $fotosPorGrupo.ContainsKey($g)) {
        $fotosPorGrupo[$g].Add($fo)
      }
    } catch {}
  }
}

# 3. Claude: suma message.usage en últimas 5 h y 7 días, y estima desde la última foto
$tokensHoy = [int64]0
$tokens5h = [int64]0
$tokens7d = [int64]0
$tokensDesdeFoto = [int64]0
$cacheReadHoy = [int64]0
$cacheRead5h = [int64]0
$cacheRead7d = [int64]0
$hace7dLocal = $ahora.AddDays(-7)
$cut7dUtc = $ahora.ToUniversalTime().AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ss')
$cut5hUtc = $ahora.ToUniversalTime().AddHours(-5).ToString('yyyy-MM-ddTHH:mm:ss')
$cutHoyUtc = $ahora.Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')

$claudeFoto = if ($fotosPorGrupo['claude'].Count -gt 0) { $fotosPorGrupo['claude'][-1] } else { $null }
$claudeReiniciaSem = if ($claudeFoto -and $claudeFoto.reinicia_semanal) { [string]$claudeFoto.reinicia_semanal } else { $null }
$claudeReiniciaSemDt = if ($claudeReiniciaSem) { try { [DateTimeOffset]::Parse($claudeReiniciaSem) } catch { $null } } else { $null }
$claudeSemReinicioPasado = ($claudeReiniciaSemDt -and ([DateTimeOffset]::Now -ge $claudeReiniciaSemDt))

$claudeReinicia5h = if ($claudeFoto -and $claudeFoto.reinicia_5h) { [string]$claudeFoto.reinicia_5h } else { $null }
$claudeReinicia5hDt = if ($claudeReinicia5h) { try { [DateTimeOffset]::Parse($claudeReinicia5h) } catch { $null } } else { $null }
$claude5hReinicioPasado = ($claudeReinicia5hDt -and ([DateTimeOffset]::Now -ge $claudeReinicia5hDt))

$claudeFotoUsado = if ($claudeSemReinicioPasado) {
  0.0
} elseif ($claudeFoto) {
  if ($claudeFoto.semanal_usado_pct -ne $null) { [double]$claudeFoto.semanal_usado_pct }
  else { [Math]::Round(100.0 - [double]$claudeFoto.semanal_libre_pct, 2) }
} elseif ($cfg -and $cfg.cuota_manual) {
  [double]$cfg.cuota_manual.claude_semanal_usado_pct
} else { 93.0 }

$claudeFotoFecha = if ($claudeFoto -and $claudeFoto.fecha) { [string]$claudeFoto.fecha } elseif ($cfg -and $cfg.cuota_manual) { [string]$cfg.cuota_manual.fecha } else { $ahoraIso }
$claudeFotoUtc = if ($claudeSemReinicioPasado) {
  $claudeReiniciaSemDt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
} else {
  try { ([DateTimeOffset]::Parse($claudeFotoFecha)).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') } catch { $cut7dUtc }
}
$cut5hClaudeUtc = if ($claude5hReinicioPasado) {
  $claudeReinicia5hDt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
} else {
  $cut5hUtc
}

$claudeDir = Join-Path $env:USERPROFILE '.claude\projects'
if (Test-Path -LiteralPath $claudeDir) {
  $archivosClaude = @(Mesa-Sesiones 'claude' | Where-Object { $_.LastWriteTime -ge $hace7dLocal })
  foreach ($f in $archivosClaude) {
    $lote = New-Object System.Collections.Generic.List[string]
    foreach ($linea in (Mesa-Cola $f.FullName).lineas) {
      if ($linea -match '"usage"\s*:\s*\{' -and $linea -match '"timestamp"\s*:\s*"([^"]+)"') {
        $ts = $Matches[1]
        if ($ts -lt $cut7dUtc) { continue }
        if ($linea -match '"usage"\s*:\s*\{([^{}]*)') {
          $uProps = ($Matches[1] -replace ',\s*"[^"]+"\s*:\s*$', '').TrimEnd(',')
          $lote.Add(('{"timestamp":"' + $ts + '","message":{"usage":{' + $uProps + '}}}'))
        } else {
          $lote.Add($linea)
        }
      }
    }
    for ($i = 0; $i -lt $lote.Count; $i += 500) {
      $fin = [Math]::Min($i + 499, $lote.Count - 1)
      try {
        $items = ("[" + ($lote.GetRange($i, $fin - $i + 1) -join ",") + "]") | ConvertFrom-Json
        foreach ($it in $items) {
          $u = $it.message.usage
          if ($u -and $it.timestamp -ge $cut7dUtc) {
            $suma = [int64]$u.input_tokens + [int64]$u.output_tokens + [int64]$u.cache_creation_input_tokens
            $cread = [int64]$u.cache_read_input_tokens
            $tokens7d += $suma
            $cacheRead7d += $cread
            if ($it.timestamp -ge $cut5hClaudeUtc) {
              $tokens5h += $suma
              $cacheRead5h += $cread
            }
            if ($it.timestamp -ge $cutHoyUtc) {
              $tokensHoy += $suma
              $cacheReadHoy += $cread
            }
            if ($it.timestamp -ge $claudeFotoUtc) {
              $tokensDesdeFoto += $suma
            }
          }
        }
      } catch {}
    }
  }
}

$tokensAntesFoto = [Math]::Max(0L, ($tokens7d - $tokensDesdeFoto))
$tokensPorPct = if ($tokensAntesFoto -gt 0 -and $claudeFotoUsado -gt 0) {
  [int64][Math]::Round($tokensAntesFoto / $claudeFotoUsado)
} elseif ($claudeFotoUsado -gt 0) {
  [int64][Math]::Round($tokens7d / $claudeFotoUsado)
} else { [int64]486070 }

$pctAdicional = if ($tokensPorPct -gt 0) { ($tokensDesdeFoto / [double]$tokensPorPct) } else { 0.0 }
$claudeUsadoEstimado = [Math]::Min(100.0, [Math]::Round($claudeFotoUsado + $pctAdicional, 2))
$claudeLibreEstimado = [Math]::Max(0.0, [Math]::Round(100.0 - $claudeUsadoEstimado, 2))
$estimadoRest = [int64][Math]::Round($claudeLibreEstimado * $tokensPorPct)

# 4. Leer llamadas registradas en registro-tokens.jsonl
$regLlamadas = New-Object System.Collections.Generic.List[object]
$agyTokens7d = [int64]0

if (Test-Path -LiteralPath $Global:Mesa_Registro) {
  foreach ($l in [System.IO.File]::ReadLines($Global:Mesa_Registro, [System.Text.Encoding]::UTF8)) {
    if (-not $l.Trim()) { continue }
    try {
      $r = $l | ConvertFrom-Json
      $regLlamadas.Add($r)
      $fLlamada = [DateTimeOffset]::Parse($r.fecha)
      if ($r.herramienta -eq 'agy' -and $fLlamada.LocalDateTime -ge $hace7dLocal) {
        $agyTokens7d += [int64]$r.total
      }
    } catch {}
  }
}

# 5. AGY: estimación por grupo desde cuota-fotos.jsonl y registro-tokens.jsonl
$semillas = @{
  flash      = 1.1
  argon      = 12.8
  claude_gpt = 3.0
}
if ($cfg -and $cfg.coste_semilla) {
  if ($cfg.coste_semilla.flash)      { $semillas['flash']      = [double]$cfg.coste_semilla.flash }
  if ($cfg.coste_semilla.argon)      { $semillas['argon']      = [double]$cfg.coste_semilla.argon }
  if ($cfg.coste_semilla.claude_gpt) { $semillas['claude_gpt'] = [double]$cfg.coste_semilla.claude_gpt }
}

$agyGrupos = [ordered]@{}
foreach ($g in @('flash', 'argon', 'claude_gpt')) {
  $listaFotos = @($fotosPorGrupo[$g] | Sort-Object { [DateTimeOffset]::Parse($_.fecha) })
  $ultimaFoto = if ($listaFotos.Count -gt 0) { $listaFotos[-1] } else { $null }
  $fotoAnt = if ($listaFotos.Count -gt 1) { $listaFotos[-2] } else { $null }

  $semLibreFoto = if ($ultimaFoto) { [double]$ultimaFoto.semanal_libre_pct } else { 0.0 }
  $fechaFoto = if ($ultimaFoto) { [string]$ultimaFoto.fecha } else { $ahoraIso }
  $reiniciaSem = if ($ultimaFoto -and $ultimaFoto.reinicia_semanal) { [string]$ultimaFoto.reinicia_semanal } else { $null }
  $reinicia5h  = if ($ultimaFoto -and $ultimaFoto.reinicia_5h) { [string]$ultimaFoto.reinicia_5h } else { $null }
  $cincoHFoto  = if ($ultimaFoto -and $ultimaFoto.cinco_h_libre_pct -ne $null) { [double]$ultimaFoto.cinco_h_libre_pct } else { $null }

  # Costes atribuidos por modelo y ponderados por duración/tokens en cada foto.
  $coste = [double]$semillas[$g]
  $aprendidas=@($regLlamadas | Where-Object { $_.herramienta -eq 'agy' -and (Mesa-AgyGrupoPorModelo $_.modelo) -eq $g -and $null -ne $_.coste_pct })
  if ($aprendidas.Count) { $coste=[double](($aprendidas | Measure-Object coste_pct -Average).Average) }

  # Llamadas registradas desde la última foto
  $llDesde = @()
  if ($ultimaFoto) {
    $fUltDt = [DateTimeOffset]::Parse($ultimaFoto.fecha)
    $llDesde = @($regLlamadas | Where-Object {
      $_.herramienta -eq 'agy' -and
      (Mesa-AgyGrupoPorModelo $_.modelo) -eq $g -and
      ([DateTimeOffset]::Parse($_.fecha)) -gt $fUltDt
    })
  }

  # % libre estimado semanal
  $gastoSemanal = 0.0
  if ($reiniciaSem -and ([DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reiniciaSem))) {
    $dtReinicioSem = [DateTimeOffset]::Parse($reiniciaSem)
    $llDesdeReinicio = @($regLlamadas | Where-Object {
      $_.herramienta -eq 'agy' -and
      (Mesa-AgyGrupoPorModelo $_.modelo) -eq $g -and
      ([DateTimeOffset]::Parse($_.fecha)) -gt $dtReinicioSem
    })
    foreach ($ll in $llDesdeReinicio) {
      $aprendido = Mesa-CosteModelo 'agy' $ll.modelo $regLlamadas
      $gastoSemanal += $(if ($null -ne $aprendido.media) { $aprendido.media } else { $coste })
    }
    $semanalLibreEst = [Math]::Max(0.0, [Math]::Round(100.0 - $gastoSemanal, 2))
  } else {
    foreach ($ll in $llDesde) {
      $aprendido = Mesa-CosteModelo 'agy' $ll.modelo $regLlamadas
      $gastoSemanal += $(if ($null -ne $aprendido.media) { $aprendido.media } else { $coste })
    }
    $semanalLibreEst = [Math]::Max(0.0, [Math]::Round($semLibreFoto - $gastoSemanal, 2))
  }

  # % libre estimado 5 h (se recupera solo a 100 al pasar su hora de reinicio y cuenta gasto solo desde el reinicio)
  $cincoHLibreEst = $null
  if ($reinicia5h -and ([DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicia5h))) {
    $dtReinicio5h = [DateTimeOffset]::Parse($reinicia5h)
    $llDesde5h = @($regLlamadas | Where-Object {
      $_.herramienta -eq 'agy' -and
      (Mesa-AgyGrupoPorModelo $_.modelo) -eq $g -and
      ([DateTimeOffset]::Parse($_.fecha)) -gt $dtReinicio5h
    })
    $gasto5h = 0.0
    foreach ($ll in $llDesde5h) {
      $aprendido = Mesa-CosteModelo 'agy' $ll.modelo $regLlamadas
      $gasto5h += $(if ($null -ne $aprendido.media) { $aprendido.media } else { $coste })
    }
    $cincoHLibreEst = [Math]::Max(0.0, [Math]::Round(100.0 - $gasto5h, 2))
  } elseif ($cincoHFoto -ne $null) {
    $cincoHLibreEst = [Math]::Max(0.0, [Math]::Round($cincoHFoto - $gastoSemanal, 2))
  }

  # Tareas grandes que caben aún
  $tareasRest = if ($coste -gt 0) { [int][Math]::Floor($semanalLibreEst / $coste) } else { 0 }

  $agyGrupos[$g] = [ordered]@{
    libre_pct_foto             = $semLibreFoto
    fecha_foto                 = $fechaFoto
    libre_pct_estimado         = $semanalLibreEst
    cinco_h_libre_pct_foto     = $cincoHFoto
    cinco_h_libre_pct_estimado = $cincoHLibreEst
    reinicia_semanal           = $reiniciaSem
    reinicia_5h                = $reinicia5h
    coste_por_tarea            = $coste
    calidad                    = 'estimado'
    tareas_restantes           = $tareasRest
    libre_pct                  = $semanalLibreEst
    fecha                      = $fechaFoto
  }
}

# Fuentes oficiales de las CLI, limitadas a una lectura cada diez minutos.
$agiOfficial = @{}
$claudeOfficial = $null
$officialStamp = $null
$cacheValida = $false
if (-not $Forzar -and $cuotaEstadoPrevio -and $cuotaEstadoPrevio.lectura_oficial_fecha) {
  try {
    $officialStamp = [DateTimeOffset]::Parse([string]$cuotaEstadoPrevio.lectura_oficial_fecha)
    $cacheValida = ([DateTimeOffset]::Now - $officialStamp).TotalMinutes -lt 10 -and ([DateTimeOffset]::Now -ge $officialStamp)
  } catch {}
}
if ($cacheValida) {
  if ($cuotaEstadoPrevio.agy.grupos) {
    foreach ($g in @('flash','argon','claude_gpt')) {
      $q = $cuotaEstadoPrevio.agy.grupos.$g
      if ($q -and $q.calidad -eq 'oficial' -and $null -ne $q.libre_pct_oficial) { $agiOfficial[$g] = $q }
    }
  }
  if ($cuotaEstadoPrevio.claude.calidad -eq 'oficial' -and $null -ne $cuotaEstadoPrevio.claude.semanal_usado_pct_oficial) { $claudeOfficial = $cuotaEstadoPrevio.claude }
} else {
  $agyCmd = if ($env:MESA_AGY_COMMAND) { $env:MESA_AGY_COMMAND } else { 'agy' }
  try {
    $rawAgy = Invoke-CuotaCommand $agyCmd '-p "/usage" --output-format json'
    $jsonAgy = $rawAgy | ConvertFrom-Json -ErrorAction Stop
    if (-not $jsonAgy.response) { throw 'JSON de agy sin response' }
    $groupMap = @{ 'Gemini Models'='flash'; 'Claude and GPT models'='claude_gpt'; 'Gemini 4 Argon'='argon' }
    foreach ($line in ([string]$jsonAgy.response -split "`r?`n")) {
      $cols = $line -split "`t"
      if ($cols.Count -lt 4 -or -not $groupMap.ContainsKey($cols[0].Trim())) { continue }
      $g = $groupMap[$cols[0].Trim()]
      if ($cols[1] -match 'Weekly' -and $cols[2] -match '^\s*(\d+(?:\.\d+)?)%\s*$') {
        if (-not $agiOfficial.ContainsKey($g)) { $agiOfficial[$g] = [ordered]@{} }
        $agiOfficial[$g].libre_pct_oficial = [double]$Matches[1]
        $agiOfficial[$g].reinicia_semanal = [string]$cols[3].Trim()
      } elseif ($cols[1] -match 'Five Hour' -and $cols[2] -match '^\s*(\d+(?:\.\d+)?)%\s*$') {
        if (-not $agiOfficial.ContainsKey($g)) { $agiOfficial[$g] = [ordered]@{} }
        $agiOfficial[$g].cinco_h_libre_pct_oficial = [double]$Matches[1]
        $agiOfficial[$g].reinicia_5h = [string]$cols[3].Trim()
      }
    }
    foreach ($g in @('flash','argon','claude_gpt')) { if (-not $agiOfficial.ContainsKey($g) -or $null -eq $agiOfficial[$g].libre_pct_oficial) { $agiOfficial.Remove($g) } }
  } catch { Write-Verbose "Lectura oficial agy falló: $_"; $agiOfficial = @{} }

  $claudeCmd = if ($env:MESA_CLAUDE_COMMAND) { $env:MESA_CLAUDE_COMMAND } else { 'claude' }
  try {
    $rawClaude = Invoke-CuotaCommand $claudeCmd '-p "/usage"'
    $week = $null; $fable = $null; $session = $null
    foreach ($line in ($rawClaude -split "`r?`n")) {
      if ($line -match '^\s*Current session:\s*(\d+(?:\.\d+)?)% used.*?resets\s+(.+?)\s*\(America/Bogota\)') { $session = @{ usado=[double]$Matches[1]; reinicia=(Convert-CuotaClaudeReset $Matches[2] $ahora) } }
      elseif ($line -match '^\s*Current week \(all models\):\s*(\d+(?:\.\d+)?)% used.*?resets\s+(.+?)\s*\(America/Bogota\)') { $week = @{ usado=[double]$Matches[1]; reinicia=(Convert-CuotaClaudeReset $Matches[2] $ahora) } }
      elseif ($line -match '^\s*Current week \(Fable\):\s*(\d+(?:\.\d+)?)% used.*?resets\s+(.+?)\s*\(America/Bogota\)') { $fable = @{ usado=[double]$Matches[1]; reinicia=(Convert-CuotaClaudeReset $Matches[2] $ahora) } }
    }
    if ($week -and $fable -and $session) { $claudeOfficial = [ordered]@{ semanal_usado_pct_oficial=$week.usado; fable_usado_pct=$fable.usado; sesion_5h_usado_pct=$session.usado; reinicia_semanal=$week.reinicia; reinicia_fable=$fable.reinicia; reinicia_5h=$session.reinicia; calidad='oficial' } }
  } catch { Write-Verbose "Lectura oficial Claude falló: $_"; $claudeOfficial = $null }
  if (($agiOfficial.Count -gt 0) -or $claudeOfficial) { $officialStamp = [DateTimeOffset]::Now }
}

# Sustituir estimaciones con valores oficiales y registrar cada nueva lectura como foto.
if ($claudeOfficial) {
  $claudeLibreEstimado = [Math]::Round(100.0 - [double]$claudeOfficial.semanal_usado_pct_oficial, 2)
  $claudeUsadoEstimado = [double]$claudeOfficial.semanal_usado_pct_oficial
}
foreach ($g in @('flash','argon','claude_gpt')) {
  if ($agiOfficial.ContainsKey($g)) {
    $o = $agiOfficial[$g]
    $agyGrupos[$g].libre_pct_estimado = [double]$o.libre_pct_oficial
    $agyGrupos[$g].libre_pct = [double]$o.libre_pct_oficial
    $agyGrupos[$g].libre_pct_oficial = [double]$o.libre_pct_oficial
    $agyGrupos[$g].calidad = 'oficial'
    if ($o.reinicia_semanal) { $agyGrupos[$g].reinicia_semanal = $o.reinicia_semanal }
    if ($o.reinicia_5h) { $agyGrupos[$g].reinicia_5h = $o.reinicia_5h }
    if ($null -ne $o.cinco_h_libre_pct_oficial) { $agyGrupos[$g].cinco_h_libre_pct_estimado = [double]$o.cinco_h_libre_pct_oficial; $agyGrupos[$g].cinco_h_libre_pct_oficial = [double]$o.cinco_h_libre_pct_oficial }
    if (-not $cacheValida) {
      $foto = [ordered]@{ fecha=$ahoraIso; grupo=$g; semanal_libre_pct=[double]$o.libre_pct_oficial; reinicia_semanal=$o.reinicia_semanal; origen='oficial' }
      if ($null -ne $o.cinco_h_libre_pct_oficial) { $foto.cinco_h_libre_pct=[double]$o.cinco_h_libre_pct_oficial; $foto.reinicia_5h=$o.reinicia_5h }
      Mesa-AnexarLinea $Global:Mesa_CuotaFotos ($foto | ConvertTo-Json -Compress)
    }
  }
}
if ($claudeOfficial) {
  $claudeLibreEstimado = [Math]::Round(100.0 - [double]$claudeOfficial.semanal_usado_pct_oficial, 2)
  if (-not $cacheValida) {
    $foto = [ordered]@{ fecha=$ahoraIso; grupo='claude'; semanal_libre_pct=$claudeLibreEstimado; semanal_usado_pct=[double]$claudeOfficial.semanal_usado_pct_oficial; reinicia_semanal=$claudeOfficial.reinicia_semanal; reinicia_5h=$claudeOfficial.reinicia_5h; cinco_h_libre_pct=[Math]::Round(100.0-[double]$claudeOfficial.sesion_5h_usado_pct,2); origen='oficial' }
    Mesa-AnexarLinea $Global:Mesa_CuotaFotos ($foto | ConvertTo-Json -Compress)
  }
}

# 6. Contadores y sugerencia
$contadores = Mesa-ContadoresLlamadas
$codexSemLibre = if ($null -ne $codexSemPct) { [Math]::Round(100.0 - $codexSemPct, 2) } else { $null }
$codex5hLibre  = if ($null -ne $codex5hPct) { [Math]::Round(100.0 - $codex5hPct, 2) } else { $null }
$codexEfLibre  = if ($null -ne $codexSemLibre -and $null -ne $codex5hLibre) { [Math]::Min($codexSemLibre, $codex5hLibre) } elseif ($null -ne $codexSemLibre) { $codexSemLibre } else { $codex5hLibre }

$codex5hDisp = if ($codex5hTrasReinicio) { "100% (tras reinicio)" } elseif ($null -ne $codex5hLibre) { "$codex5hLibre%" } else { "N/D" }
$codexSemDisp = if ($codexSemTrasReinicio) { "100% (tras reinicio)" } elseif ($null -ne $codexSemLibre) { "$codexSemLibre%" } else { "N/D" }

$flashEst = $agyGrupos['flash'].libre_pct_estimado
$argonEst = $agyGrupos['argon'].libre_pct_estimado
$cgptEst  = $agyGrupos['claude_gpt'].libre_pct_estimado

$candidatos = @(
  [pscustomobject]@{ nombre = 'agy/flash';      libre = $flashEst; extra = "~$($agyGrupos['flash'].tareas_restantes) tareas" },
  [pscustomobject]@{ nombre = 'codex';          libre = $codexEfLibre; extra = "5h: $codex5hDisp, sem: $codexSemDisp" },
  [pscustomobject]@{ nombre = 'agy/argon';      libre = $argonEst; extra = "~$($agyGrupos['argon'].tareas_restantes) tareas" },
  [pscustomobject]@{ nombre = 'agy/claude_gpt'; libre = $cgptEst; extra = "~$($agyGrupos['claude_gpt'].tareas_restantes) tareas" },
  [pscustomobject]@{ nombre = 'claude';         libre = $claudeLibreEstimado; extra = "$estimadoRest tokens" }
)

$validosPesado = $candidatos | Where-Object { $null -ne $_.libre -and $_.libre -ge 10.0 } | Sort-Object libre -Descending
$mejorPesado = if ($validosPesado) { "$($validosPesado[0].nombre) ($($validosPesado[0].libre)% libre, $($validosPesado[0].extra))" } else { "ninguno (>=10% libre)" }
$noUsar = @($candidatos | Where-Object { $null -ne $_.libre -and $_.libre -lt 10.0 } | ForEach-Object {
  if ($_.nombre -eq 'codex' -and $null -ne $codex5hLibre -and $codex5hLibre -lt 10.0) { "codex (5h: $codex5hDisp libre, 7d: $codexSemDisp libre)" }
  else { "$($_.nombre) ($($_.libre)% libre)" }
})

$partesSug = @("Trabajo pesado a $mejorPesado.")
if ($claudeLibreEstimado -lt 20.0) {
  $partesSug += "Claude solo para decisiones (queda $claudeLibreEstimado% libre, <20%)."
}
if ($noUsar.Count -gt 0) {
  $partesSug += "No usar por debajo del 10% libre: $($noUsar -join ', ')."
}
$sugerencia = $partesSug -join ' '

# 7. Estado final y guardado
$estado = [ordered]@{
  actualizado = $ahoraIso
  codex       = [ordered]@{
    fuente                = 'rate_limits del JSONL de sesión más reciente'
    observado             = $codexObservado
    calidad               = if ($codex5hTrasReinicio -or $codexSemTrasReinicio) { 'oficial (tras reinicio)' } else { 'oficial' }
    cinco_horas_usado_pct = $codex5hPct
    cinco_horas_libre_pct = $codex5hLibre
    cinco_horas_reinicia  = $codex5hIso
    cinco_horas_estado    = if ($codex5hTrasReinicio) { 'tras reinicio' } else { 'vigente' }
    semanal_usado_pct     = $codexSemPct
    semanal_libre_pct     = $codexSemLibre
    semanal_reinicia      = $codexSemIso
    semanal_estado        = if ($codexSemTrasReinicio) { 'tras reinicio' } else { 'vigente' }
  }
  claude      = [ordered]@{
    tokens_hoy                 = $tokensHoy
    tokens_5h                  = $tokens5h
    tokens_7d                  = $tokens7d
    tokens_desde_foto          = $tokensDesdeFoto
    cache_read_hoy             = $cacheReadHoy
    cache_read_5h              = $cacheRead5h
    cache_read_7d              = $cacheRead7d
    semanal_usado_pct_foto     = $claudeFotoUsado
    semanal_libre_pct_foto     = [Math]::Round(100.0 - $claudeFotoUsado, 2)
    fecha_foto                 = $claudeFotoFecha
    semanal_usado_pct_estimado = $claudeUsadoEstimado
    semanal_libre_pct_estimado = $claudeLibreEstimado
    semanal_usado_pct_manual   = $claudeUsadoEstimado
    fecha_manual               = $claudeFotoFecha
    semanal_usado_pct_oficial  = if ($claudeOfficial) { $claudeOfficial.semanal_usado_pct_oficial } else { $null }
    fable_usado_pct            = if ($claudeOfficial) { $claudeOfficial.fable_usado_pct } else { $null }
    sesion_5h_usado_pct        = if ($claudeOfficial) { $claudeOfficial.sesion_5h_usado_pct } else { $null }
    reinicia_semanal           = if ($claudeOfficial) { $claudeOfficial.reinicia_semanal } else { $claudeReiniciaSem }
    reinicia_fable             = if ($claudeOfficial) { $claudeOfficial.reinicia_fable } else { $null }
    reinicia_5h                = if ($claudeOfficial) { $claudeOfficial.reinicia_5h } else { $claudeReinicia5h }
    tokens_por_pct             = $tokensPorPct
    estimado_restante_tokens   = $estimadoRest
    calidad                    = if ($claudeOfficial) { 'oficial' } else { 'estimado' }
    cobertura                  = 'colas de 256 KB; tokens observados, histórico incompleto'
  }
  agy         = [ordered]@{
    llamadas_hoy       = [int]$contadores.agy.dia
    tokens_7d_registro = $agyTokens7d
    grupos             = $agyGrupos
  }
  lectura_oficial_fecha = if ($officialStamp) { $officialStamp.ToString('yyyy-MM-ddTHH:mm:sszzz') } else { $null }
  llamadas    = [ordered]@{
    codex    = [ordered]@{ hora = [int]$contadores.codex.hora;    dia = [int]$contadores.codex.dia }
    agy      = [ordered]@{ hora = [int]$contadores.agy.hora;      dia = [int]$contadores.agy.dia }
    claude   = [ordered]@{ hora = [int]$contadores.claude.hora;   dia = [int]$contadores.claude.dia }
  }
  sugerencia  = $sugerencia
}

Mesa-EscribirJson $Global:Mesa_CuotaEstado $estado

if ($Json) {
  $estado | ConvertTo-Json -Depth 8
} else {
  $filas = @(
    [pscustomobject]@{
      Herramienta   = 'codex'
      Libre_Sem_Pct = if ($codexSemTrasReinicio -and $codex5hTrasReinicio) { "100% (tras reinicio)" } elseif ($null -ne $codexSemLibre) { "$codexSemLibre% (5h: $codex5hDisp)" } else { "5h: $codex5hDisp" }
      Usado_5h_Sem  = "5h: $(if ($codex5hTrasReinicio) { '0% (tras reinicio)' } elseif ($null -ne $codex5hPct) { ""$codex5hPct%"" } else { 'N/D' }) | 7d: $(if ($codexSemTrasReinicio) { '0% (tras reinicio)' } elseif ($null -ne $codexSemPct) { ""$codexSemPct%"" } else { 'N/D' })"
      Tokens_o_Info = if ($codex5hIso) { "reinicia 5h: $codex5hIso" } else { "sin fecha de reinicio" }
      Llamadas_H_D  = "$($contadores.codex.hora)/h, $($contadores.codex.dia)/d"
    },
    [pscustomobject]@{
      Herramienta   = 'claude'
      Libre_Sem_Pct = if ($claudeOfficial) { "$claudeLibreEstimado% (oficial)" } else { "≈ $claudeLibreEstimado% (estimado; foto: $([Math]::Round(100.0 - $claudeFotoUsado, 2))%)" }
      Usado_5h_Sem  = if ($claudeOfficial) { "5h: $($claudeOfficial.sesion_5h_usado_pct)% usado | 7d: $claudeUsadoEstimado% usado" } else { "7d est: $claudeUsadoEstimado% (foto $claudeFotoFecha)" }
      Tokens_o_Info = "5h: $tokens5h | 7d: $tokens7d | rest: ~$estimadoRest"
      Llamadas_H_D  = "$($contadores.claude.hora)/h, $($contadores.claude.dia)/d"
    },
    [pscustomobject]@{
      Herramienta   = 'agy/flash'
      Libre_Sem_Pct = "$(if ($agyGrupos['flash'].calidad -eq 'oficial') { "$flashEst% (oficial)" } else { "≈ $flashEst% (estimado)" }) (5h: $($agyGrupos['flash'].cinco_h_libre_pct_estimado)%)"
      Usado_5h_Sem  = "foto sem: $($agyGrupos['flash'].libre_pct_foto)% ($($agyGrupos['flash'].fecha_foto))"
      Tokens_o_Info = "quedan ~$($agyGrupos['flash'].tareas_restantes) tareas (coste $($agyGrupos['flash'].coste_por_tarea)%)"
      Llamadas_H_D  = "$($contadores.agy.hora)/h, $($contadores.agy.dia)/d"
    },
    [pscustomobject]@{
      Herramienta   = 'agy/argon'
      Libre_Sem_Pct = if ($agyGrupos['argon'].calidad -eq 'oficial') { "$argonEst% (oficial)" } else { "≈ $argonEst% (estimado)" }
      Usado_5h_Sem  = "foto sem: $($agyGrupos['argon'].libre_pct_foto)% ($($agyGrupos['argon'].fecha_foto))"
      Tokens_o_Info = "quedan ~$($agyGrupos['argon'].tareas_restantes) tareas (coste $($agyGrupos['argon'].coste_por_tarea)%)"
      Llamadas_H_D  = "$($contadores.agy.hora)/h, $($contadores.agy.dia)/d"
    },
    [pscustomobject]@{
      Herramienta   = 'agy/claude_gpt'
      Libre_Sem_Pct = if ($agyGrupos['claude_gpt'].calidad -eq 'oficial') { "$cgptEst% (oficial)" } else { "≈ $cgptEst% (estimado)" }
      Usado_5h_Sem  = "foto sem: $($agyGrupos['claude_gpt'].libre_pct_foto)% ($($agyGrupos['claude_gpt'].fecha_foto))"
      Tokens_o_Info = "quedan ~$($agyGrupos['claude_gpt'].tareas_restantes) tareas (coste $($agyGrupos['claude_gpt'].coste_por_tarea)%)"
      Llamadas_H_D  = "$($contadores.agy.hora)/h, $($contadores.agy.dia)/d"
    }
  )
  $filas | Format-Table -AutoSize | Out-String -Width 160 | ForEach-Object { $_.TrimEnd() }
  Write-Output "Capacidad tareas grandes agy: flash: ~$($agyGrupos['flash'].tareas_restantes) tareas; argon: ~$($agyGrupos['argon'].tareas_restantes); claude_gpt: ~$($agyGrupos['claude_gpt'].tareas_restantes)"
  Write-Output "Nota Claude (aproximación): tokens_por_pct = $tokensPorPct; tokens_desde_foto = $tokensDesdeFoto; restante = ~$estimadoRest tokens"
  Write-Output "Sugerencia: $sugerencia"
}
