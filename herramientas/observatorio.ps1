# Lectores acotados y adaptadores de metadatos. Nunca devuelve mensajes de sesión.
function Mesa-Cola([string]$Ruta, [long]$Desde = -1) {
  $fs = $null
  try {
    $fs = [IO.File]::Open($Ruta, 'Open', 'Read', 'ReadWrite')
    $inicio = if ($Desde -lt 0 -or $Desde -gt $fs.Length) { [Math]::Max(0L, $fs.Length - 262144L) } else { $Desde }
    [void]$fs.Seek($inicio, 'Begin')
    $n = [int][Math]::Min(262144L, $fs.Length - $inicio)
    $buf = New-Object byte[] $n
    $leidos = $fs.Read($buf, 0, $n)
    $ultimo = $leidos - 1
    while ($ultimo -ge 0 -and $buf[$ultimo] -ne 10) { $ultimo-- }
    if ($ultimo -lt 0) { return @{ lineas = @(); offset = $inicio; parcial = ($n -eq 262144) } }
    $texto = [Text.Encoding]::UTF8.GetString($buf, 0, $ultimo + 1)
    $lineas = @($texto -split "`n")
    if ($Desde -lt 0 -and $inicio -gt 0) { $lineas = @($lineas | Select-Object -Skip 1) }
    return @{ lineas = $lineas; offset = $inicio + $ultimo + 1; parcial = ($fs.Length -gt $inicio + $ultimo + 1) }
  } catch { return @{ lineas = @(); offset = [Math]::Max(0L, $Desde); error = $true } }
  finally { if ($fs) { $fs.Dispose() } }
}

function Mesa-Jsonl([string]$Ruta) {
  foreach ($l in (Mesa-Cola $Ruta).lineas) { if ($l.Trim()) { try { $l | ConvertFrom-Json } catch {} } }
}

function Mesa-RegistroLocal([string]$Ruta) {
  if (!(Test-Path -LiteralPath $Ruta)) { return }
  $fs=$null; $reader=$null
  try {
    $fs=[IO.File]::Open($Ruta,'Open','Read','ReadWrite')
    $reader=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8)
    while (!$reader.EndOfStream) { $l=$reader.ReadLine(); if ($l.Trim()) { try { $l | ConvertFrom-Json } catch {} } }
  } finally { if ($reader) { $reader.Dispose() } elseif ($fs) { $fs.Dispose() } }
}

function Mesa-Ocultar([string]$Texto) {
  $s = $Texto -replace '(?i)(?:ghp_|github_pat_|sk-|AIza)[A-Za-z0-9_\-]+', '<OCULTO>'
  $s = $s -replace '(?i)(Bearer\s+)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace '(?i)(X-[\w-]*Token\s*[=:]\s*)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace '(?i)((?:api[_-]?key|password|secret|access[_-]?token)\s*[=:]\s*["'']?)[^\s"'';,}]+', '$1<OCULTO>'
  $s = $s -replace ($Global:Mesa_Excluidos + '[^\s"'']*'), '<RUTA EXCLUIDA>'
  return $s
}

function Mesa-SanearObjeto($Objeto) {
  if ($null -eq $Objeto) { return $null }
  if ($Objeto -is [string]) { return (Mesa-Ocultar $Objeto) }
  if ($Objeto -is [Collections.IDictionary]) {
    $r=@{}; foreach ($k in $Objeto.Keys) { $r[$k]=Mesa-SanearObjeto $Objeto[$k] }; return $r
  }
  if ($Objeto -is [Collections.IEnumerable]) { $r=@(foreach ($v in $Objeto) { Mesa-SanearObjeto $v }); return ,$r }
  if ($Objeto -is [pscustomobject]) { $r=@{}; foreach ($p in $Objeto.PSObject.Properties) { $r[$p.Name]=Mesa-SanearObjeto $p.Value }; return $r }
  return $Objeto
}

function Mesa-Sesiones([string]$Agente) {
  $base = if ($env:VIGIA_RAIZ_PRUEBA) { Join-Path $env:VIGIA_RAIZ_PRUEBA $Agente } else {
    switch ($Agente) { claude { Join-Path $env:USERPROFILE '.claude\projects' }; codex { Join-Path $env:USERPROFILE '.codex\sessions' }; agy { Join-Path $env:USERPROFILE '.gemini\antigravity-cli\brain' } }
  }
  if (Test-Path -LiteralPath $base) {
    Get-ChildItem -LiteralPath $base -Recurse -File -Filter *.jsonl -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -notmatch ($Global:Mesa_Excluidos + '|(?i)[\\/](?:auth|credentials|tokens)\.') } | Sort-Object LastWriteTime -Descending
  }
}

function Mesa-Meta($e) {
  $p = $e.payload
  $modelo = if ($p.model) { $p.model } elseif ($e.message.model) { $e.message.model } elseif ($e.model) { $e.model } else { $null }
  $esfuerzo = if ($p.effort) { $p.effort } elseif ($p.reasoning_effort) { $p.reasoning_effort } elseif ($e.effort) { $e.effort } else { $null }
  $cwd = if ($p.cwd) { $p.cwd } elseif ($e.cwd) { $e.cwd } else { $null }
  @{ modelo = $modelo; esfuerzo = $esfuerzo; cwd = $cwd }
}

function Mesa-Acciones($e) {
  # Lista blanca: tool_use, function_call y functionCall. Sin texto de usuario/asistente.
  $calls = @()
  if ($e.payload.type -in @('function_call','custom_tool_call')) { $calls += $e.payload }
  if ($e.type -in @('tool_use','function_call','custom_tool_call','tool_call')) { $calls += $e }
  foreach ($b in @($e.message.content) + @($e.content)) { if ($b.type -eq 'tool_use') { $calls += $b } }
  foreach ($p in @($e.parts) + @($e.content.parts) + @($e.message.parts)) { if ($p.functionCall) { $calls += $p.functionCall } }
  if ($e.toolCall) { $calls += $e.toolCall }
  foreach ($call in $calls) {
    $name = [string]$call.name
    if (-not $name) { $name = [string]$call.tool }
    $arg = if ($null -ne $call.arguments) { $call.arguments } elseif ($null -ne $call.args) { $call.args } else { $call.input }
    if ($arg -is [string]) { try { $arg = $arg | ConvertFrom-Json } catch {} }
    $stamp = if ($e.timestamp) { $e.timestamp } elseif ($e.time) { $e.time } else { $null }
    if ($name -match '(?i)(^|[._])(Task|Agent|spawn_agent|delegate|subagent)$') {
      [pscustomobject]@{ tipo='pasante'; valor=$call.id; herramienta=$name; hora=$stamp; operacion='inicio' }; continue
    }
    if ($name -match '(?i)(apply_patch|patch)$') {
      $patch = if ($arg -is [string]) { $arg } elseif ($arg.patch) { $arg.patch } else { $arg.input }
      foreach ($m in [regex]::Matches([string]$patch, '(?m)^\*\*\* (?:(?:Add|Update|Delete) File: |Move to: )(.+?)\r?$')) {
        [pscustomobject]@{ tipo='archivo'; valor=$m.Groups[1].Value; herramienta=$name; hora=$stamp; operacion='escritura' }
      }
      continue
    }
    $ruta = if ($arg.file_path) { $arg.file_path } elseif ($arg.path) { $arg.path } elseif ($arg.TargetFile) { $arg.TargetFile } elseif ($arg.AbsolutePath) { $arg.AbsolutePath } else { $null }
    if ($ruta) {
      $op = if ($name -match '(?i)read|view|search|list|glob|grep|find|get_') { 'lectura' } else { 'escritura' }
      [pscustomobject]@{ tipo='archivo'; valor=[string]$ruta; herramienta=$name; hora=$stamp; operacion=$op }
    }
    if ($name -match '(?i)Bash|PowerShell|exec_command|run_command|shell|terminal') {
      $cmd = if ($arg.cmd) { $arg.cmd } elseif ($arg.command) { $arg.command } elseif ($arg.CommandLine) { $arg.CommandLine } else { $null }
      if ($cmd) { [pscustomobject]@{ tipo='comando'; valor=[string]$cmd; herramienta=$name; hora=$stamp; operacion='ejecucion'; cwd=$arg.workdir } }
    }
    # Orquestador JS: extraer solo los argumentos cmd/command, nunca el código de un parche.
    if ($name -match '(^|\.)exec$' -and $arg -is [string]) {
      foreach ($m in [regex]::Matches($arg, '(?:cmd|command)\s*:\s*("(?:\\.|[^"\\])*")')) {
        try { $cmd = $m.Groups[1].Value | ConvertFrom-Json; [pscustomobject]@{ tipo='comando'; valor=$cmd; herramienta='exec_command'; hora=$stamp; operacion='ejecucion' } } catch {}
      }
      foreach ($m in [regex]::Matches($arg, 'apply_patch\(("(?:\\.|[^"\\])*")\)')) {
        try { $patch = $m.Groups[1].Value | ConvertFrom-Json; Mesa-Acciones ([pscustomobject]@{ type='custom_tool_call'; name='apply_patch'; input=$patch; timestamp=$stamp }) } catch {}
      }
    }
  }
}

function Mesa-Actividades([int]$Horas = 8, [string]$Agente) {
  $desde = (Get-Date).AddHours(-$Horas)
  $lista = New-Object System.Collections.Generic.List[object]
  foreach ($a in @(Mesa-RegistroLocal (Join-Path $Global:Mesa_Raiz 'actividad.jsonl'))) {
    if ($a.tipo -eq 'archivo' -and $a.valor -notmatch $Global:Mesa_Excluidos -and $a.operacion -ne 'lectura' -and (!$Agente -or $a.agente -eq $Agente)) {
      try { if ([DateTimeOffset]::Parse($a.hora).LocalDateTime -ge $desde) { $lista.Add($a) } } catch {}
    }
  }
  foreach ($f in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Recurse -File -Filter '*-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -ne 'logs' })) {
    try {
      $m = Mesa-LeerJson $f.FullName; $autor = Mesa-NormalizarHerramienta $m.autor
      if (!$autor -or ($Agente -and $autor -ne $Agente) -or [DateTimeOffset]::Parse($m.fecha).LocalDateTime -lt $desde) { continue }
      foreach ($ruta in @($m.traspaso.archivos)) {
        foreach ($r in ([string]$ruta -split ',')) {
          if ($r.Trim() -and $r -notmatch $Global:Mesa_Excluidos) { $lista.Add([pscustomobject]@{ agente=$autor; modelo=$m.modelo; hora=$m.fecha; tipo='archivo'; valor=(Mesa-Ocultar $r.Trim()); herramienta='traspaso'; operacion='declarado' }) }
        }
      }
    } catch {}
  }
  $lista | Sort-Object hora -Descending | Group-Object agente,valor | ForEach-Object { $_.Group[0] }
}

function Mesa-Alertas([int]$Horas = 24, [string]$Nivel) {
  $vistas = Mesa-LeerJson (Join-Path $Global:Mesa_Raiz 'alertas-revisadas.json')
  foreach ($a in @(Mesa-RegistroLocal (Join-Path $Global:Mesa_Raiz 'alertas.jsonl'))) {
    try {
      if ([DateTimeOffset]::Parse($a.hora) -lt [DateTimeOffset]::Now.AddHours(-$Horas) -or ($Nivel -and $a.nivel -ne $Nivel)) { continue }
      $a | Add-Member -NotePropertyName revisada -NotePropertyValue (@($vistas.ids) -contains $a.id) -Force
      $a
    } catch {}
  }
}
