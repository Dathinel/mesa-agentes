if (!$mesaBase) { $mesaBase = Split-Path -Parent $PSScriptRoot }
if (!$datosDir) { $datosDir = Join-Path $mesaBase 'datos' }
. (Join-Path $mesaBase 'herramientas\comun.ps1')
. (Join-Path $mesaBase 'herramientas\costes.ps1')
$script:metadatos=@{}

# Tokens de Codex desde las sesiones locales (consola interactiva y llamadas de la mesa):
# entrada sin caché + salida del último total de cada sesión escrita en la ventana.
# Una sesión que empezó antes de la ventana cuenta entera: es una aproximación por exceso.
function Codex-TokensDesde([datetime]$Desde) {
  $raiz = Join-Path $env:USERPROFILE '.codex\sessions'
  if (!(Test-Path -LiteralPath $raiz)) { return $null }
  $total = 0L
  foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $Desde })) {
    try {
      $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite')
      $n = [Math]::Min(262144L, $fs.Length); [void]$fs.Seek(-$n, 'End')
      $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n); $fs.Close()
      $m = [regex]::Matches([Text.Encoding]::UTF8.GetString($buf), '"total_token_usage":\{"input_tokens":(\d+),"cached_input_tokens":(\d+)[^}]*"output_tokens":(\d+)')
      if ($m.Count) { $u = $m[$m.Count - 1]; $total += [long]$u.Groups[1].Value - [long]$u.Groups[2].Value + [long]$u.Groups[3].Value }
    } catch {}
  }
  return $total
}

# --- Sesiones: solo metadatos (modelo, herramienta, ruta y fechas), nunca el texto de los mensajes ---

function Estado-Cola([string]$Ruta, [long]$Bytes = 262144) {
  $fs = $null
  try {
    $fs = [IO.File]::Open($Ruta, 'Open', 'Read', 'ReadWrite')
    $n = [Math]::Min($Bytes, $fs.Length); [void]$fs.Seek(-$n, 'End')
    $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n)
    $lineas = @([Text.Encoding]::UTF8.GetString($buf) -split "`n")
    if ($n -lt $fs.Length) { $lineas = @($lineas | Select-Object -Skip 1) }
    return $lineas
  } catch { return @() } finally { if ($fs) { $fs.Dispose() } }
}

function Estado-PrimeraLinea([string]$Ruta) {
  $fs = $null
  try {
    $fs = [IO.File]::Open($Ruta, 'Open', 'Read', 'ReadWrite')
    $n = [int][Math]::Min(65536L, $fs.Length); $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n)
    return ([Text.Encoding]::UTF8.GetString($buf) -split "`n")[0]
  } catch { return '' } finally { if ($fs) { $fs.Dispose() } }
}

# Clasifica un comando sin exponerlo: solo devuelve la categoría.
function Estado-ClaseComando([string]$Cmd) {
  if (!$Cmd) { return $null }
  if ($Cmd -match '(?i)\b(dotnet\s+test|pytest|vitest|jest|Invoke-Pester|cargo\s+test|go\s+test|npm\s+(run\s+)?test|pruebas?\.ps1|tests?\.ps1)\b') { return 'probando' }
  if ($Cmd -match '(?i)\b(dotnet\s+(build|publish)|msbuild|cargo\s+build|npm\s+(run\s+)?build|tsc|cmake|ninja|build(\.ps1|\.cmd|\.sh)?|compilar(\.ps1)?)\b') { return 'compilando' }
  return $null
}

function Claude-Carpetas($cfg) {
  $raiz = Join-Path $env:USERPROFILE '.claude\projects'
  $patrones = @($cfg.claude_proyectos | Where-Object { $_ })
  if (!$patrones.Count) { $patrones = @((($mesaBase -replace '[^A-Za-z0-9]', '-') + '*')) }
  @(Get-ChildItem -LiteralPath $raiz -Directory -ErrorAction SilentlyContinue | Where-Object {
    $n = $_.Name
    $n -notmatch $Global:Mesa_Excluidos -and @($patrones | Where-Object { $n -like $_ }).Count -gt 0
  })
}

# Sesiones principales de Claude (sin subagents\), la más reciente primero.
function Claude-SesionesPrincipales($cfg) {
  @(foreach ($d in (Claude-Carpetas $cfg)) { Get-ChildItem -LiteralPath $d.FullName -File -Filter *.jsonl -ErrorAction SilentlyContinue }) |
    Sort-Object LastWriteTime -Descending
}

# Lee de una cola de JSONL el último modelo y las últimas acciones (solo líneas del asistente).
function Estado-MetaCola([string]$Ruta, [long]$Bytes = 262144) {
  $modelo = $null; $acciones = @()
  foreach ($l in (Estado-Cola $Ruta $Bytes)) {
    if ($l -notmatch '"type":"assistant"|"type":"turn_context"|"function_call"|"custom_tool_call"') { continue }
    try { $e = $l | ConvertFrom-Json } catch { continue }
    $m = (Mesa-Meta $e).modelo; if ($m -and $m -notmatch '^<') { $modelo = $m }
    $acciones += @(Mesa-Acciones $e)
  }
  @{ modelo = $modelo; acciones = $acciones }
}

function Estado-Recorte([string]$s, [int]$max = 60) {
  $s = (($s -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
  if (!$s) { return $null }
  $s = (Mesa-Ocultar $s.Trim())
  if ($s.Length -gt $max) { $s = $s.Substring(0, $max - 1) + '…' }
  $s
}

# Subagentes activos de Claude: agent-*.jsonl escritos hace menos de 3 minutos.
function Claude-Pasantes($cfg) {
  $limite = (Get-Date).AddMinutes(-3); $lista = @()
  foreach ($d in (Claude-Carpetas $cfg)) {
    foreach ($ses in @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) {
      $dirSub = Join-Path $ses.FullName 'subagents'
      if (!(Test-Path -LiteralPath $dirSub)) { continue }
      foreach ($f in @(Get-ChildItem -LiteralPath $dirSub -File -Filter 'agent-*.jsonl' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $limite })) {
        $meta = Mesa-LeerJson ($f.FullName -replace '\.jsonl$', '.meta.json')
        if ($meta -and $meta.finished) { continue }
        $info = Estado-MetaCola $f.FullName 131072
        $tarea = if ($meta -and $meta.description) { [string]$meta.description } else { $null }
        if (!$tarea -and $meta -and $meta.toolUseId) {
          $padre = Join-Path $d.FullName ($ses.Name + '.jsonl')
          if (Test-Path -LiteralPath $padre) {
            $id = [regex]::Escape([string]$meta.toolUseId)
            $m = [regex]::Match((Estado-Cola $padre 4194304) -join "`n", '"id":"' + $id + '","name":"(?:Agent|Task)","input":\{"description":"((?:\\.|[^"\\])*)"')
            if ($m.Success) { try { $tarea = ('"' + $m.Groups[1].Value + '"') | ConvertFrom-Json } catch {} }
          }
        }
        if (!$tarea) {
          # Último recurso: primera línea del encargo, recortada.
          try { $e = (Estado-PrimeraLinea $f.FullName) | ConvertFrom-Json; if ($e.message.content -is [string]) { $tarea = $e.message.content } } catch {}
        }
        $ult = @($info.acciones | Where-Object { $_.tipo -ne 'pasante' } | Select-Object -Last 1)
        $arch = @($info.acciones | Where-Object { $_.tipo -eq 'archivo' } | Select-Object -Last 1)
        $lista += [pscustomobject]@{
          id = $f.BaseName
          modelo = $info.modelo
          tarea = Estado-Recorte $tarea 60
          herramienta = if ($ult.Count) { $ult[0].herramienta } else { $null }
          archivo = if ($arch.Count) { Mesa-Ocultar ([string]$arch[0].valor) } else { $null }
          accion = if ($ult.Count -and $ult[0].tipo -eq 'comando') { Estado-ClaseComando $ult[0].valor } else { $null }
          hora = $f.LastWriteTime.ToString('o')
        }
      }
    }
  }
  @($lista | Sort-Object hora -Descending | Select-Object -First 4)
}

# Codex: solo cuenta como pasante una sesión cuyo session_meta la declara subagente.
function Codex-EsSubagente([string]$Ruta) { (Estado-PrimeraLinea $Ruta) -match '"source":\{"subagent"' }

function Codex-Pasantes {
  $raiz = Join-Path $env:USERPROFILE '.codex\sessions'
  if (!(Test-Path -LiteralPath $raiz)) { return @() }
  $limite = (Get-Date).AddMinutes(-3); $lista = @()
  foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -File -Filter *.jsonl -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $limite })) {
    if (!(Codex-EsSubagente $f.FullName)) { continue }
    $info = Estado-MetaCola $f.FullName 131072
    $ult = @($info.acciones | Where-Object { $_.tipo -ne 'pasante' } | Select-Object -Last 1)
    $arch = @($info.acciones | Where-Object { $_.tipo -eq 'archivo' } | Select-Object -Last 1)
    $lista += [pscustomobject]@{
      id = $f.BaseName; modelo = $info.modelo; tarea = 'Subagente de Codex'
      herramienta = if ($ult.Count) { $ult[0].herramienta } else { $null }
      archivo = if ($arch.Count) { Mesa-Ocultar ([string]$arch[0].valor) } else { $null }
      accion = if ($ult.Count -and $ult[0].tipo -eq 'comando') { Estado-ClaseComando $ult[0].valor } else { $null }
      hora = $f.LastWriteTime.ToString('o')
    }
  }
  @($lista | Sort-Object hora -Descending | Select-Object -First 4)
}

# Archivos tocados hoy por Claude en su alcance (sesión principal y subagentes), sin temporales.
function Claude-ArchivosHoy($cfg) {
  $hoy = (Get-Date).Date; $lista = @()
  $fuentes = @(foreach ($d in (Claude-Carpetas $cfg)) { Get-ChildItem -LiteralPath $d.FullName -Recurse -File -Filter *.jsonl -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $hoy } }) |
    Sort-Object LastWriteTime -Descending | Select-Object -First 8
  foreach ($f in $fuentes) {
    foreach ($a in @((Estado-MetaCola $f.FullName 131072).acciones | Where-Object { $_.tipo -eq 'archivo' })) {
      if ([string]$a.valor -match '(?i)\\AppData\\Local\\Temp\\|/tmp/' -or [string]$a.valor -match $Global:Mesa_Excluidos) { continue }
      $hora = if ($a.hora) { $a.hora } else { $f.LastWriteTime.ToString('o') }
      try { if ([DateTimeOffset]::Parse($hora).LocalDateTime -lt $hoy) { continue } } catch { continue }
      $lista += [pscustomobject]@{ agente = 'claude'; valor = (Mesa-Ocultar ([string]$a.valor)); hora = $hora; operacion = $a.operacion; herramienta = $a.herramienta }
    }
  }
  @($lista | Sort-Object hora -Descending | Group-Object valor | ForEach-Object { $_.Group[0] } | Select-Object -First 6)
}

# --- Datos reales para pizarra, línea de tiempo, noticiero, tokens por hora y póster ---

function Estado-Local($iso) {
  try { [DateTimeOffset]::Parse([string]$iso, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime } catch { $null }
}

function Estado-Corto([string]$s, [int]$max = 70) {
  $s = ((Mesa-Ocultar $s) -replace '\s+', ' ').Trim()
  if ($s.Length -gt $max) { $s = $s.Substring(0, $max - 1) + '…' }
  $s
}

function Estado-Duracion([double]$minutos) {
  $m = [int][Math]::Round($minutos)
  if ($m -ge 60) { '{0} h {1:00} min' -f [Math]::Floor($m / 60), ($m % 60) } else { "$m min" }
}

function Estado-Cifra([double]$n) {
  $es = [Globalization.CultureInfo]::GetCultureInfo('es-ES')
  if ($n -ge 1000000) { ($n / 1000000).ToString('0.0', $es) + ' M' }
  elseif ($n -ge 1000) { ($n / 1000).ToString('0.0', $es) + ' k' }
  else { ([long]$n).ToString($es) }
}

# Tokens de Claude por hora de hoy y por día (7 días): entrada + salida + escritura de caché de message.usage.
function Estado-ClaudeUso {
  if ($script:usoClaude -and ((Get-Date) - $script:usoClaude.t).TotalSeconds -lt 60) { return $script:usoClaude }
  $horas = New-Object 'long[]' 24; $dias = @{}
  $hoy = (Get-Date).Date; $corte = $hoy.AddDays(-6).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')
  foreach ($f in @(Mesa-Sesiones 'claude' | Where-Object { $_.LastWriteTime -ge $hoy.AddDays(-6) })) {
    foreach ($linea in (Mesa-Cola $f.FullName).lineas) {
      $i = $linea.IndexOf('"usage":{'); if ($i -lt 0) { continue }
      if ($linea -notmatch '"timestamp"\s*:\s*"([^"]+)"') { continue }
      $ts = $Matches[1]; if ($ts -lt $corte) { continue }
      $u = $linea.Substring($i); $suma = 0L
      foreach ($c in '"input_tokens":(\d+)', '"cache_creation_input_tokens":(\d+)', '"output_tokens":(\d+)') {
        $m = [regex]::Match($u, $c); if ($m.Success) { $suma += [long]$m.Groups[1].Value }
      }
      $loc = Estado-Local $ts; if (!$loc) { continue }
      $k = $loc.ToString('yyyy-MM-dd'); $dias[$k] = [long]$dias[$k] + $suma
      if ($loc.Date -eq $hoy) { $horas[$loc.Hour] += $suma }
    }
  }
  $script:usoClaude = @{ t = (Get-Date); horas = $horas; dias = $dias }
  $script:usoClaude
}

# Tokens de Codex por hora de hoy: diferencia entre eventos token_count consecutivos de cada sesión.
function Estado-CodexHoras {
  if ($script:horasCodex -and ((Get-Date) - $script:horasCodex.t).TotalSeconds -lt 60) { return $script:horasCodex.h }
  $horas = New-Object 'long[]' 24; $hoy = (Get-Date).Date
  $raiz = Join-Path $env:USERPROFILE '.codex\sessions'
  if (Test-Path -LiteralPath $raiz) {
    foreach ($f in @(Get-ChildItem -LiteralPath $raiz -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $hoy })) {
      $previo = 0L; $fs = $null; $rd = $null
      try {
        $fs = [IO.File]::Open($f.FullName, 'Open', 'Read', 'ReadWrite'); $rd = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        while ($null -ne ($linea = $rd.ReadLine())) {
          if ($linea.IndexOf('"total_token_usage":{"input_tokens"') -lt 0) { continue }
          $m = [regex]::Match($linea, '"total_token_usage":\{"input_tokens":(\d+),"cached_input_tokens":(\d+)[^}]*"output_tokens":(\d+)')
          $t = [regex]::Match($linea, '^\{"timestamp":"([^"]+)"')
          if (!$m.Success -or !$t.Success) { continue }
          $total = [long]$m.Groups[1].Value - [long]$m.Groups[2].Value + [long]$m.Groups[3].Value
          $dif = if ($total -ge $previo) { $total - $previo } else { $total }; $previo = $total
          $loc = Estado-Local $t.Groups[1].Value
          if ($loc -and $loc.Date -eq $hoy -and $dif -gt 0) { $horas[$loc.Hour] += $dif }
        }
      } catch {} finally { if ($rd) { $rd.Dispose() } elseif ($fs) { $fs.Dispose() } }
    }
  }
  $script:horasCodex = @{ t = (Get-Date); h = $horas }
  $horas
}

# Acciones de actividad.jsonl desde una fecha: solo agente, hora y herramienta (nunca el valor).
function Estado-Acciones([datetime]$Desde) {
  $ruta = Join-Path $Global:Mesa_Raiz 'actividad.jsonl'
  if (!(Test-Path -LiteralPath $ruta)) { return @() }
  $clave = "$((Get-Item -LiteralPath $ruta).Length)|$($Desde.Date)"
  if ($script:cacheAcc -and $script:cacheAcc.k -eq $clave) { return $script:cacheAcc.v }
  $pref = @(0..([int]((Get-Date).Date - $Desde.Date).TotalDays + 1) | ForEach-Object { $Desde.Date.AddDays($_ - 1).ToString('yyyy-MM-dd') })
  $lista = New-Object System.Collections.Generic.List[object]
  foreach ($l in [IO.File]::ReadLines($ruta, [Text.Encoding]::UTF8)) {
    if ($l.Length -lt 20) { continue }
    $m = [regex]::Match($l, '"hora":"(\d{4}-\d\d-\d\d)T[^"]*"'); if (!$m.Success -or $m.Groups[1].Value -notin $pref) { continue }
    $a = [regex]::Match($l, '"agente":"([^"]+)"'); $h = [regex]::Match($l, '"herramienta":"([^"]+)"')
    $loc = Estado-Local ($m.Value -replace '^"hora":"|"$', '')
    if ($loc -and $loc -ge $Desde -and $a.Success) { $lista.Add([pscustomobject]@{ agente = $a.Groups[1].Value; dt = $loc; herramienta = $(if ($h.Success) { $h.Groups[1].Value } else { $null }) }) }
  }
  $script:cacheAcc = @{ k = $clave; v = $lista.ToArray() }
  $lista.ToArray()
}

# Tramos: acciones y llamadas registradas, unidas si distan menos de 5 minutos.
function Estado-Tramos($Instantes, $Intervalos) {
  $iv = New-Object System.Collections.Generic.List[object]
  foreach ($d in @($Instantes)) { $iv.Add([pscustomobject]@{ i = $d; f = $d }) }
  foreach ($p in @($Intervalos)) { $iv.Add([pscustomobject]@{ i = $p.i; f = $p.f }) }
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($p in @($iv | Sort-Object i)) {
    $u = if ($res.Count) { $res[$res.Count - 1] } else { $null }
    if ($u -and ($p.i - $u.f).TotalMinutes -lt 5) { if ($p.f -gt $u.f) { $u.f = $p.f } }
    else { $res.Add([pscustomobject]@{ i = $p.i; f = $p.f }) }
  }
  $res.ToArray()
}

function Estado-LineaTiempo($Agentes, $Acciones, $Registro, $Hilos, [datetime]$Ahora) {
  $hoy = $Ahora.Date; $res = @(); $minutosTrabajo = @{}
  foreach ($id in $Agentes) {
    $inst = @($Acciones | Where-Object { $_.agente -eq $id -and $_.dt.Date -eq $hoy } | ForEach-Object { $_.dt })
    $tareas = @($Registro | Where-Object { $_.herramienta -eq $id -and (Estado-Local $_.fecha) -and (Estado-Local $_.fecha).Date -eq $hoy })
    $ivs = @(foreach ($t in $tareas) {
      $ini = Estado-Local $t.inicio; $fin = Estado-Local $t.fin
      if ($ini -and $fin -and $fin -ge $ini) { if ($ini -lt $hoy) { $ini = $hoy }; [pscustomobject]@{ i = $ini; f = $fin } }
    })
    $tr = @(Estado-Tramos $inst $ivs); $tramos = @(); $min = 0.0
    foreach ($p in $tr) {
      $a = [double]$p.i.TimeOfDay.TotalMinutes; $b = [double]$p.f.TimeOfDay.TotalMinutes; $min += ($b - $a)
      $tramos += @{ inicio = $p.i.ToString('HH:mm'); fin = $p.f.ToString('HH:mm'); inicio_pct = [Math]::Round($a / 14.4, 2); ancho_pct = [Math]::Max(0.4, [Math]::Round(($b - $a) / 14.4, 2)) }
    }
    $minutosTrabajo[$id] = $min
    $marcas = @(foreach ($t in ($tareas | Sort-Object fecha)) {
      $f = Estado-Local $t.fecha; $hi = @($Hilos | Where-Object { $_.id -eq $t.hilo } | Select-Object -First 1)
      $nombre = if ($hi.Count -and $hi[0].titulo) { [string]$hi[0].titulo } elseif ($t.hilo) { [string]$t.hilo } else { 'tarea' }
      $dur = if ($t.segundos) { ' · ' + (Estado-Duracion ([double]$t.segundos / 60)) } else { '' }
      @{ hora = $f.ToString('HH:mm'); pct = [Math]::Round($f.TimeOfDay.TotalMinutes / 14.4, 2); titulo = (Estado-Corto "Tarea terminada: $nombre$dur" 80) }
    })
    if ($id -eq 'claude') {
      $marcas = @(foreach ($hi in $Hilos) { foreach ($m in $hi.mensajes) {
        $f = Estado-Local $m.fecha
        if ((Mesa-NormalizarHerramienta $m.autor) -eq 'claude' -and $m.tipo -eq 'encargo' -and $f -and $f.Date -eq $hoy) {
          @{ hora = $f.ToString('HH:mm'); pct = [Math]::Round($f.TimeOfDay.TotalMinutes / 14.4, 2); titulo = (Estado-Corto "Delegó a $(Mesa-NormalizarHerramienta $m.para): $(if ($hi.titulo) { $hi.titulo } else { $hi.id })" 80) }
        } } })
      $marcas = @($marcas | Sort-Object { $_.hora })
    }
    $color = switch ($id) { 'claude' { '#d27e67' } 'codex' { '#5ed3a1' } default { '#4285f4' } }
    $res += @{ id = $id; nombre = $(if ($id -eq 'agy') { 'agy' } else { (Get-Culture).TextInfo.ToTitleCase($id) }); color = $color; tramos = $tramos; marcas = $marcas }
  }
  @{ lineas = $res; minutos = $minutosTrabajo }
}

function Estado-Noticias($Hilos, $Alertas, $Registro, [datetime]$Ahora) {
  $ev = New-Object System.Collections.Generic.List[object]
  $nm = { param($v) $x = Mesa-NormalizarHerramienta $v; if ($x) { $x } else { [string]$v } }
  foreach ($h in $Hilos) {
    $tit = if ($h.titulo) { [string]$h.titulo } else { [string]$h.id }
    foreach ($m in $h.mensajes) {
      $dt = Estado-Local $m.fecha; if (!$dt) { continue }
      $tipo = if ($m.estado -eq 'hecho' -and $m.traspaso -and $m.traspaso.hecho) { 'hecho' } elseif ($m.estado -eq 'fallo') { 'alerta' } else { 'traspaso' }
      $txt = "$(& $nm $m.autor) → $(& $nm $m.para): $($m.tipo) $($m.estado) · $tit"
      $ev.Add([pscustomobject]@{ dt = $dt; tipo = $tipo; texto = (Estado-Corto $txt 110) })
    }
  }
  foreach ($a in $Alertas) {
    if ($a.nivel -ne 'alto') { continue }
    $dt = Estado-Local $a.hora; if (!$dt) { continue }
    $ev.Add([pscustomobject]@{ dt = $dt; tipo = 'vigia'; texto = (Estado-Corto "Vigía: alerta alta de $($a.agente) · $($a.motivo)" 110) })
  }
  foreach ($r in $Registro) {
    $dt = Estado-Local $r.fecha; if (!$dt) { continue }
    $dur = if ($r.segundos) { ' en ' + (Estado-Duracion ([double]$r.segundos / 60)) } else { '' }
    $ev.Add([pscustomobject]@{ dt = $dt; tipo = 'hecho'; texto = (Estado-Corto "$($r.herramienta) terminó tarea con $($r.modelo)$dur" 110) })
  }
  # Eventos idénticos seguidos (p. ej. la misma alerta repetida) se juntan con su cuenta.
  $col = New-Object System.Collections.Generic.List[object]
  foreach ($e in @($ev | Sort-Object dt)) {
    $u = if ($col.Count) { $col[$col.Count - 1] } else { $null }
    if ($u -and $u.base -eq $e.texto -and ($e.dt - $u.dt).TotalMinutes -lt 15) { $u.n++; $u.dt = $e.dt }
    else { $col.Add([pscustomobject]@{ dt = $e.dt; tipo = $e.tipo; base = $e.texto; n = 1 }) }
  }
  foreach ($c in $col) { $c | Add-Member texto $(if ($c.n -gt 1) { "$($c.base) (×$($c.n))" } else { $c.base }) -Force }
  $ult = @($col | Sort-Object dt -Descending | Select-Object -First 12 | Sort-Object dt)
  @($ult | ForEach-Object { @{ hora = $(if ($_.dt.Date -eq $Ahora.Date) { $_.dt.ToString('HH:mm') } else { $_.dt.ToString('dd/MM HH:mm') }); texto = $_.texto; tipo = $_.tipo } })
}

# Estado de un encargo: hecho, fallido, pendiente o abandonado (sin respuesta y con más de 6 h).
function Estado-EstadoEncargo($m, $Mensajes, [string]$Dest) {
  $fm = Estado-Local $m.fecha
  $respuesta = @($Mensajes | Where-Object {
    $_.n -ne $m.n -and (Estado-Local $_.fecha) -ge $fm -and (((Mesa-NormalizarHerramienta $_.autor) -eq $Dest -and ($_.estado -eq 'hecho' -or $_.traspaso)) -or ($_.autor -eq $m.autor -and $_.tipo -eq 'respuesta' -and $_.estado -eq 'hecho'))
  })
  $ll = $m.llamada
  if ($m.estado -eq 'hecho' -or $respuesta.Count -or ($ll -and $ll.fin -and $null -ne $ll.salida -and [int]$ll.salida -eq 0)) { return 'hecho' }
  if ($m.estado -eq 'fallo' -or ($ll -and $ll.fin -and $null -ne $ll.salida -and [int]$ll.salida -ne 0)) { return 'fallido' }
  if ($m.estado -in @('pendiente','aprobado','ejecutando') -and $fm -and ((Get-Date) - $fm).TotalHours -lt 6) { return 'pendiente' }
  'abandonado'
}

# Pasos del plan: encargos recibidos en el hilo más reciente del agente, más lo que falta de su última respuesta.
function Estado-PasosPlan([string]$Id, $Hilos) {
  $norm = { param($v) $x = Mesa-NormalizarHerramienta $v; if ($x) { $x } else { [string]$v } }
  $h = @($Hilos | Where-Object {
    (& $norm $_.lider) -eq $Id -or @($_.participantes | Where-Object { (& $norm $_) -eq $Id }).Count -or
    @($_.mensajes | Where-Object { (& $norm $_.autor) -eq $Id -or (& $norm $_.para) -eq $Id }).Count
  } | Select-Object -First 1)
  # Encargos enviados en las últimas 24 h, de todos los hilos (más recientes primero, hasta 8).
  $enviados = @(); $lim = (Get-Date).AddHours(-24)
  foreach ($hi in $Hilos) { foreach ($m in $hi.mensajes) {
    $fm = Estado-Local $m.fecha; $dest = & $norm $m.para
    if ($m.tipo -ne 'encargo' -or (& $norm $m.autor) -ne $Id -or $dest -eq $Id -or !$fm -or $fm -lt $lim) { continue }
    $est = Estado-EstadoEncargo $m $hi.mensajes $dest
    if ($est -eq 'abandonado') { continue }

    $tit = if ($hi.titulo) { [string]$hi.titulo } elseif ($m.encargo) { ([IO.Path]::GetFileNameWithoutExtension([string]$m.encargo)) -replace '[-_]+', ' ' } else { [string]$hi.id }
    $enviados += [pscustomobject]@{ dt = $fm; paso = @{ texto = (Estado-Corto "$(if ($est -eq 'fallido') { '✗ ' })${dest}: $tit"); completado = ($est -eq 'hecho'); fallido = ($est -eq 'fallido') } }
  } }
  $enviados = @($enviados | Sort-Object dt -Descending | Select-Object -First 8 | ForEach-Object { $_.paso })
  if (!$h.Count) { return $enviados }
  $ms = @($h[0].mensajes | Sort-Object fecha); $pasos = @()
  foreach ($m in $ms) {
    if ($m.tipo -ne 'encargo' -or (& $norm $m.para) -ne $Id) { continue }
    $fm = Estado-Local $m.fecha
    $est = Estado-EstadoEncargo $m $ms $Id
    if ($est -eq 'abandonado') { continue }

    $nombre = if ($m.encargo) { ([IO.Path]::GetFileNameWithoutExtension([string]$m.encargo)) -replace '[-_]+', ' ' } else { [string]$m.texto }
    $pasos += @{ texto = (Estado-Corto "$(if ($est -eq 'fallido') { '✗ ' })Encargo: $nombre"); completado = ($est -eq 'hecho'); fallido = ($est -eq 'fallido') }
  }
  $ult = @($ms | Where-Object { (& $norm $_.autor) -eq $Id -and $_.tipo -eq 'respuesta' -and $_.traspaso } | Select-Object -Last 1)
  if ($ult.Count -and $ult[0].traspaso.falta) {
    $n = 0
    foreach ($l in ([string]$ult[0].traspaso.falta -split '\r?\n' | ForEach-Object { $_ -split '(?<=[.;])\s+' })) {
      $t = ($l -replace '^[\s\-\*•\d\.\)]+', '').Trim()
      if ($t.Length -lt 4 -or $t -match '^(?i)(ninguna?|nada|n/a)\W*$' -or $t -match 'node\.exe\s*:|NativeCommandError|CategoryInfo|^En línea|^At line') { continue }
      if ($n -ge 6) { break }; $n++
      $pasos += @{ texto = (Estado-Corto $t); completado = $false }
    }
  }
  @($enviados) + @($pasos)
}

function Obtener-EstadoCompleto {
  $now=Get-Date
  $cfg=Mesa-LeerJson (Join-Path $datosDir 'mesa.json')
  $catalogo=Mesa-LeerJson (Join-Path $datosDir 'personajes.json')
  $cuota=Mesa-LeerJson $Global:Mesa_CuotaEstado
  $hilos=@(); $pendientes=@(); $tareas=@{}
  foreach ($dir in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue)) {
    $h=try { Mesa-LeerJson (Join-Path $dir.FullName 'hilo.json') } catch { $null }
    # Un hilo.json dañado no esconde el hilo ni sus pendientes: se muestra como dañado.
    if (!$h) { $h=[pscustomobject]@{ id=$dir.Name; titulo='Hilo dañado: hilo.json no se puede leer'; lider=$null; participantes=@(); estado='dañado'; actualizado=(Mesa-IsoNow) } }
    $mensajes=@()
    foreach ($f in @(Get-ChildItem -LiteralPath $dir.FullName -Filter '*-*.json' | Sort-Object Name)) {
      try {
        $m=Mesa-LeerJson $f.FullName
        $m | Add-Member hilo $h.id -Force
        $mensajes+=$m
        if ($m.estado -eq 'pendiente') { $pendientes+=$m }
        if ($m.estado -eq 'ejecutando') { $tareas[(Mesa-NormalizarHerramienta $m.para)]=$m }
      } catch {}
    }
    $h | Add-Member mensajes $mensajes -Force
    $hilos+=$h
  }
  $hilos=@($hilos | Sort-Object actualizado -Descending)
  $reg=@(Mesa-RegistroLocal $Global:Mesa_Registro | Where-Object { $_.calidad -ne 'simulado' })
  $archivos=@(Mesa-Actividades 24)
  # El archivador muestra 80 alertas; acotar también ráfagas dentro de las 72 horas.
  $alertas=@(Mesa-Alertas 72 | Sort-Object { [DateTimeOffset]::Parse($_.hora) } -Descending | Select-Object -First 10 | Select-Object id,agente,hora,nivel,motivo,revisada)
  $acciones7=@(Estado-Acciones $now.Date.AddDays(-6))
  $usoClaude=Estado-ClaudeUso
  $horasCodex=Estado-CodexHoras
  $lt=Estado-LineaTiempo @('claude','codex','agy') $acciones7 $reg $hilos $now
  # Claude no escribe en el registro de tokens: sus tareas son los encargos que delegó y quedaron resueltos.
  $delegadas=@(foreach ($hi in $hilos) { foreach ($m in $hi.mensajes) {
    if ((Mesa-NormalizarHerramienta $m.autor) -eq 'claude' -and $m.tipo -eq 'encargo' -and (Mesa-NormalizarHerramienta $m.para) -ne 'claude' -and $m.estado -in @('hecho','fallo')) { [pscustomobject]@{ dia=(Estado-Local $m.fecha).Date; ok=($m.estado -eq 'hecho') } }
  } })
  $procs=@()
  try { $procs=@(Get-CimInstance Win32_Process -Property Name,ProcessId,ParentProcessId,CommandLine -ErrorAction Stop) } catch {
    $procs=@(Get-Process -Name claude,codex,agy -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Name=($_.ProcessName+'.exe'); ProcessId=$_.Id; ParentProcessId=0 } })
  }

  # Calcular tokens de Claude si no están en cuota
  $claudeTokensHoy = if ($cuota -and $cuota.claude -and $cuota.claude.tokens_hoy) { [long]$cuota.claude.tokens_hoy } else { $null }
  $claudeTokens5h  = if ($cuota -and $cuota.claude -and $cuota.claude.tokens_5h)  { [long]$cuota.claude.tokens_5h }  else { $null }
  $claudeTokens7d  = if ($cuota -and $cuota.claude -and $cuota.claude.tokens_7d)  { [long]$cuota.claude.tokens_7d }  else { $null }
  $claudeCacheReadHoy = if ($cuota -and $cuota.claude -and $cuota.claude.cache_read_hoy) { [long]$cuota.claude.cache_read_hoy } else { $null }
  $claudeCacheRead5h  = if ($cuota -and $cuota.claude -and $cuota.claude.cache_read_5h)  { [long]$cuota.claude.cache_read_5h }  else { $null }
  $claudeCacheRead7d  = if ($cuota -and $cuota.claude -and $cuota.claude.cache_read_7d)  { [long]$cuota.claude.cache_read_7d }  else { $null }

  $agentes=@()
  foreach ($id in @('claude','codex','agy')) {
    $modelo=$null; $esfuerzo=$null; $ultima=$null; $pasantes=0; $estado='apagado'; $origen='configuración'
    # codex corre como node.exe con su script; claude en mayúsculas es la app de escritorio, no la CLI.
    $vivos=@($procs | Where-Object { if ($id -eq 'codex') { $_.Name -eq 'codex.exe' -or ($_.Name -eq 'node.exe' -and "$($_.CommandLine)" -match '@openai[\\/]codex') } else { $_.Name -ceq "$id.exe" } })
    if ($vivos.Count) { $estado='esperando' }
    # Sesión principal: el modelo y la última acción salen de ella, nunca de un subagente.
    $f=@(switch ($id) {
      'claude' { @(Claude-SesionesPrincipales $cfg | Select-Object -First 1) }
      'codex'  { @(Mesa-Sesiones 'codex' | Select-Object -First 12 | Where-Object { !(Codex-EsSubagente $_.FullName) } | Select-Object -First 1) }
      default  { @(Mesa-Sesiones $id | Select-Object -First 1) }
    })
    $listaPasantes=@(switch ($id) { 'claude' { Claude-Pasantes $cfg }; 'codex' { Codex-Pasantes } })
    if ($f.Count) {
      $f=$f[0]; $cache=$script:metadatos[$f.FullName]
      if ($cache) { $modelo=$cache.modelo; $esfuerzo=$cache.esfuerzo; if ($modelo) { $origen='sesión (última observación)' } }
      $acciones=@(); $completados=@{}
      foreach ($e in @(Mesa-Jsonl $f.FullName)) {
        $meta=Mesa-Meta $e
        if ($meta.modelo) { $modelo=$meta.modelo; $origen='sesión' }
        if ($meta.esfuerzo) { $esfuerzo=$meta.esfuerzo }
        $acciones+=@(Mesa-Acciones $e)
        foreach ($b in @($e.message.content)) { if ($b.type -eq 'tool_result') { $completados[[string]$b.tool_use_id]=$true } }
      }
      $script:metadatos[$f.FullName]=@{ modelo=$modelo; esfuerzo=$esfuerzo }
      $acts=@($acciones | Where-Object { $_.tipo -ne 'pasante' } | Select-Object -Last 1)
      if ($acts.Count) {
        $a=$acts[0]
        if (!$a.hora) { $a.hora=$f.LastWriteTime.ToString('o') }
        $ultima=@{ herramienta=$a.herramienta; archivo=if ($a.tipo -eq 'archivo') { Mesa-Ocultar $a.valor } else { $null }; hora=$a.hora; operacion=$a.operacion; accion=if ($a.tipo -eq 'comando') { Estado-ClaseComando $a.valor } else { $null } }
      }
      if ($f.LastWriteTime -ge $now.AddMinutes(-2)) {
        $estado='pensando'
        if ($ultima -and [DateTimeOffset]::Parse($ultima.hora) -ge [DateTimeOffset]::Now.AddMinutes(-2)) {
          $estado=if ($ultima.accion) { $ultima.accion } elseif ($ultima.operacion -eq 'lectura') { 'leyendo' } else { 'escribiendo' }
        }
      }
    }
    # Pasantes: solo subagentes con sesión propia escrita hace menos de 3 minutos.
    $pasantes=$listaPasantes.Count
    if ($pasantes -and $estado -eq 'apagado') { $estado='esperando' }
    if ($tareas[$id] -and $estado -in @('apagado','esperando')) { $estado='pensando' }
    if (!$modelo -and $tareas[$id]) { $modelo=$tareas[$id].modelo; $origen='encargo' }
    if (!$modelo) { $modelo=Mesa-ModeloPorDefecto $id $cfg }
    if (!$esfuerzo -and $tareas[$id]) { $esfuerzo=$tareas[$id].esfuerzo }
    $personaje=@($catalogo.modelos | Where-Object {
      $_.agente -eq $id -and @($_.patrones | Where-Object { $modelo -like $_ }).Count -gt 0
    } | Select-Object -First 1)
    $personaje=if ($personaje.Count) { $personaje[0] } else { $catalogo.defecto }
    $r=@($reg | Where-Object { $_.herramienta -eq $id -and [DateTimeOffset]::Parse($_.fecha).LocalDateTime -ge $now.Date.AddDays(-6) })
    $hoy=@($r | Where-Object { [DateTimeOffset]::Parse($_.fecha).LocalDateTime.Date -eq $now.Date })
    $exito=@($r | Where-Object { $null -ne $_.salida_proceso -and $_.salida_proceso -eq 0 })
    $serie=@(); for ($d=6; $d -ge 0; $d--) {
      $dia=$now.Date.AddDays(-$d)
      $diarias=@($r | Where-Object { [DateTimeOffset]::Parse($_.fecha).LocalDateTime.Date -eq $dia })
      $tokensDia = [long](($diarias | Measure-Object total -Sum).Sum)
      if ($id -eq 'claude') {
        $tokensDia = [long]$usoClaude.dias[$dia.ToString('yyyy-MM-dd')]
        $diarias = @($delegadas | Where-Object { $_.dia -eq $dia })
      }
      $serie+=@{ dia=$dia.ToString('yyyy-MM-dd'); tareas=$diarias.Count; tokens=$tokensDia }
    }
    # Tareas reales: registro de tokens (codex, agy) o encargos delegados (claude).
    if ($id -eq 'claude') {
      $nHoy=@($delegadas | Where-Object { $_.dia -eq $now.Date }); $n7=@($delegadas | Where-Object { $_.dia -ge $now.Date.AddDays(-6) })
      $nOk7=@($n7 | Where-Object ok); $nFallHoy=@($nHoy | Where-Object { !$_.ok }).Count
    } else {
      $nHoy=$hoy; $n7=$r; $nOk7=$exito; $nFallHoy=@($hoy | Where-Object { $null -ne $_.salida_proceso -and $_.salida_proceso -ne 0 }).Count
    }
    $coste=Mesa-CosteModelo $id $modelo $reg
    $sem=$null; $cinco=$null; $reinicio=$null; $reinicio5=$null; $calidad='estimado'; $fechaCuota=$null
    if ($id -eq 'codex') {
      if ($null -ne $cuota.codex.semanal_libre_pct) {
        $sem = [double]$cuota.codex.semanal_libre_pct
      } elseif ($null -ne $cuota.codex.semanal_usado_pct) {
        $sem = 100 - [double]$cuota.codex.semanal_usado_pct
      }
      if ($null -ne $cuota.codex.cinco_horas_libre_pct) {
        $cinco = [double]$cuota.codex.cinco_horas_libre_pct
      } elseif ($null -ne $cuota.codex.cinco_horas_usado_pct) {
        $cinco = 100 - [double]$cuota.codex.cinco_horas_usado_pct
      }
      $reinicio = $cuota.codex.semanal_reinicia
      $reinicio5 = $cuota.codex.cinco_horas_reinicia
      $calidad = if ($cuota.codex.calidad) { $cuota.codex.calidad } else { 'oficial' }
      $fechaCuota = $cuota.codex.observado
      if ($reinicio5 -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio5)) {
        $cinco = 100.0
        $calidad = 'oficial (tras reinicio)'
      }
      if ($reinicio -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio)) {
        $sem = 100.0
        $calidad = 'oficial (tras reinicio)'
      }
    } elseif ($id -eq 'claude') {
      $foto=@(Mesa-RegistroLocal $Global:Mesa_CuotaFotos | Where-Object grupo -eq 'claude' | Select-Object -Last 1)
      if ($foto.Count) { $reinicio=$foto[0].reinicia_semanal; $reinicio5=$foto[0].reinicia_5h }
      $fechaCuota = if ($cuota -and $cuota.claude) { $cuota.claude.fecha_foto } else { $foto[0].fecha }

      if ($reinicio -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio)) {
        $sem = if ($cuota -and $cuota.claude -and $null -ne $cuota.claude.semanal_libre_pct_estimado) { [double]$cuota.claude.semanal_libre_pct_estimado } else { 100.0 }
      } else {
        $sem = if ($cuota -and $cuota.claude -and $null -ne $cuota.claude.semanal_libre_pct_estimado) { [double]$cuota.claude.semanal_libre_pct_estimado } else { 100.0 }
      }

      if ($foto.Count -and $null -ne $foto[0].cinco_h_libre_pct) {
        $cinco = [double]$foto[0].cinco_h_libre_pct
      } else {
        $cinco = [Math]::Max(1.0, [Math]::Min(100.0, [Math]::Round(100.0 - ($claudeTokens5h / 15375.0), 1)))
      }
      if ($reinicio5 -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio5)) {
        $cinco = 100.0
      }
    } else {
      $grupo=Mesa-AgyGrupoPorModelo $modelo; $g=$cuota.agy.grupos.$grupo
      $sem=$g.libre_pct_estimado; $cinco=$g.cinco_h_libre_pct_estimado; $reinicio=$g.reinicia_semanal; $reinicio5=$g.reinicia_5h; $fechaCuota=$g.fecha_foto
      if ($reinicio -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio)) {
        if ($sem -eq $null -or $sem -lt 100) { $sem = if ($g.libre_pct_estimado) { $g.libre_pct_estimado } else { 100.0 } }
      }
      if ($reinicio5 -and [DateTimeOffset]::Now -ge [DateTimeOffset]::Parse($reinicio5)) {
        if ($cinco -eq $null -or $cinco -lt 100) { $cinco = if ($g.cinco_h_libre_pct_estimado) { $g.cinco_h_libre_pct_estimado } else { 100.0 } }
      }
      if (!$coste.n -and $g.coste_por_tarea) { $coste.media=$g.coste_por_tarea; $coste.calidad='semilla sin muestras' }
    }
    # 5 h agotada: descansa hasta su reinicio (la energía sigue siendo la semanal).
    $vuelve=$null
    if ($null -ne $cinco -and $cinco -le 0.5 -and $reinicio5) {
      try { if ([DateTimeOffset]::Parse($reinicio5) -gt [DateTimeOffset]::Now) { $vuelve=$reinicio5; $estado='descansando' } } catch {}
    }
    $restantes=if ($coste.media -gt 0 -and $null -ne $sem) { [Math]::Floor($sem/$coste.media) } else { $null }
    $tasa=if ($n7.Count) { [Math]::Round(100*$nOk7.Count/$n7.Count) } else { $null }
    $prevision=$null
    $costesHoy=@($hoy | Where-Object { $null -ne $_.coste_pct })
    $consumo=[double](($costesHoy | Measure-Object coste_pct -Sum).Sum)
    if ($consumo -gt 0 -and $null -ne $sem) { $prevision=$now.AddDays($sem/$consumo).ToString('yyyy-MM-dd') }
    $operacionAnimada = if ($estado -in @('apagado','descansando')) { $estado } else { 'esperando' }
    if ($estado -notin @('apagado','descansando') -and $ultima) {
      $h = [string]$ultima.herramienta
      $arc = [string]$ultima.archivo
      $op = [string]$ultima.operacion
      if ($h -match 'replace_file_content|apply_patch|Edit|edit') {
        $operacionAnimada = 'editando archivos'
      } elseif ($h -match 'write_to_file|Write|Set-Content|Out-File' -or ($op -eq 'escritura' -and $arc)) {
        $operacionAnimada = 'escribiendo'
      } elseif ($h -match 'Read|view_file|read_file|cat|head|Get-Content' -or $op -eq 'lectura') {
        $operacionAnimada = 'leyendo'
      } elseif ($arc -match 'Copy-Item|Move-Item|cp|mv|git') {
        $operacionAnimada = 'moviendo archivos'
      } elseif ($h -match 'exec_command|run_command|Bash|PowerShell' -or $arc -match 'test|build|cargo|node|npm|dotnet|pytest|validar|probar') {
        $operacionAnimada = 'ejecutando pruebas o compilando'
      }
    } elseif ($estado -eq 'leyendo') {
      $operacionAnimada = 'leyendo'
    } elseif ($estado -eq 'escribiendo') {
      $operacionAnimada = 'escribiendo'
    } elseif ($estado -eq 'pensando') {
      $operacionAnimada = 'ejecutando pruebas o compilando'
    }

    $pasos = @(Estado-PasosPlan $id $hilos)

    $carpetas = @()
    foreach ($hi in $hilos) {
      foreach ($m in $hi.mensajes) {
        if ($m.para -eq $id -and $m.traspaso) {
          # La nota del corcho muestra el «hecho» real del traspaso; si no lo hay, el título del hilo.
          $hechoReal = if ($m.traspaso.hecho -and [string]$m.traspaso.hecho -notmatch '^(?i)s*(mensaje registrado|autoaprobad)') { [string]$m.traspaso.hecho } else { $null }
          $resumen = if ($hechoReal) { $hechoReal } elseif ($hi.titulo) { [string]$hi.titulo } else { [string]$hi.id }
          # Incidencia: salida distinta de 0 o texto con error/exception/failed; los «warning:» de la CLI no lo son.
          $ref = (("$resumen $($m.texto)") -replace 'NativeCommandError|FullyQualifiedErrorId\s*:\s*\w+|CategoryInfo\s*:[^\r\n]*', '')
          $esIncidencia = (($m.llamada -and $m.llamada.fin -and $null -ne $m.llamada.salida -and [int]$m.llamada.salida -ne 0) -or $ref -match '(?i)\b(errors?|exceptions?|failed)\b')
          $carpetas += @{
            de = $m.autor
            para = $m.para
            hora = $m.fecha
            resumen = $resumen
            hecho = if ($hechoReal -and $hechoReal.Length -gt 250) { $hechoReal.Substring(0, 247) + '...' } else { $hechoReal }
            falta = if ($m.traspaso.falta) { $fal = [string]$m.traspaso.falta; if ($fal.Length -gt 150) { $fal.Substring(0, 147) + '...' } else { $fal } } else { 'Ninguna' }
            hilo = $hi.id
            titulo = $hi.titulo
            archivos = @($m.traspaso.archivos | Select-Object -First 5)
            tipo = if ($esIncidencia) { 'incidencia' } else { 'traspaso' }
          }
        }
      }
    }
    # Ordenar: traspasos normales primero, incidencias señaladas
    $carpetas = @($carpetas | Sort-Object { if ($_.tipo -eq 'incidencia') { 1 } else { 0 } } | Select-Object -First 4)

    $archivados = @()
    foreach ($hi in $hilos) {
      foreach ($m in $hi.mensajes) {
        if (($m.autor -eq $id -or $m.para -eq $id) -and ($m.estado -eq 'hecho' -or ($m.traspaso -and $m.traspaso.hecho))) {
          $tit = if ($hi.titulo) { $hi.titulo } else { $hi.id }
          if ($tit.Length -gt 45) { $tit = $tit.Substring(0,42)+'...' }
          $archivados += @{
            hilo = $hi.id
            titulo = $tit
            autor = $m.autor
            hora = $m.fecha
            hecho = if ($m.traspaso.hecho) { $h = [string]$m.traspaso.hecho; if ($h.Length -gt 120) { $h.Substring(0, 117) + '...' } else { $h } } else { $t = [string]$m.texto; if ($t.Length -gt 120) { $t.Substring(0, 117) + '...' } else { $t } }
          }
        }
      }
    }
    $archivados = @($archivados | Select-Object -First 6)

    # Últimos 6 archivos tocados hoy
    # Claude: solo su alcance (claude_proyectos), leído de sus sesiones; los demás, del registro de actividad.
    # if desenrolla las listas: sin @() externo, un solo archivo llegaba como objeto y rompía los despachos.
    $ultimos6 = @(if ($id -eq 'claude') { @(Claude-ArchivosHoy $cfg) } else { @($archivos | Where-Object { $_.agente -eq $id -and [DateTimeOffset]::Parse($_.hora).LocalDateTime.Date -eq $now.Date } | Select-Object -First 6) })

    # Hilo en el que trabaja: el del encargo en ejecución o el más reciente en que participa.
    $hiloObj = @(if ($tareas[$id]) { @($hilos | Where-Object { $_.id -eq $tareas[$id].hilo } | Select-Object -First 1) } else { @() })
    if (!$hiloObj.Count) { $hiloObj = @($hilos | Where-Object { @($_.mensajes | Where-Object { (Mesa-NormalizarHerramienta $_.autor) -eq $id -or (Mesa-NormalizarHerramienta $_.para) -eq $id }).Count } | Select-Object -First 1) }
    $hiloActual = if ($hiloObj.Count) { if ($hiloObj[0].titulo) { [string]$hiloObj[0].titulo } else { [string]$hiloObj[0].id } } else { $null }


    # Tokens por hora de hoy (24 barras de 00 a 23) desde las fuentes reales de cada agente.
    $tokensPorHora = @(0)*24
    if ($id -eq 'claude') { for ($i=0; $i -lt 24; $i++) { $tokensPorHora[$i] = [long]$usoClaude.horas[$i] } }
    elseif ($id -eq 'codex') { for ($i=0; $i -lt 24; $i++) { $tokensPorHora[$i] = [long]$horasCodex[$i] } }
    else { foreach ($x in $hoy) { $f = Estado-Local $x.fecha; if ($f) { $tokensPorHora[$f.Hour] += [long]$x.total } } }

    $tiempoHoy = Estado-Duracion $lt.minutos[$id]
    # Muestras para calibrar
    $calibracionTexto = if ($coste.n -ge 3) {
      "calibrado ($($coste.n) tareas)"
    } elseif ($coste.n -gt 0) {
      "faltan $(3 - $coste.n) tareas para estimar"
    } elseif ($id -eq 'claude') {
      "calibrado por foto oficial semanal"
    } else {
      "faltan 2 tareas para estimar"
    }

    $tokHoy = if ($id -eq 'claude') { $claudeTokensHoy } elseif ($id -eq 'codex') { Codex-TokensDesde $now.Date } else { [long](($hoy | Measure-Object total -Sum).Sum) }
    $tok5h = if ($id -eq 'claude') { $claudeTokens5h } elseif ($id -eq 'codex') { Codex-TokensDesde $now.AddHours(-5) } else { [long]((@($r | Where-Object { [DateTimeOffset]::Parse($_.fecha).LocalDateTime -ge $now.AddHours(-5) }) | Measure-Object total -Sum).Sum) }
    $tok7d = if ($id -eq 'claude') { $claudeTokens7d } elseif ($id -eq 'codex') { Codex-TokensDesde $now.AddDays(-7) } else { [long](($r | Measure-Object total -Sum).Sum) }

    # Póster: semana real (tareas hechas, tokens de 7 días y lo más usado).
    $uso7 = @($acciones7 | Where-Object { $_.agente -eq $id -and $_.herramienta } | Group-Object herramienta | Sort-Object Count -Descending | Select-Object -First 1)
    if ($uso7.Count) { $masUsada = "$($uso7[0].Name) lo más usado" }
    else {
      $mod7 = @($r | Where-Object { $_.modelo } | Group-Object modelo | Sort-Object Count -Descending | Select-Object -First 1)
      $masUsada = if ($mod7.Count) { "$($mod7[0].Name) lo más usado" } else { 'sin uso registrado' }
    }
    $icono = switch ($id) { 'claude' { 'ajedrez' } 'codex' { 'terminal' } default { 'cohete' } }
    $colorPoster = switch ($id) { 'claude' { '#d27e67' } 'codex' { '#5ed3a1' } default { '#4285f4' } }
    $poster = @{
      lema = if ($n7.Count) { "$($nOk7.Count) de $($n7.Count) tareas en 7 días" } else { 'Sin tareas esta semana' }
      sublema = "$(Estado-Cifra ([double]$tok7d)) tokens · $masUsada"
      icono = $icono
      color = $colorPoster
    }

    # Despacho persistente (Item 1)
    $despachoRuta = Join-Path $Global:Mesa_Raiz "despachos\$id.json"
    $despachoObj = if (Test-Path -LiteralPath $despachoRuta) { Mesa-LeerJson $despachoRuta } else { $null }

    # Calibración matemática (Item 3)
    $calibracionObj = $null
    $rutaCalibracion = Join-Path $Global:Mesa_Raiz 'cuota-calibracion.json'
    if (Test-Path -LiteralPath $rutaCalibracion) {
      $calJson = Mesa-LeerJson $rutaCalibracion
      if ($calJson -and $calJson.agentes -and $calJson.agentes.$id) {
        $calibracionObj = $calJson.agentes.$id
      }
    }
    if (!$calibracionObj) {
      $calibracionObj = [ordered]@{
        coste_medio      = $coste.media
        margen           = $coste.margen
        n                = $coste.n
        tareas_restantes = $restantes
        r_min            = $null
        r_max            = $null
        k_estimado       = $null
        calidad          = if ($coste.n -ge 2) { 'calibrado' } else { 'respaldo' }
      }
    }

    # El estado de la mesa lo decide el supervisor (docs\estado-contrato.md); aquí solo queda el detalle de la animación.
    $contrato = Mesa-LeerJson (Join-Path $Global:Mesa_Raiz "agentes\$id.json")
    $estadoDetalle = $estado
    $estado = if ($contrato -and $contrato.estado) { [string]$contrato.estado } else { 'libre' }
    if ($estado -eq 'sin-cuota' -and $contrato.hasta) { $vuelve = $contrato.hasta }

    $agentes+=@{
      estado_detalle=$estadoDetalle; motivo=if ($contrato) { $contrato.motivo } else { 'sin datos del supervisor' }; desde=if ($contrato) { $contrato.desde } else { $null }
      alerta=if ($contrato) { $contrato.alerta } else { $null }
      despacho=$despachoObj
      calibracion=$calibracionObj
      operacion_animada=$operacionAnimada; pasos_plan=$pasos; carpetas=$carpetas; archivados=$archivados
      id=$id; nombre=if ($id -eq 'agy') { 'agy' } else { (Get-Culture).TextInfo.ToTitleCase($id) }
      modelo=$modelo; modelo_fuente=$origen; esfuerzo=$esfuerzo; personaje=$personaje; estado=$estado; online=($estado -in @('trabajando','libre','esperando-daniel'))
      plan=if ($tareas[$id]) { $tareas[$id].texto } else { 'Sin encargo en ejecución' }; ultima=$ultima; pasantes=[Math]::Min(4,$pasantes); pasantes_lista=$listaPasantes; hilo_actual=$hiloActual; vuelve=$vuelve
      archivos=$ultimos6
      ultimos_archivos=$ultimos6
      tiempo_trabajado_hoy=$tiempoHoy
      calibracion_mensaje=$calibracionTexto
      tokens_por_hora=$tokensPorHora
      poster=$poster
      estadisticas=@{
        hoy=$nHoy.Count
        dias7=$n7.Count
        exitos7=$nOk7.Count
        tasa=$tasa
        coste=$coste
        serie=$serie
        tokens_hoy=$tokHoy
        tokens_5h=$tok5h
        tokens_7d=$tok7d
        cache_read_hoy=if ($id -eq 'claude') { $claudeCacheReadHoy } else { 0L }
        cache_read_5h=if ($id -eq 'claude') { $claudeCacheRead5h } else { 0L }
        cache_read_7d=if ($id -eq 'claude') { $claudeCacheRead7d } else { 0L }
        hechas_hoy=$nHoy.Count - $nFallHoy
        fallidas_hoy=$nFallHoy
      }
      energia=@{
        semanal=$sem
        cinco_h=$cinco
        efectiva=if ($null -ne $sem) { $sem } else { $cinco }
        vuelve=$vuelve
        calidad=$calidad
        fecha=$fechaCuota
        reinicio=$reinicio
        reinicio5=$reinicio5
        tareas=$restantes
        prevision=$prevision
        tokens_5h=$tok5h
        tokens_hoy=$tokHoy
      }
      alertas=@($alertas | Where-Object { $_.agente -eq $id -and $_.nivel -eq 'alto' -and !$_.revisada })
    }
  }

  $lineaTiempo = $lt.lineas
  $noticias = Estado-Noticias $hilos $alertas $reg $now

  $ganador=@($agentes | Where-Object { $_.estadisticas.exitos7 -gt 0 } | Sort-Object { $_.estadisticas.exitos7 } -Descending | Select-Object -First 1)
  return @{
    actualizado=if ($hilos -and $hilos.Count -and $hilos[0].actualizado) { $hilos[0].actualizado } else { (Mesa-IsoNow) }
    agentes=$agentes
    # Resumen de hilos sin mensajes para descarga ligera; el detalle va en /api/hilo?id=<id>.
    hilos=@(foreach ($hi in $hilos) {
      $u = if ($hi.mensajes -and $hi.mensajes.Count) { $hi.mensajes[-1] } else { $null }
      $uTexto = if ($u) { Mesa-Ocultar ([string]$u.texto) } else { '' }
      if ($uTexto.Length -gt 90) { $uTexto = $uTexto.Substring(0, 87) + '...' }
      [ordered]@{
        id = $hi.id; titulo = $hi.titulo; lider = $hi.lider; participantes = $hi.participantes
        estado = $hi.estado; actualizado = $hi.actualizado
        conteo_mensajes = if ($hi.mensajes) { $hi.mensajes.Count } else { 0 }
        ultimo_mensaje = if ($u) { [ordered]@{ tipo = $u.tipo; estado = $u.estado; fecha = $u.fecha; autor = $u.autor; texto = $uTexto } } else { $null }
      }
    })
    pendientes=@(foreach ($p in $pendientes) { $t = Mesa-Ocultar ([string]$p.texto); if ($t.Length -gt 180) { $t = $t.Substring(0, 177) + '...' }; [ordered]@{ autor=$p.autor; para=$p.para; texto=$t; traspaso=if ($p.traspaso) { [ordered]@{ falta=$p.traspaso.falta } } else { $null } } })
    cuota=$cuota
    catalogo=$catalogo
    alertas=$alertas
    empleado=if ($ganador.Count) { $ganador[0].nombre } else { $null }
    topes=$cfg.topes
    llamadas=(Mesa-ContadoresLlamadas)
    linea_tiempo=$lineaTiempo
    noticias=$noticias
    reclamos=@(Mesa-Reclamos)
    entregas=@(Mesa-Entregas | Select-Object hilo,tarea,autor,estado,fecha,ronda,revisor,motivo)
  }
}
