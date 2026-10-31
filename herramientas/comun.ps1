# Biblioteca común de la Cuadrilla: rutas, configuración, JSON atómico, exclusiones, causa de fallo y ocultar secretos.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Global:Mesa_Base = Split-Path -Parent $PSScriptRoot
# Carpeta de datos: MESA_DATOS (las pruebas la aíslan en %TEMP%) o datos\ junto a la mesa.
$Global:Mesa_Raiz = if ($env:MESA_DATOS) { $env:MESA_DATOS } else { Join-Path $Global:Mesa_Base 'datos' }
# Carpeta donde están los repositorios: MESA_TRABAJO o, por defecto, la que contiene la mesa.
$Global:Mesa_DefaultDir = if ($env:MESA_TRABAJO) { $env:MESA_TRABAJO } else { Split-Path -Parent $Global:Mesa_Base }

# Ámbitos que ningún agente toca ni se muestran: una expresión regular por línea en datos\excluidos.txt, que no se versiona.
function Mesa-Excluidos {
  $f = Join-Path $Global:Mesa_Raiz 'excluidos.txt'
  if (Test-Path -LiteralPath $f) {
    $lineas = @([IO.File]::ReadAllLines($f) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($lineas.Count) { $x = '(?i)' + (($lineas | ForEach-Object { "(?:$_)" }) -join '|'); [void][regex]::new($x); return $x }
  }
  '(?!)'
}
$Global:Mesa_Excluidos = Mesa-Excluidos

# Oculta secretos y rutas excluidas antes de imprimir o guardar la respuesta de un CLI.
function Mesa-Ocultar([string]$Texto) {
  $s = $Texto -replace '(?i)(?:ghp_|github_pat_|sk-|AIza)[A-Za-z0-9_\-]+', '<OCULTO>'
  $s = $s -replace '(?i)(Bearer\s+)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace '(?i)(X-[\w-]*Token\s*[=:]\s*)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace '(?i)((?:api[_-]?key|password|secret|access[_-]?token)\s*[=:]\s*["'']?)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace ($Global:Mesa_Excluidos + '[^\s"'']*'), '<RUTA EXCLUIDA>'
  return $s
}

# Por qué falló una llamada, leyendo solo el evento final de su log: cuota, login o red no son muertes reales y se tratan aparte.
function Mesa-CausaFallo([string]$texto) {
  try { $ev = $texto | ConvertFrom-Json -ErrorAction Stop } catch { $ev = $null }
  if ($ev) {
    $esResultado = $ev.type -eq 'result' -or $ev.event -eq 'result' -or (-not $ev.type -and -not $ev.event)
    $r = if ($ev.result -and $ev.result -isnot [string]) { $ev.result } else { $ev }
    $fallo = ($esResultado -and ($ev.is_error -eq $true -or $ev.subtype -like 'error*' -or
      $r.status -in @('ERROR','RESOURCE_EXHAUSTED','FAILED') -or $r.error_code -or $r.error)) -or
      $ev.type -in @('error','turn.failed')
    if (-not $fallo) { return $null }
    $texto = @($r.status, $r.error_code, $r.error, $r.errors, $ev.error, $ev.errors) | ConvertTo-Json -Depth 20 -Compress
    # message/result solo son texto de error cuando el evento final declara fallo.
    $texto += ' ' + [string]$r.message
    if ($ev.is_error -eq $true -and $ev.result -is [string]) { $texto += ' ' + $ev.result }
  } elseif ($texto -notmatch '^\s*Error:\s*(401\s+Unauthorized|connection failed|RESOURCE_EXHAUSTED)') {
    return $null
  }
  if ($texto -match '(?i)RESOURCE_EXHAUSTED|usage limit|rate.?limit|quota|\b429\b|limit reached|out of credits') {
    $hasta = if ($texto -match '(?i)resets? in (\d+)h(\d+)m') { (Get-Date).AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]) }
      elseif ($texto -match '(?i)try again at (\d{1,2}):(\d{2})\s*([AP]M)?') {
        # «try again at 6:57 PM» de codex: la hora real de hoy o, si ya pasó, de mañana (el 24-oct se guardó «hasta las 15:10»).
        $h = [int]$Matches[1]; if ($Matches[3] -eq 'PM' -and $h -lt 12) { $h += 12 } elseif ($Matches[3] -eq 'AM' -and $h -eq 12) { $h = 0 }
        $t = (Get-Date).Date.AddHours($h).AddMinutes([int]$Matches[2]); if ($t -le (Get-Date)) { $t = $t.AddDays(1) }; $t
      } else { (Get-Date).AddHours(1) }
    return [pscustomobject]@{ fallo = $true; causa = 'sin-cuota'; hasta = $hasta.ToString('yyyy-MM-ddTHH:mm:sszzz') }
  }
  if ($texto -match '(?i)\b401\b|unauthori[sz]ed|not logged in|please (log ?in|sign in)|/login|invalid (api key|credentials)|token (has )?expired') { return [pscustomobject]@{ fallo = $true; causa = 'necesita-login'; hasta = $null } }
  if ($texto -match '(?i)waiting for network|connection failed|ENOTFOUND|ECONNRESET|network error|UNAVAILABLE|\b50[23]\b|overloaded') { return [pscustomobject]@{ fallo = $true; causa = 'red'; hasta = $null } }
  [pscustomobject]@{ fallo = $true; causa = $null; hasta = $null }
}

function Mesa-IsoNow { (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz') }

# Un PID se reutiliza: la identidad es PID, hora de inicio y nombre.
function Mesa-ProcesoVivo {
  param([Alias('pid')][int]$procesoId, [string]$inicio, [string]$nombre)
  if ($procesoId -le 0 -or -not $inicio -or -not $nombre) { return $false }
  try {
    $proceso = Get-Process -Id $procesoId -ErrorAction Stop
    return (-not $proceso.HasExited -and $proceso.ProcessName -eq $nombre -and
      $proceso.StartTime.ToUniversalTime().Ticks -eq [datetime]::Parse($inicio).ToUniversalTime().Ticks)
  } catch { return $false }
}

function Mesa-ConfigPath {
  if ($env:MESA_CONFIG) { return $env:MESA_CONFIG }
  $propia = Join-Path $Global:Mesa_Raiz 'mesa.json'
  # Sin configuración propia (instalación nueva), la de ejemplo que trae el repositorio.
  if (Test-Path -LiteralPath $propia) { $propia } else { Join-Path $Global:Mesa_Base 'datos\mesa.ejemplo.json' }
}

function Mesa-LeerJson($ruta) {
  if (-not (Test-Path -LiteralPath $ruta)) { return $null }
  $raw = [IO.File]::ReadAllText($ruta, [Text.Encoding]::UTF8)
  try { return ($raw | ConvertFrom-Json -ErrorAction Stop) } catch {}
  # Comentarios // de fin de línea si alguien edita mesa.json a mano.
  $limpio = ($raw -split "`r?`n" | ForEach-Object { $_ -replace '\s+//.*$', '' }) -join "`n"
  try { return ($limpio | ConvertFrom-Json -ErrorAction Stop) } catch { throw "JSON dañado en ${ruta}: $($_.Exception.Message)" }
}

# Escritura atómica: archivo temporal y File.Replace (Move-Item -Force borra y luego mueve), para que un apagón no deje un JSON a medias ni sin archivo.
function Mesa-EscribirJson($ruta, $obj) {
  $carpeta = Split-Path -Parent $ruta
  if ($carpeta -and -not (Test-Path -LiteralPath $carpeta)) { New-Item -ItemType Directory -Force -Path $carpeta | Out-Null }
  $tmp = "$ruta.tmp.$PID.$([Guid]::NewGuid().ToString('N').Substring(0,6))"
  [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding $false))
  # NullString y no $null: PowerShell pasaría "" y Replace lo rechaza como ruta de copia.
  if (Test-Path -LiteralPath $ruta) { [IO.File]::Replace($tmp, $ruta, [NullString]::Value) } else { [IO.File]::Move($tmp, $ruta) }
}

function Mesa-ModeloPorDefecto($herramienta, $cfg) {
  if ($cfg -and $cfg.modelos -and $cfg.modelos.$herramienta -and $cfg.modelos.$herramienta.Count -gt 0) { return $cfg.modelos.$herramienta[0] }
  switch ($herramienta) { 'codex' { 'gpt-6-luna' } 'agy' { 'gemini-3.8-flash-low' } }
}
