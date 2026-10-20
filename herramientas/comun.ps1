# Configuración común para Mesa de agentes (independiente).
# Solo para Claude, Codex y Antigravity (agy).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Global:Mesa_Base = Split-Path -Parent $PSScriptRoot
# Carpeta de datos: MESA_DATOS (MESA_RAIZ_PRUEBA es su nombre antiguo y sigue valiendo) o datos\ junto a la mesa.
$Global:Mesa_Raiz = if ($env:MESA_DATOS) { $env:MESA_DATOS } elseif ($env:MESA_RAIZ_PRUEBA) { $env:MESA_RAIZ_PRUEBA } else { Join-Path $Global:Mesa_Base 'datos' }
$Global:Mesa_Hilos = Join-Path $Global:Mesa_Raiz 'hilos'
$Global:Mesa_Registro = Join-Path $Global:Mesa_Raiz 'registro-tokens.jsonl'
$Global:Mesa_Aprobaciones = Join-Path $Global:Mesa_Raiz 'aprobaciones.log'
$Global:Mesa_CuotaEstado = Join-Path $Global:Mesa_Raiz 'cuota-estado.json'
$Global:Mesa_CuotaFotos = Join-Path $Global:Mesa_Raiz 'cuota-fotos.jsonl'
# Carpeta donde trabajan los agentes: MESA_TRABAJO o, por defecto, la que contiene la mesa.
$Global:Mesa_DefaultDir = if ($env:MESA_TRABAJO) { $env:MESA_TRABAJO } else { Split-Path -Parent $Global:Mesa_Base }
$Global:Mesa_Agentes = @('claude', 'codex', 'agy')

# Ámbitos que ningún agente toca ni se muestran: una expresión regular en datos\excluidos.txt, que no se versiona.
function Mesa-Excluidos {
  $f = Join-Path $Global:Mesa_Raiz 'excluidos.txt'
  if (Test-Path -LiteralPath $f) {
    $lineas = @([IO.File]::ReadAllLines($f) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    if ($lineas.Count) { $x = '(?i)' + (($lineas | ForEach-Object { "(?:$_)" }) -join '|'); [void][regex]::new($x); return $x }
  }
  '(?!)'
}

# Última señal de vida de un agente: actividad.jsonl, que el vigía escribe con cada herramienta que usa.
# El latido del panel no cuenta: un panel vivo con el agente parado no sostiene un reclamo ni un liderazgo.
function Mesa-UltimaActividad($agente) {
  $ult = [datetime]::MinValue
  $f = Join-Path $Global:Mesa_Raiz 'actividad.jsonl'
  if (Test-Path -LiteralPath $f) {
    $fs = [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite')
    try { [void]$fs.Seek([Math]::Max(0, $fs.Length - 262144), 'Begin'); $txt = (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
    foreach ($l in $txt -split "`n") {
      if ($l -match ('"agente":"' + $agente + '"') -and $l -match '"hora":"([^"]+)"') { $h = [datetime]::Parse($Matches[1]); if ($h -gt $ult) { $ult = $h } }
    }
  }
  $ult
}

# Por qué falló una llamada, leyendo la cola de su log: cuota, login o red no son muertes reales y se tratan aparte.
function Mesa-CausaFallo([string]$texto) {
  if ($texto -match '(?i)RESOURCE_EXHAUSTED|usage limit|rate.?limit|quota|\b429\b|limit reached|out of credits') {
    $hasta = if ($texto -match '(?i)resets? in (\d+)h(\d+)m') { (Get-Date).AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]) } else { (Get-Date).AddHours(1) }
    return [pscustomobject]@{ causa = 'sin-cuota'; hasta = $hasta.ToString('yyyy-MM-ddTHH:mm:sszzz') }
  }
  if ($texto -match '(?i)\b401\b|unauthori[sz]ed|not logged in|please (log ?in|sign in)|/login|invalid (api key|credentials)|token (has )?expired') { return [pscustomobject]@{ causa = 'necesita-login'; hasta = $null } }
  if ($texto -match '(?i)waiting for network|connection failed|ENOTFOUND|ECONNRESET|network error') { return [pscustomobject]@{ causa = 'red'; hasta = $null } }
  $null
}

# Tipo de un encargo para decidir si se autoaprueba: lo declara quien delega (-Tipo) o se deduce de su carpeta.
# lectura, mesa (escribe solo en la mesa), relevo: autoaprobables. repo, carpeta, red, irreversible: esperan a la persona.
function Mesa-TipoEncargo($dir, $declarado) {
  if ($declarado) { return $declarado }
  if (-not $dir) { return 'carpeta' }
  $d = [IO.Path]::GetFullPath($dir).TrimEnd('\') + '\'
  if ($d.StartsWith($Global:Mesa_Base.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return 'mesa' }
  $p = $d.TrimEnd('\')
  while ($p) { if (Test-Path -LiteralPath (Join-Path $p '.git')) { return 'repo' }; $p = Split-Path -Parent $p }
  'carpeta'
}

# Modo de aprobación: «por-tipo» (por defecto), «todo» (lo de antes: se autoaprueba cualquier encargo de un agente de la lista) o «nada».
function Mesa-Aprobacion($cfg) {
  $a = $cfg.aprobacion
  [pscustomobject]@{
    modo = if ($a.modo) { [string]$a.modo } else { 'por-tipo' }
    tipos = if ($a.autoaprobados) { @($a.autoaprobados) } else { @('lectura', 'mesa', 'relevo') }
  }
}

# Lo nuevo para un agente desde una fecha: lo dirigido a él o a 'todos', y los inicio/alcance/bloqueo y cambios de líder de los demás.
function Mesa-Novedades($yo, [datetime]$desde, [int]$max = 600) {
  foreach ($a in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Recurse -Filter '*-*.json' -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -gt $desde -and $_.Directory.Name -notin @('logs', 'entregas', 'claims') } | Sort-Object LastWriteTime)) {
    $m = Mesa-LeerMensaje $a.FullName
    if ($m -and $m.tipo -ne 'encargo' -and (Mesa-NormalizarHerramienta $m.autor) -ne $yo -and
        ($m.tipo -in @('avance-inicio', 'avance-alcance', 'avance-bloqueo', 'lider') -or
         @(([string]$m.para) -split '[,;]' | Where-Object { (Mesa-NormalizarHerramienta $_.Trim()) -eq $yo -or $_.Trim() -eq 'todos' }).Count)) {
      $t = [string]$m.texto
      '{0} #{1} {2} -> {3} [{4}]: {5}' -f $a.Directory.Name, $m.n, $m.autor, $m.para, $m.tipo, $(if ($t.Length -gt $max) { $t.Substring(0, $max) + '…' } else { $t })
    }
  }
}

function Mesa-IsoNow {
  (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
}

function Mesa-ProcesoVivo {
  param([Alias('pid')][int]$procesoId, [string]$inicio, [string]$nombre)
  if ($procesoId -le 0 -or -not $inicio -or -not $nombre) { return $false }
  try {
    $proceso = Get-Process -Id $procesoId -ErrorAction Stop
    return (-not $proceso.HasExited -and $proceso.ProcessName -eq $nombre -and
      $proceso.StartTime.ToUniversalTime().Ticks -eq [datetime]::Parse($inicio).ToUniversalTime().Ticks)
  } catch { return $false }
}

function Mesa-ConfigPath($customPath = $null) {
  if ($customPath) { return $customPath }
  if ($env:MESA_CONFIG) { return $env:MESA_CONFIG }
  $propia = Join-Path $Global:Mesa_Raiz 'mesa.json'
  # Sin configuración propia (instalación nueva), la de ejemplo que trae el repositorio.
  if (Test-Path -LiteralPath $propia) { return $propia } else { return (Join-Path $Global:Mesa_Base 'datos\mesa.ejemplo.json') }
}

function Mesa-LeerJson($ruta) {
  if (-not (Test-Path -LiteralPath $ruta)) { return $null }
  $raw = [System.IO.File]::ReadAllText($ruta, [System.Text.Encoding]::UTF8)
  # Primero tal cual: quitar '//' rompía textos con URLs o código dentro (logs de agentes).
  try { return ($raw | ConvertFrom-Json -ErrorAction Stop) } catch {}
  # Limpiar comentarios // de fin de línea fuera de cadenas si alguien edita mesa.json a mano
  $limpio = ($raw -split "`r?`n" | ForEach-Object { $_ -replace '\s+//.*$', '' }) -join "`n"
  try { return ($limpio | ConvertFrom-Json -ErrorAction Stop) } catch { throw "JSON dañado en ${ruta}: $($_.Exception.Message)" }
}

$Global:Mesa_Excluidos = Mesa-Excluidos
# Nombre de la persona que dirige la mesa en los hilos (autor de charlas, aprobaciones y escalados).
$Global:Mesa_Humano = if ($env:MESA_HUMANO) { $env:MESA_HUMANO } else { @($(try { (Mesa-LeerJson (Mesa-ConfigPath)).humano } catch { $null }), 'usuario') | Where-Object { $_ } | Select-Object -First 1 }

# Para recorrer hilos: un mensaje dañado se avisa y se salta en vez de cortar el listado entero.
function Mesa-LeerMensaje($ruta) {
  try { Mesa-LeerJson $ruta } catch { Write-Warning $_.Exception.Message; $null }
}

function Mesa-EscribirJson($ruta, $obj, [switch]$Comprimir) {
  $carpeta = Split-Path -Parent $ruta
  if ($carpeta -and -not (Test-Path -LiteralPath $carpeta)) {
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
  }
  $json = if ($Comprimir) { $obj | ConvertTo-Json -Depth 10 -Compress } else { $obj | ConvertTo-Json -Depth 10 }
  $tmp = "$ruta.tmp.$PID.$([Guid]::NewGuid().ToString('N').Substring(0,6))"
  [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding $false))
  Move-Item -LiteralPath $tmp -Destination $ruta -Force
}

function Mesa-AnexarLinea($ruta, $linea) {
  $carpeta = Split-Path -Parent $ruta
  if ($carpeta -and -not (Test-Path -LiteralPath $carpeta)) {
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null
  }
  $candado=Mesa-Bloquear $ruta
  try {
    [System.IO.File]::AppendAllText($ruta, ($linea + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding $false))
  } finally { $candado.Dispose() }
}

# Candado entre procesos: <ruta>.lock abierto en exclusiva; Windows lo suelta aunque el proceso muera.
function Mesa-Bloquear($ruta) {
  for ($intento=0; $intento -lt 200; $intento++) {
    try { return [IO.File]::Open("$ruta.lock",'OpenOrCreate','ReadWrite','None') }
    catch { Start-Sleep -Milliseconds 50 }
  }
  throw "Ocupado ($ruta); no se escribió nada."
}

function Mesa-BloquearRegistro { Mesa-Bloquear $Global:Mesa_Registro }

function Mesa-BloquearHilo($carpetaHilo) { Mesa-Bloquear (Join-Path $carpetaHilo 'hilo') }

# Numera y escribe en una sola sección bajo candado: dos agentes a la vez no comparten número ni se sobrescriben.
function Mesa-EscribirMensaje($carpetaHilo, $msg, $autor) {
  $candado = Mesa-BloquearHilo $carpetaHilo
  try {
    $max = 0
    Get-ChildItem -LiteralPath $carpetaHilo -Filter '*-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.BaseName -match '^(\d+)-') { $max = [Math]::Max($max, [int]$Matches[1]) }
    }
    $msg['n'] = $max + 1
    $nombre = '{0:D4}-{1}.json' -f ($max + 1), $autor
    Mesa-EscribirJson (Join-Path $carpetaHilo $nombre) $msg
    return $nombre
  } finally { $candado.Dispose() }
}

# Reclamos globales (datos\reclamos) y por hilo (hilos\<id>\claims): quién tiene qué.
function Mesa-Reclamos {
  # lider.json era una segunda fuente del líder: ya no cuenta. El líder de cada hilo vive solo en su hilo.json.
  $archivos = @(Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Raiz 'reclamos') -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object Name -ne 'lider.json')
  $archivos += @(Get-ChildItem -Path (Join-Path $Global:Mesa_Hilos '*\claims\*.json') -ErrorAction SilentlyContinue)
  foreach ($a in $archivos) {
    try { $r = Mesa-LeerJson $a.FullName } catch { continue }
    if (-not $r) { continue }
    $enHilo = $a.Directory.Name -eq 'claims'
    [pscustomobject]@{
      tarea  = if ($r.tarea) { $r.tarea } elseif ($r.area) { "area-$($r.area)" } else { $a.BaseName }
      agente = $r.agente
      fecha  = if ($r.fecha) { $r.fecha } else { $r.hora }
      hilo   = if ($r.hilo) { $r.hilo } elseif ($enHilo) { $a.Directory.Parent.Name } else { $null }
      toca   = if ($r.toca) { $r.toca } elseif ($r.archivos) { @($r.archivos) -join ', ' } else { $null }
      ruta   = $a.FullName
    }
  }
}

# Bandeja de entregas: hilos\<id>\entregas\<tarea>.json. Nunca se borran; archivar solo cambia el estado.
function Mesa-Entregas([switch]$ConArchivadas) {
  foreach ($a in @(Get-ChildItem -Path (Join-Path $Global:Mesa_Hilos '*\entregas\*.json') -ErrorAction SilentlyContinue)) {
    try { $e = Mesa-LeerJson $a.FullName } catch { continue }
    if ($e -and ($ConArchivadas -or $e.estado -ne 'archivada')) { $e }
  }
}

function Mesa-ActualizarHilo($carpetaHilo, [scriptblock]$cambio) {
  $candado = Mesa-BloquearHilo $carpetaHilo
  try {
    $ruta = Join-Path $carpetaHilo 'hilo.json'
    $h = Mesa-LeerJson $ruta
    if ($h) { & $cambio $h; Mesa-EscribirJson $ruta $h }
    return $h
  } finally { $candado.Dispose() }
}

function Mesa-NormalizarHerramienta($destino) {
  if (-not $destino) { return $null }
  switch ($destino.ToLowerInvariant()) {
    'codex'       { return 'codex' }
    'openworker'  { return 'codex' }
    'opencode'    { return 'codex' }
    'agy'         { return 'agy' }
    'antigravity' { return 'agy' }
    'agy-flash'   { return 'agy' }
    'agy-sonnet'  { return 'agy' }
    'claude'      { return 'claude' }
    'claude_nodo' { return 'claude' }
    'claude_code' { return 'claude' }
    default       { return $null }
  }
}

function Mesa-ModeloPorDefecto($herramienta, $cfg) {
  if (-not $herramienta) { return $null }
  if ($cfg -and $cfg.modelos -and $cfg.modelos.$herramienta -and $cfg.modelos.$herramienta.Count -gt 0) {
    return $cfg.modelos.$herramienta[0]
  }
  switch ($herramienta) {
    'codex'    { return 'gpt-6-astra' }
    'agy'      { return 'gemini-3.8-flash-high' }
    'claude'   { return 'sonnet' }
    default    { return $null }
  }
}

function Mesa-ObtenerLlamadas($desde = $null) {
  $vistos = @{}
  $lista = New-Object System.Collections.Generic.List[object]
  if (Test-Path -LiteralPath $Global:Mesa_Registro) {
    foreach ($l in [System.IO.File]::ReadLines($Global:Mesa_Registro, [System.Text.Encoding]::UTF8)) {
      if (-not $l.Trim()) { continue }
      try {
        $r = $l | ConvertFrom-Json
        $f = [DateTime]::Parse($r.fecha)
        if ($desde -and $f -lt $desde) { continue }
        $clave = "$($r.hilo):$($r.n)"
        $vistos[$clave] = $true
        $lista.Add([pscustomobject]@{
          fecha          = $r.fecha
          fecha_dt       = $f
          herramienta    = $r.herramienta
          modelo         = $r.modelo
          hilo           = $r.hilo
          n              = $r.n
          entrada        = $r.entrada
          salida         = $r.salida
          total          = $r.total
          calidad        = $r.calidad
          segundos       = $r.segundos
          salida_proceso = $r.salida_proceso
        })
      } catch {}
    }
  }
  if (Test-Path -LiteralPath $Global:Mesa_Hilos) {
    Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $hiloId = $_.Name
      Get-ChildItem -LiteralPath $_.FullName -Filter '*-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        try {
          $m = Mesa-LeerMensaje $_.FullName
          if ($m -and $m.tipo -eq 'encargo' -and $m.estado -eq 'ejecutando' -and $m.llamada -and $m.llamada.inicio -and $m.herramienta) {
            $clave = "${hiloId}:$($m.n)"
            if (-not $vistos.ContainsKey($clave)) {
              $f = [DateTime]::Parse($m.llamada.inicio)
              if (-not $desde -or $f -ge $desde) {
                $vistos[$clave] = $true
                $lista.Add([pscustomobject]@{
                  fecha          = $m.llamada.inicio
                  fecha_dt       = $f
                  herramienta    = $m.herramienta
                  modelo         = $m.modelo
                  hilo           = $hiloId
                  n              = $m.n
                  entrada        = 0
                  salida         = 0
                  total          = 0
                  calidad        = 'en_curso'
                  segundos       = 0
                  salida_proceso = $m.llamada.salida
                })
              }
            }
          }
        } catch {}
      }
    }
  }
  return ($lista | Sort-Object fecha_dt)
}

function Mesa-ContadoresLlamadas {
  $ahora = Get-Date
  $hace1h = $ahora.AddHours(-1)
  $inicioDia = $ahora.Date
  $llamadas = Mesa-ObtenerLlamadas $inicioDia
  if ($hace1h -lt $inicioDia) {
    $llamadas = Mesa-ObtenerLlamadas $hace1h
  }
  $res = @{
    codex    = @{ hora = 0; dia = 0 }
    agy      = @{ hora = 0; dia = 0 }
    claude   = @{ hora = 0; dia = 0 }
  }
  foreach ($ll in $llamadas) {
    $h = $ll.herramienta
    if (-not $h -or -not $res.ContainsKey($h)) { continue }
    if ($ll.fecha_dt -ge $hace1h) { $res[$h].hora++ }
    if ($ll.fecha_dt -ge $inicioDia) { $res[$h].dia++ }
  }
  return $res
}

function Mesa-AgyGrupoPorModelo($modelo) {
  if (-not $modelo) { return 'flash' }
  if ($modelo -like 'gemini-3.8-flash*') { return 'flash' }
  if ($modelo -like 'gemini-4-argon*')   { return 'argon' }
  if ($modelo -like 'claude-*' -or $modelo -like 'gpt-oss*') { return 'claude_gpt' }
  return 'flash'
}

function Mesa-ConvertirRelativoAIso([string]$rel, [DateTimeOffset]$fechaBase) {
  if (-not $rel) { return $null }
  $rel = $rel.Trim()
  if ($rel -match '^\d{4}-\d{2}-\d{2}') { return $rel }
  $horas = 0
  $mins = 0
  if ($rel -match '(\d+)\s*h') { $horas = [int]$Matches[1] }
  if ($rel -match '(\d+)\s*m') { $mins = [int]$Matches[1] }
  if ($horas -eq 0 -and $mins -eq 0 -and ($rel -match '^\d+$')) {
    $horas = [int]$rel
  }
  return $fechaBase.AddHours($horas).AddMinutes($mins).ToString('yyyy-MM-ddTHH:mm:sszzz')
}
