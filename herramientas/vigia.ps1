# Observador: no ejecuta comandos de sesiones ni modifica permisos.
param([switch]$Biblioteca)
. "$PSScriptRoot\comun.ps1"
. "$PSScriptRoot\observatorio.ps1"

function Vigia-DirectoriosEncargados {
  foreach ($carpeta in @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue)) {
    try { $hilo = Mesa-LeerJson (Join-Path $carpeta.FullName 'hilo.json') } catch { continue }
    if ($hilo.estado -ne 'abierto') { continue }
    foreach ($archivo in @(Get-ChildItem -LiteralPath $carpeta.FullName -Filter '*.json' -File)) {
      if ($archivo.Name -eq 'hilo.json') { continue }
      try {
        $encargo = Mesa-LeerJson $archivo.FullName
        if ($encargo.tipo -ne 'encargo' -or -not $encargo.dir) { continue }
        $dir = ([string]$encargo.dir) -replace '^/([a-zA-Z])/', '$1:\'
        # Solo directorios absolutos: no ampliar permisos según el cwd del vigía.
        if ($dir -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2})') { continue }
        [IO.Path]::GetFullPath($dir).Replace('/','\').TrimEnd('\')
      } catch { continue }
    }
  }
}
# Foto por ejecución, también con -Biblioteca; nunca recorrer hilos por evento.
$script:Vigia_DirectoriosEncargados = @(Vigia-DirectoriosEncargados | Select-Object -Unique)

function Vigia-ArgumentosBorrado([string]$Segmento) {
  $inicio = [regex]::Match($Segmento, '(?i)\b(?:rm|Remove-Item)\s+')
  if (!$inicio.Success) { return @() }
  $resto = $Segmento.Substring($inicio.Index + $inicio.Length)
  $rutas = New-Object System.Collections.Generic.List[string]
  $esperaValor = $false; $capturaRuta = $false
  foreach ($m in [regex]::Matches($resto, '"[^"]*"|''[^'']*''|[^\s]+')) {
    $crudo = $m.Value
    if ($esperaValor) {
      if ($capturaRuta) { $rutas.Add($crudo.Trim([char]34,[char]39)) }
      $esperaValor = $false; $capturaRuta = $false
      continue
    }
    if ($crudo.StartsWith('-')) {
      if ($crudo -eq '--') { continue }
      $opcion = $crudo.TrimStart('-')
      if ($opcion -match '(?i)^(Path|LiteralPath)(?:[:=](.*))?$') {
        if ($Matches[2]) { $rutas.Add($Matches[2].Trim([char]34,[char]39)) }
        else { $esperaValor = $true; $capturaRuta = $true }
      } elseif ($opcion -match '(?i)^(ErrorAction|ErrorVariable|WarningAction|WarningVariable|InformationAction|InformationVariable|OutVariable|OutBuffer|PipelineVariable|Filter|Include|Exclude|Stream|Encoding|Delimiter|Width)(?:[:=].*)?$') {
        if ($opcion -notmatch '[:=]') { $esperaValor = $true }
      }
      continue
    }
    $ruta = $crudo.Trim([char]34,[char]39)
    if ($ruta -and $ruta -notin @('{','}','(',')',',')) { $rutas.Add($ruta) }
  }
  return $rutas.ToArray()
}
function Vigia-RutaReclamada([string]$RutaRelativa, [string]$Toca) {
  foreach ($alcance in ($Toca -split '[,;\r\n]')) {
    $alcance = $alcance.Trim().Trim([char]34,[char]39).Replace('/','\').TrimStart([char[]]@([char]46,[char]92))
    # Quitar descripciones conservando los dos puntos de la unidad (D:\).
    $alcance = ($alcance -split ' \(|(?<!^[A-Za-z]):', 2)[0].Trim().Trim([char]34,[char]39)
    if (-not $alcance) { continue }
    if ([IO.Path]::IsPathRooted($alcance)) {
      $prefijoMesa = $Global:Mesa_Base.TrimEnd('\') + '\'
      if (-not $alcance.StartsWith($prefijoMesa, [StringComparison]::OrdinalIgnoreCase)) { continue }
      $alcance = $alcance.Substring($prefijoMesa.Length)
    }
    if ($alcance.Contains('*') -or $alcance.Contains('?')) {
      if ($RutaRelativa -like $alcance) { return $true }
    } elseif ($RutaRelativa.Equals($alcance, [StringComparison]::OrdinalIgnoreCase) -or
      ($alcance.EndsWith('\') -and $RutaRelativa.StartsWith($alcance, [StringComparison]::OrdinalIgnoreCase))) {
      return $true
    }
  }
  return $false
}
function Vigia-ReclamoActivo($Reclamo) {
  $tarea = [string]$Reclamo.tarea
  if (-not $tarea) { return $true }
  $alternas = @($tarea, ($tarea -replace '^(\d+)-', 'area-$1-')) | Select-Object -Unique
  $dueno = Mesa-NormalizarHerramienta ([string]$Reclamo.agente)
  if (-not $dueno) { $dueno = [regex]::Match([string]$Reclamo.agente, '^(?i)(claude|codex|agy)').Groups[1].Value.ToLowerInvariant() }
  foreach ($entrega in @(Mesa-Entregas -ConArchivadas)) {
    if ($entrega.estado -notin @('aceptada','archivada')) { continue }
    if ($Reclamo.hilo -and $entrega.hilo -ne $Reclamo.hilo) { continue }
    if ($dueno -and (Mesa-NormalizarHerramienta ([string]$entrega.autor)) -ne $dueno) { continue }
    foreach ($id in $alternas) {
      if ($entrega.tarea -eq $id -or $entrega.tarea.StartsWith($id + '-', [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
  }
  return $true
}
function Vigia-EscrituraCoordinada([string]$Agente, [string]$Valor, [string]$Cwd) {
  if (-not $Agente -or -not $Valor) { return $null }
  try {
    $ruta = ($Valor -replace '^~', $env:USERPROFILE) -replace '^/([a-zA-Z])/', '$1:\' -replace '^/tmp(?=/|$)', $env:TEMP
    if (![IO.Path]::IsPathRooted($ruta) -and $Cwd) { $ruta = Join-Path $Cwd $ruta }
    if (![IO.Path]::IsPathRooted($ruta)) { return $null }
    $ruta = [IO.Path]::GetFullPath($ruta).Replace('/','\')
    $raiz = [IO.Path]::GetFullPath($Global:Mesa_Base).TrimEnd('\')
    if (-not $ruta.StartsWith($raiz + '\', [StringComparison]::OrdinalIgnoreCase)) { return $null }
    $relativa = $ruta.Substring($raiz.Length + 1).Replace('/','\')
    if ($relativa -notmatch '(?i)^(?:panel|herramientas)[\\]') { return $null }

    $yo = Mesa-NormalizarHerramienta $Agente
    if (-not $yo) { return $null }
    $propia = $false
    $ajenas = New-Object System.Collections.Generic.List[string]
    foreach ($reclamo in @(Mesa-Reclamos | Where-Object { $_.toca -and (Vigia-ReclamoActivo $_) })) {
      if (-not (Vigia-RutaReclamada $relativa ([string]$reclamo.toca))) { continue }
      $dueno = Mesa-NormalizarHerramienta ([string]$reclamo.agente)
      if (-not $dueno) { $dueno = [regex]::Match([string]$reclamo.agente, '^(?i)(claude|codex|agy)').Groups[1].Value.ToLowerInvariant() }
      if ($dueno -eq $yo) { $propia = $true }
      elseif ($dueno) { $ajenas.Add($dueno) }
    }
    if ($ajenas.Count) { return @{ nivel='alto'; motivo="Escritura sobre archivo reclamado por otro agente ($((@($ajenas | Select-Object -Unique)) -join ', '))" } }
    if (-not $propia) { return @{ nivel='medio'; motivo='Escritura en panel/herramientas sin reclamo propio para esa ruta' } }
  } catch { return @{ nivel='medio'; motivo='No se pudo comprobar el reclamo de esta escritura' } }
  return $null
}
function Vigia-Evaluar([string]$Tipo, [string]$Valor, [string]$Cwd, [string]$Operacion, [string]$Agente) {
  $alto = New-Object System.Collections.Generic.List[string]
  $medio = New-Object System.Collections.Generic.List[string]
  if ($Valor -match $Global:Mesa_Excluidos) { $alto.Add('Referencia a ámbito excluido') }
  if ($Tipo -eq 'archivo' -and $Operacion -ne 'lectura') {
    if ($Valor -match '(?i)((?:^|[\\/])\.claude[\\/]settings\.json|(?:^|[\\/])\.codex[\\/]config\.toml|(?:^|[\\/])auth\.json|\.agentes-token|(?:^|[\\/])[^\\/]*\.env(?:\..*)?$)') { $alto.Add('Cambio de configuración sensible') }
    try {
      $ruta = ($Valor -replace '^~', $env:USERPROFILE) -replace '^/([a-zA-Z])/', '$1:\' -replace '^/tmp(?=/|$)', $env:TEMP
      if (![IO.Path]::IsPathRooted($ruta) -and $Cwd) { $ruta = Join-Path $Cwd $ruta }
      if ([IO.Path]::IsPathRooted($ruta)) {
        $ruta = [IO.Path]::GetFullPath($ruta).Replace('/','\')
        $permitida = $ruta.StartsWith($Global:Mesa_DefaultDir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
        foreach ($dir in $script:Vigia_DirectoriosEncargados) {
          if ($ruta.Equals($dir, [StringComparison]::OrdinalIgnoreCase) -or
            $ruta.StartsWith($dir + '\', [StringComparison]::OrdinalIgnoreCase)) { $permitida=$true; break }
        }
        if ($ruta.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { $permitida=$true }
        foreach ($cli in @('.claude','.codex','.gemini\antigravity-cli')) { if ($ruta.StartsWith((Join-Path $env:USERPROFILE $cli) + '\', [StringComparison]::OrdinalIgnoreCase)) { $permitida=$true } }
        if (!$permitida) { $alto.Add('Escritura fuera del ámbito de trabajo') }
      }
    } catch { $medio.Add('Ruta de escritura no resoluble') }
    $coordinacion = Vigia-EscrituraCoordinada $Agente $Valor $Cwd
    if ($coordinacion) {
      if ($coordinacion.nivel -eq 'alto') { $alto.Add($coordinacion.motivo) }
      else { $medio.Add($coordinacion.motivo) }
    }
  }
  if ($Tipo -eq 'comando') {
    $reglas = @{
      'Push forzado'='(?i)\bgit\s+push\b[^\r\n;]*(?:--force(?:-with-lease)?\b|(?:^|\s)-f(?:\s|$))'
      'Borrado remoto'='(?i)\bgit\s+push\b[^\r\n;]*--delete\b'
      'Borrado de rama'='(?-i)\bgit\s+branch\s+[^\r\n;]*-D\b'
      'Merge administrativo'='(?i)\bgh\s+pr\s+merge\b[^\r\n;]*--admin\b'
      'Publicación o borrado de release'='(?i)\bgh\s+release\s+(create|delete|upload)\b'
      'Borrado de repositorio'='(?i)\bgh\s+repo\s+delete\b'
      'Operación de disco o registro'='(?i)(?:^|[;&|\r\n])\s*(?:format(?:\.com)?(?:\s|$)|diskpart\b|reg\s+delete\b)'
      'Descarga y ejecución'='(?i)\b(curl|iwr|Invoke-WebRequest)\b[^\r\n]*\|\s*(iex|Invoke-Expression)\b'
      'Configuración sensible'='(?i)(?:Set-Content|Add-Content|Out-File|Remove-Item|\brm\b|\bdel\b|\btee\b|>)[^\r\n]*(?:\.claude[\\/]settings\.json|\.codex[\\/]config\.toml|auth\.json|\.agentes-token|\S*\.env\b)'
    }
    foreach ($r in $reglas.Keys) { if ($Valor -match $reglas[$r]) { $alto.Add($r) } }
    if ($Valor -match '(?i)\bgit\s+reset\s+--hard\b') {
      # Sin ejecutar git: leer únicamente HEAD, nunca configuración ni remotos.
      $main = $Valor -match '(?i)\bmain\b'
      if ($Cwd -and $Cwd -notmatch $Global:Mesa_Excluidos) {
        $head = Join-Path $Cwd '.git\HEAD'
        if (Test-Path -LiteralPath $head -PathType Leaf) { $main = $main -or (([IO.File]::ReadAllText($head)) -match 'refs/heads/main\s*$') }
      }
      if ($main) { $alto.Add('Reset destructivo en main') } else { $medio.Add('Reset destructivo; rama sin confirmar') }
    }
    # Resuelve solo asignaciones literales simples del comando; nunca ejecuta la expresión.
    $variables = @{}
    foreach ($asig in [regex]::Matches($Valor, '(?m)(?:^|[;\r\n])\s*\$?([A-Za-z_]\w*)\s*=\s*"([^"]*)"')) {
      $variables[$asig.Groups[1].Value] = $asig.Groups[2].Value
    }
    for ($paso = 0; $paso -lt 3; $paso++) {
      foreach ($nombre in @($variables.Keys)) {
        $valorVar = [string]$variables[$nombre]
        foreach ($otra in @($variables.Keys)) {
          if ($otra -ne $nombre) { $valorVar = $valorVar.Replace('$' + $otra, [string]$variables[$otra]) }
        }
        $variables[$nombre] = $valorVar
      }
    }
    foreach ($segmento in ($Valor -split '[;\r\n]|&&|\|\||\|')) {
      if ($segmento -match '(?i)\brm\s+-(?:rf|fr)\b|\brm\s+-r\s+-f\b|Remove-Item\b.*-Recurse\b') {
        $rutas = @(Vigia-ArgumentosBorrado $segmento)
        $seguro = $rutas.Count -gt 0
        $conVariable = $false
        $requiereRevision = $false
        foreach ($ruta in $rutas) {
          $normal = $ruta -replace '/', '\\'
          $varMatch = [regex]::Match($normal, '^\$(\w+)(.*)$')
          if ($varMatch.Success -and $variables.ContainsKey($varMatch.Groups[1].Value)) { $normal = ([string]$variables[$varMatch.Groups[1].Value] + $varMatch.Groups[2].Value) -replace '/', '\' }
          # Las variables que no se pueden resolver quedan para revisión, nunca se aprueban como seguras.
          if ($normal -match '\$' -and $normal -notmatch '\.\.|\*') { $conVariable = $true; continue }
          $rutaAmbigua = $normal -match '(?i)(?:^|\\)(?:playground|plugins)(?:\\|$)'
          $esCarpetaSegura = $normal -match '(?i)(?:^|\\)(?:worktrees?|temp|tmp|bin|obj|dist|scratchpad|marketplaces-locales)(?:\\|$)'
          if ($normal -match '\.\.|\*') { $seguro = $false }
          elseif ($rutaAmbigua) { $requiereRevision = $true }
          elseif (-not $esCarpetaSegura) { $seguro = $false }
        }
        if (!$seguro) { $alto.Add('Borrado recursivo fuera de carpetas desechables') }
        elseif ($conVariable -or $requiereRevision) { $medio.Add('Borrado recursivo con destino que requiere revisión') }
        if ($rutas.Count -gt 50 -or $segmento -match '(?i)Get-ChildItem.*\*|\*.*Remove-Item') { $medio.Add('Borrado masivo posible') }
      }
    }
    if ($Valor -match '(?im)(?:^|[;&|\r\n])\s*(?:\$?\w+\s*=\s*)?(?:Stop-Process\s+(?:-Name\b|-Id\s*\(|-Id\s+\d+\s*,)|Get-Process\b[^;\r\n]*\|\s*Stop-Process|taskkill\b[^;\r\n]*\*)') { $medio.Add('Detención masiva de procesos') }
    if ($Valor -match '(?i)(?:^|[;\r\n])\s*(?:rm|del|Remove-Item)\s+(.+)') {
      $destinos=@([regex]::Matches($Matches[1], '"[^"]+"|''[^'']+''|[^\s,]+') | Where-Object { $_.Value -notmatch '^-' })
      if ($destinos.Count -gt 50) { $medio.Add('Borrado de más de 50 destinos') }
    }
    if ($Valor -match '(?i)--dangerously-[\w-]+|danger-full-access') { $medio.Add('Sandbox desactivado') }
    if ($Valor -match '(?i)(?:^|[;\r\n])\s*(?:cd|Set-Location|Push-Location)\s+(?:-LiteralPath\s+|-Path\s+)?["'']?([^"'';\r\n]+)') {
      $destino = ($Matches[1].Trim()) -replace '^/([a-zA-Z])/', '$1:\' -replace '^/tmp(?=/|$)', $env:TEMP
      try {
        $resuelto = if ([IO.Path]::IsPathRooted($destino)) { [IO.Path]::GetFullPath($destino) } elseif ($Cwd) { [IO.Path]::GetFullPath((Join-Path $Cwd $destino)) } else { $destino }
        # Moverse dentro de la carpeta de programas o de temporales es trabajo normal.
        $dentro = $resuelto.StartsWith($Global:Mesa_DefaultDir, [StringComparison]::OrdinalIgnoreCase) -or $resuelto.StartsWith([IO.Path]::GetFullPath($env:TEMP), [StringComparison]::OrdinalIgnoreCase)
        if (!$dentro) { $medio.Add('Salida de la carpeta de trabajo') }
      } catch {}
    }
    # Destinos explícitos de escritura en shell; no interpretar contenidos de scripts.
    foreach ($m in [regex]::Matches($Valor, '(?i)(?:Set-Content|Add-Content|Out-File)\s+(?:-LiteralPath\s+|-Path\s+)?(?:"([^"]+)"|''([^'']+)''|([^\s;]+))|(?:^|\s)[12]?>>?\s*(?:"([^"]+)"|''([^'']+)''|([^\s;|&]+))')) {
      $ruta = @($m.Groups | Select-Object -Skip 1 | Where-Object Success | ForEach-Object Value)[0]
      if ($ruta) { $ruta = $ruta.Trim("`"'`t ()`r`n") }
      if ($ruta -in @('$null','/dev/null','NUL','&1','&2') -or $ruta -match '^(?:&[12]|/dev/null|NUL|\$null)$') { continue }
      $r = Vigia-Evaluar 'archivo' $ruta $Cwd 'escritura' $Agente
      if ($r) { if ($r.nivel -eq 'alto') { $alto.Add($r.motivo) } else { $medio.Add($r.motivo) } }
    }
  }
  if ($alto.Count) { return @{ nivel='alto'; motivo=($alto | Select-Object -Unique) -join '; ' } }
  if ($medio.Count) { return @{ nivel='medio'; motivo=($medio | Select-Object -Unique) -join '; ' } }
}

function Invocar-Vigia {
  $raiz = if ($env:VIGIA_RAIZ_PRUEBA) { Join-Path $env:VIGIA_RAIZ_PRUEBA 'datos' } else { $Global:Mesa_Raiz }
  New-Item -ItemType Directory -Force -Path $raiz | Out-Null
  $lock = $null
  try { $lock = [IO.File]::Open((Join-Path $raiz 'vigia.lock'),'OpenOrCreate','ReadWrite','None') } catch { return }
  try {
    $rutaEstado = Join-Path $raiz 'vigia-estado.json'
    $anterior = Mesa-LeerJson $rutaEstado
    $iniciado=if ($anterior.iniciado) { $anterior.iniciado } else { Mesa-IsoNow }
    $archivos = @{}
    if ($anterior.archivos) { foreach ($p in $anterior.archivos.PSObject.Properties) { $archivos[$p.Name]=$p.Value } }
    $recientes = @{}
    if ($anterior.recientes) { foreach ($p in $anterior.recientes.PSObject.Properties) { if (((Get-Date) - [datetime]$p.Value).TotalMinutes -lt 15) { $recientes[$p.Name] = $p.Value } } }
    $cronometro=[Diagnostics.Stopwatch]::StartNew()
    :agentes foreach ($agente in @('claude','codex','agy')) {
      foreach ($f in @(Mesa-Sesiones $agente | Where-Object { $_.LastWriteTime -ge (Get-Date).AddDays(-7) })) {
        if ($cronometro.ElapsedMilliseconds -gt 1800) { break agentes }
        $key = $f.FullName
        $prev = $archivos[$key]
        if ($prev -and [long]$prev.offset -eq $f.Length) { continue }
        $desde = if ($prev) { [long]$prev.offset } else { -1L }
        $cola = Mesa-Cola $key $desde
        if ($cola.error) { continue }
        $modelo = if ($prev) { $prev.modelo } else { 'desconocido' }
        $cwd = if ($prev) { $prev.cwd } else { $null }
        foreach ($l in $cola.lineas) {
          if (!$l.Trim()) { continue }
          try { $e = $l | ConvertFrom-Json } catch { continue }
          $meta = Mesa-Meta $e
          if ($meta.modelo) { $modelo=$meta.modelo }
          if ($meta.cwd -and $meta.cwd -notmatch $Global:Mesa_Excluidos) { $cwd=$meta.cwd }
          foreach ($a in @(Mesa-Acciones $e)) {
            if ($a.tipo -eq 'pasante') { continue }
            if ($a.valor -match $Global:Mesa_Excluidos) { continue }
            if (!$a.hora) { $a.hora=$f.LastWriteTime.ToString('o') }
            $contexto = if ($a.cwd) { $a.cwd } else { $cwd }
            $regla = Vigia-Evaluar $a.tipo $a.valor $contexto $a.operacion $agente
            # En el primer arranque sólo se alerta por acciones nuevas; las colas antiguas
            # sirven para actividad/metadatos, no para simular incidentes en vivo.
            if (!$env:VIGIA_RAIZ_PRUEBA) {
              try { if ([DateTimeOffset]::Parse($a.hora) -lt [DateTimeOffset]::Parse($iniciado)) { $regla=$null } } catch {}
            }
            $limpio = Mesa-Ocultar $a.valor
            if ($limpio.Length -gt 200) { $limpio = $limpio.Substring(0,197) + '...' }
            $registro = [ordered]@{ agente=$agente; modelo=$modelo; hora=$a.hora; tipo=$a.tipo; valor=$limpio; herramienta=$a.herramienta; operacion=$a.operacion }
            Mesa-AnexarLinea (Join-Path $raiz 'actividad.jsonl') ($registro | ConvertTo-Json -Compress)
            if ($regla) {
              $registro.id = [Guid]::NewGuid().ToString('N').Substring(0,12)
              $registro.nivel = $regla.nivel; $registro.motivo = $regla.motivo
              Mesa-AnexarLinea (Join-Path $raiz 'alertas.jsonl') ($registro | ConvertTo-Json -Compress)
            }
          }
        }
        # Una línea >256 KB se omite sin guardarla: evitar un atasco permanente.
        $offset = $cola.offset
        if ($cola.parcial -and $offset -eq [Math]::Max(0L,$desde)) { $offset = [Math]::Min($f.Length, $offset + 262144L) }
        $archivos[$key]=@{ offset=$offset; modelo=$modelo; cwd=(Mesa-Ocultar $cwd) }
      }
    }
    # El mapa conserva solo las sesiones que aún entran en la ventana de observación.
    $limiteArchivos = (Get-Date).ToUniversalTime().AddDays(-7)
    foreach ($key in @($archivos.Keys)) {
      if ([IO.File]::GetLastWriteTimeUtc($key) -lt $limiteArchivos) { $archivos.Remove($key) }
    }
    Mesa-EscribirJson $rutaEstado @{ iniciado=$iniciado; actualizado=(Mesa-IsoNow); archivos=$archivos; recientes=$recientes } -Comprimir
  } finally { $lock.Dispose() }
}
if (!$Biblioteca) { Invocar-Vigia }
