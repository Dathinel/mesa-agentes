# cuadrilla.ps1 con CLI falsos en una copia aislada (MESA_DATOS en %TEMP%): salidas, rechazos, cortes y git. No gasta cuota.
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$raiz = Join-Path $env:TEMP ('mesa-cuadrilla-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$datos = Join-Path $raiz 'datos'; $h = Join-Path $raiz 'herramientas'; $bin = Join-Path $raiz 'bin'; $casos = Join-Path $raiz 'casos'
$utf8 = New-Object Text.UTF8Encoding $false; $bom = New-Object Text.UTF8Encoding $true
$guardado = @{}
foreach ($clave in @('MESA_DATOS', 'MESA_TRABAJO', 'MESA_FALSO_DIR', 'MESA_FALSO_MODO', 'LOCALAPPDATA', 'Path', 'USERPROFILE')) { $guardado[$clave] = [Environment]::GetEnvironmentVariable($clave, 'Process') }
$script:fallos = 0; $lanzados = New-Object Collections.ArrayList
function Caso($nombre, $esperado, $obtenido, [bool]$ok) {
  if (-not $ok) { $script:fallos++ }
  Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido)
}
function Esperar([scriptblock]$condicion, [int]$segundos = 30) {
  $fin = (Get-Date).AddSeconds($segundos)
  while (-not (& $condicion)) { if ((Get-Date) -ge $fin) { throw "Tiempo de espera de la prueba ($segundos s)." }; Start-Sleep -Milliseconds 100 }
}
function Encargo-Md($nombre, $texto = 'Objetivo: prueba. Contexto: ninguno. Hecho cuando: sí. No toques: nada.') { $f = Join-Path $casos $nombre; [IO.File]::WriteAllText($f, $texto, $utf8); $f }
# Cada delegar es un proceso aparte, como lo lanza Claude: así valen el candado y la muerte del lanzador.
function Lanzar($modo, [string[]]$argumentos) {
  $casoDir = Join-Path $casos ('falso-' + [Guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force $casoDir | Out-Null
  $env:MESA_FALSO_DIR = $casoDir; $env:MESA_FALSO_MODO = $modo
  $todos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$h\cuadrilla.ps1`"", 'delegar') + @($argumentos | ForEach-Object { if ($_ -like '-*') { $_ } else { "`"$_`"" } })
  $p = Start-Process powershell.exe -ArgumentList $todos -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $casoDir 'salida.txt') -RedirectStandardError (Join-Path $casoDir 'error.txt')
  $null = $p.Handle; [void]$lanzados.Add($p)
  [pscustomobject]@{ proceso = $p; carpeta = $casoDir; reloj = [Diagnostics.Stopwatch]::StartNew() }
}
function Terminar($l, [int]$segundos = 60) {
  if (-not $l.proceso.WaitForExit($segundos * 1000)) { throw "delegar no terminó: $($l.carpeta)" }
  $l.reloj.Stop()
  $salida = [IO.File]::ReadAllText((Join-Path $l.carpeta 'salida.txt'), $utf8)
  $err = [IO.File]::ReadAllText((Join-Path $l.carpeta 'error.txt'), $utf8)
  $res = if ($salida -match '(?m)^(.+\\resultado\.json)\s*$') { Mesa-LeerJson $Matches[1] }
  [pscustomobject]@{ codigo = $l.proceso.ExitCode; texto = $salida; error = $err; resultado = $res; segundos = $l.reloj.Elapsed.TotalSeconds; carpeta = $l.carpeta }
}
function Delegar($modo, [string[]]$argumentos) { Terminar (Lanzar $modo $argumentos) }
function Vivos($arbol) { return @($arbol | Where-Object { Mesa-ProcesoVivo $_.id $_.inicio $_.nombre }).Count }
function Arbol($l) { $f = Join-Path $l.carpeta 'arbol.json'; Esperar { Test-Path -LiteralPath $f }; @(Mesa-LeerJson $f) }
function Resultado-Vivo($agente) {
  $fin = (Get-Date).AddSeconds(30)
  do {
    $v = Get-ChildItem (Join-Path $datos 'trabajos') -Directory -Filter "$agente-*" | ForEach-Object { Mesa-LeerJson (Join-Path $_.FullName 'resultado.json') } | Where-Object { $_.estado -eq 'ejecutando' -and $_.cli } | Select-Object -Last 1
    if ($v) { return $v }; Start-Sleep -Milliseconds 100
  } while ((Get-Date) -lt $fin)
  throw "ningún encargo de $agente vivo"
}

try {
  New-Item -ItemType Directory -Force $h, $bin, (Join-Path $datos 'trabajos'), $casos, (Join-Path $raiz 'perfil') | Out-Null
  foreach ($a in @('cuadrilla.ps1', 'proceso.ps1', 'comun.ps1', 'worktrees.ps1')) { Copy-Item -LiteralPath (Join-Path $base "herramientas\$a") -Destination $h }
  Copy-Item -LiteralPath (Join-Path $base 'herramientas\git-bloqueo') -Destination (Join-Path $h 'git-bloqueo') -Recurse
  New-Item -ItemType Directory -Force (Join-Path $raiz 'plantillas\cuadrilla') | Out-Null
  Copy-Item -LiteralPath (Join-Path $base 'plantillas\cuadrilla\SKILL.md') -Destination (Join-Path $raiz 'plantillas\cuadrilla')
  [IO.File]::WriteAllText((Join-Path $datos 'mesa.json'), '{"modelos":{"codex":["modelo-falso"],"agy":["modelo-falso"]},"limites":{"encargo_min":0.5,"inactivo_min":0.05},"worktrees":{"max_por_agente":3}}', $utf8)
  [IO.File]::WriteAllText((Join-Path $datos 'excluidos.txt'), "IVIMA`r`n", $utf8)
  # Solo los CLI falsos y lo imprescindible (git, powershell): nunca un CLI real.
  $gitDir = Split-Path -Parent (Get-Command git.exe).Source
  $env:Path = "$bin;$gitDir;$env:SystemRoot\System32;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
  $env:MESA_DATOS = $datos; $env:MESA_TRABAJO = $casos; $env:LOCALAPPDATA = $raiz; $env:USERPROFILE = Join-Path $raiz 'perfil'
  . "$h\comun.ps1"

  $falso = @'
[Console]::InputEncoding = New-Object Text.UTF8Encoding $false
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$u = New-Object Text.UTF8Encoding $false
$dir = $env:MESA_FALSO_DIR; $modo = $env:MESA_FALSO_MODO
$cli = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
$argumentos = @($args)
$texto = [Console]::In.ReadToEnd()
$i = [Array]::IndexOf($argumentos, '-p')
if ($i -ge 0 -and $argumentos[$i + 1] -match 'archivo UTF-8 (.+) y ejecuta') { $texto = [IO.File]::ReadAllText($Matches[1], $u) }
[IO.File]::WriteAllText((Join-Path $dir 'entrada.txt'), $texto, $u)
[IO.File]::WriteAllText((Join-Path $dir 'argumentos.json'), (ConvertTo-Json -InputObject $argumentos -Compress), $u)
[IO.File]::WriteAllText((Join-Path $dir 'cwd.txt'), (Get-Location).Path, $u)
function Evento($o) { [Console]::WriteLine((ConvertTo-Json -InputObject $o -Compress -Depth 5)) }
if ($modo -in @('arbol', 'mudo')) {
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',("`"" + (Join-Path (Split-Path -Parent $PSCommandPath) 'hijo.ps1') + "`"") -PassThru -WindowStyle Hidden
  while (-not (Test-Path (Join-Path $dir 'arbol.json'))) { Start-Sleep -Milliseconds 40 }
  if ($modo -eq 'mudo') { Start-Sleep -Seconds 300 }
  for ($n = 0; $n -lt 300; $n++) { [Console]::WriteLine("latido $n"); Start-Sleep -Seconds 1 }
}
if ($modo -eq 'git') {
  $c1 = & git commit --allow-empty -m x 2>&1; $commit = $LASTEXITCODE
  $c2 = & git push origin HEAD:main 2>&1; $push = $LASTEXITCODE
  [IO.File]::AppendAllText((Join-Path (Get-Location).Path 'README.md'), 'cambio', $u)
  $c3 = & git stash 2>&1; $stash = $LASTEXITCODE
  & git checkout -- README.md 2>&1 | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir 'git.json'), (ConvertTo-Json -Compress @{ commit = $commit; push = $push; stash = $stash; salida = "$c1`n$c2`n$c3" }), $u)
}
if ($cli -eq 'codex') {
  switch ($modo) {
    'cuota' { Evento @{ type = 'error'; message = 'You have hit your usage limit. Upgrade to Pro or try again at 6:57 PM.' }; Evento @{ type = 'turn.failed'; error = @{ message = 'You have hit your usage limit. Upgrade to Pro or try again at 6:57 PM.' } }; exit 1 }
    '401' { Evento @{ type = 'turn.failed'; error = @{ message = 'Error: 401 Unauthorized. Please run codex login' } }; exit 1 }
    default {
      Evento @{ type = 'item.completed'; item = @{ type = 'agent_message'; text = 'respuesta item con acción' } }
      Evento @{ type = 'turn.completed'; usage = @{ input_tokens = 13; cached_input_tokens = 0; output_tokens = 7 } }
      $o = [Array]::IndexOf($argumentos, '-o')
      if ($modo -ne 'sin-final' -and $o -ge 0) { [IO.File]::WriteAllText($argumentos[$o + 1], 'respuesta final con acción', $u) }
    }
  }
} else {
  Evento @{ event = 'init'; conversation_id = 'x' }
  switch ($modo) {
    'agy-error' { Evento @{ event = 'result'; result = @{ status = 'ERROR'; response = 'respuesta agy a medias'; error = 'Malformed function call'; usage = @{ input_tokens = 13; output_tokens = 7; total_tokens = 20 } } }; exit 1 }
    '503' { Evento @{ event = 'result'; result = @{ status = 'ERROR'; response = ''; error = '503 Service Unavailable' } }; exit 1 }
    default { Evento @{ event = 'result'; result = @{ status = 'SUCCESS'; response = 'respuesta agy con acción'; usage = @{ input_tokens = 13; output_tokens = 7; total_tokens = 20 } } } }
  }
}
'@
  foreach ($cli in @('codex', 'agy')) { [IO.File]::WriteAllText((Join-Path $bin "$cli.ps1"), $falso, $bom) }
  $hijo = @'
$nieto = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 300' -PassThru -WindowStyle Hidden
$arbol = @((Get-Process -Id $PID), $nieto) | ForEach-Object { @{ id = $_.Id; inicio = $_.StartTime.ToUniversalTime().ToString('o'); nombre = $_.ProcessName } }
[IO.File]::WriteAllText((Join-Path $env:MESA_FALSO_DIR 'arbol.json'), (ConvertTo-Json -InputObject @($arbol) -Compress), (New-Object Text.UTF8Encoding $false))
Start-Sleep -Seconds 300
'@
  [IO.File]::WriteAllText((Join-Path $bin 'hijo.ps1'), $hijo, $bom)
  $carpeta = Join-Path $casos 'carpeta'; New-Item -ItemType Directory -Force $carpeta | Out-Null

  # --- salidas ---
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'uno.md'), '-Dir', $carpeta)
  Caso 'codex con final.txt' 'salida 0, hecho, respuesta de final.txt, 20 tokens medidos' "codigo=$($r.codigo), estado=$($r.resultado.estado), respuesta=$($r.resultado.respuesta), tokens=$($r.resultado.tokens.total) $($r.error)" ($r.codigo -eq 0 -and $r.resultado.estado -eq 'hecho' -and $r.resultado.respuesta -eq 'respuesta final con acción' -and $r.resultado.tokens.total -eq 20 -and $r.resultado.cli.cli_pid -gt 0)
  $entrada = [IO.File]::ReadAllText((Join-Path $r.carpeta 'entrada.txt'), $utf8)
  Caso 'prompt con cabecera y encargo' 'cabecera fija, sin REINTENTO, encargo al final' ($entrada.Substring(0, [Math]::Min(80, $entrada.Length))) ($entrada -like 'Trabajas en *' -and $entrada -notmatch 'REINTENTO' -and $entrada -like '*No toques: nada.')
  $r = Delegar sin-final @('-A', 'codex', '-Encargo', (Encargo-Md 'dos.md'), '-Dir', $carpeta)
  Caso 'codex sin final.txt' 'texto del item.text del último agent_message' "codigo=$($r.codigo), respuesta=$($r.resultado.respuesta)" ($r.codigo -eq 0 -and $r.resultado.respuesta -eq 'respuesta item con acción')
  $r = Delegar agy-error @('-A', 'agy', '-Encargo', (Encargo-Md 'tres.md'), '-Dir', $carpeta)
  Caso 'agy ERROR con respuesta' 'salida 2, hecho con aviso, respuesta no vacía' "codigo=$($r.codigo), estado=$($r.resultado.estado), avisos=$($r.resultado.avisos -join ';')" ($r.codigo -eq 2 -and $r.resultado.estado -eq 'hecho' -and $r.resultado.respuesta -eq 'respuesta agy a medias' -and @($r.resultado.avisos).Count -eq 1)
  $args4 = @(Mesa-LeerJson (Join-Path $r.carpeta 'argumentos.json'))
  Caso 'agy va en stream-json y accept-edits' '--output-format stream-json, --mode accept-edits, --model modelo-falso' ($args4 -join ' ') ($args4 -contains 'stream-json' -and $args4 -contains 'accept-edits' -and $args4 -contains 'modelo-falso')
  $r = Delegar cuota @('-A', 'codex', '-Encargo', (Encargo-Md 'cuatro.md'), '-Dir', $carpeta)
  $hasta = if ($r.resultado.hasta) { ([datetime]::Parse($r.resultado.hasta)).ToString('HH:mm') }
  Caso '«try again at 6:57 PM»' 'fallo, sin-cuota, hasta las 18:57' "codigo=$($r.codigo), estado=$($r.resultado.estado), causa=$($r.resultado.causa), hasta=$hasta" ($r.codigo -eq 1 -and $r.resultado.estado -eq 'fallo' -and $r.resultado.causa -eq 'sin-cuota' -and $hasta -eq '18:57')
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'cinco.md'), '-Dir', $carpeta)
  Caso 'segundo intento sin cuota' 'NO LANZADO con 3 en menos de 2 s y sin arrancar el CLI' "codigo=$($r.codigo), segundos=$([int]$r.segundos), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.segundos -lt 2 -and $r.texto -match 'NO LANZADO: codex sin cuota hasta 18:57' -and -not (Test-Path (Join-Path $r.carpeta 'argumentos.json')))
  # La señal de cuota caduca: se finge que ya pasó la hora.
  $ult = Get-ChildItem (Join-Path $datos 'trabajos') -Directory -Filter 'codex-cuatro-*' | Select-Object -Last 1
  $res = Mesa-LeerJson (Join-Path $ult.FullName 'resultado.json'); $res.hasta = (Get-Date).AddMinutes(-1).ToString('yyyy-MM-ddTHH:mm:sszzz'); Mesa-EscribirJson (Join-Path $ult.FullName 'resultado.json') $res
  $r = Delegar 503 @('-A', 'agy', '-Encargo', (Encargo-Md 'seis.md'), '-Dir', $carpeta)
  Caso '503 da red' 'fallo con causa red' "codigo=$($r.codigo), causa=$($r.resultado.causa)" ($r.codigo -eq 1 -and $r.resultado.causa -eq 'red')
  $r = Delegar 401 @('-A', 'codex', '-Encargo', (Encargo-Md 'siete.md'), '-Dir', $carpeta)
  Caso '401 da necesita-login' 'fallo con causa necesita-login' "codigo=$($r.codigo), causa=$($r.resultado.causa)" ($r.codigo -eq 1 -and $r.resultado.causa -eq 'necesita-login')

  # --- rechazos ---
  $repo = Join-Path $casos 'repo'; $bare = Join-Path $casos 'remoto.git'
  & git init -q --bare $bare; & git init -q -b main $repo
  & git -C $repo -c user.name=p -c user.email=p@p config user.name p; & git -C $repo config user.email p@p
  [IO.File]::WriteAllText((Join-Path $repo 'README.md'), 'hola', $utf8); & git -C $repo add .; & git -C $repo commit -q -m inicial; & git -C $repo remote add origin $bare; & git -C $repo push -q origin main 2>&1 | Out-Null
  Remove-Item (Join-Path $bin 'agy.ps1')
  $r = Delegar normal @('-A', 'agy', '-Encargo', (Encargo-Md 'r1.md'), '-Dir', $repo)
  Caso 'CLI fuera del PATH' '3 en menos de 3 s' "codigo=$($r.codigo), segundos=$([int]$r.segundos), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.segundos -lt 3 -and $r.texto -match 'NO LANZADO: agy no está en el PATH')
  [IO.File]::WriteAllText((Join-Path $bin 'agy.ps1'), $falso, $bom)
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'r2.md'), '-Dir', (Join-Path $casos 'no-existe'))
  Caso 'carpeta inexistente' '3 en menos de 3 s' "codigo=$($r.codigo), segundos=$([int]$r.segundos), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.segundos -lt 3 -and $r.texto -match 'no existe la carpeta')
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'r3.md'), '-Dir', ($repo + '\$(x)'))
  Caso 'ruta con $(' '3 en menos de 3 s' "codigo=$($r.codigo), segundos=$([int]$r.segundos), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.segundos -lt 3 -and $r.texto -match 'acento grave')
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'r4.md'), '-Dir', $repo, '-Modelo', 'gemini-3-flash')
  Caso 'modelo inválido' '3 en menos de 3 s' "codigo=$($r.codigo), segundos=$([int]$r.segundos), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.segundos -lt 3 -and $r.texto -match 'modelo gemini-3-flash no está')
  $excl = Join-Path $casos 'IVIMA-cosa'; New-Item -ItemType Directory -Force $excl | Out-Null
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'r5.md'), '-Dir', $excl)
  Caso 'ruta excluida' '3' "codigo=$($r.codigo), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.texto -match 'excluida')
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'r6.md'), '-Dir', $casos)
  Caso 'carpeta con repos sin ser uno exige -Lectura' '3' "codigo=$($r.codigo), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.texto -match 'pide -Lectura')
  Caso 'ningún rechazo creó worktree' 'sin .claude\worktrees en el repo' (Test-Path (Join-Path $repo '.claude\worktrees')) (-not (Test-Path (Join-Path $repo '.claude\worktrees')))

  # --- cortes --- (Continue: el stderr de powershell.exe y git en 5.1 se volvería excepción)
  $ErrorActionPreference = 'Continue'
  $l1 = Lanzar arbol @('-A', 'codex', '-Encargo', (Encargo-Md 'ocupado.md'), '-Dir', $carpeta)
  $arbol = Arbol $l1
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'ocupado2.md'), '-Dir', $carpeta)
  Caso 'dos delegar al mismo CLI' 'el segundo sale 3 con ocupado' "codigo=$($r.codigo), texto=$($r.texto.Trim())" ($r.codigo -eq 3 -and $r.texto -match 'NO LANZADO: codex ocupado')
  $vivo = Resultado-Vivo codex
  $estado = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\cuadrilla.ps1" estado 2>&1 | Out-String
  Caso 'estado con uno ocupado' 'codex ocupado <id>; agy libre' ($estado.Trim() -replace "`r?`n", ' | ') ($estado -match "codex\s+ocupado $($vivo.id)" -and $estado -match 'agy\s+libre')
  $corte = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\cuadrilla.ps1" cortar $vivo.id 2>&1 | Out-String
  $r = Terminar $l1
  Esperar { (Vivos $arbol) -eq 0 } 10
  $res = Mesa-LeerJson (Join-Path $datos "trabajos\$($vivo.id)\resultado.json")
  Caso 'cortar mata el árbol' 'CORTADO, interrumpido/cortado y 0 descendientes' "$($corte.Trim()); estado=$($res.estado), causa=$($res.causa), vivos=$(Vivos $arbol)" ($corte -match 'CORTADO' -and $res.estado -eq 'interrumpido' -and $res.causa -eq 'cortado' -and (Vivos $arbol) -eq 0)

  $l2 = Lanzar mudo @('-A', 'agy', '-Encargo', (Encargo-Md 'mudo.md'), '-Dir', $carpeta)
  $arbol = Arbol $l2
  $r = Terminar $l2
  Caso 'falso mudo queda colgado' '124, colgado, 0 descendientes' "codigo=$($r.codigo), estado=$($r.resultado.estado), causa=$($r.resultado.causa), vivos=$(Vivos $arbol)" ($r.codigo -eq 124 -and $r.resultado.estado -eq 'colgado' -and $r.resultado.causa -eq 'colgado' -and (Vivos $arbol) -eq 0)

  $md = Encargo-Md 'matado.md'
  $l3 = Lanzar arbol @('-A', 'codex', '-Encargo', $md, '-Dir', $carpeta)
  $arbol = Arbol $l3; $vivo = Resultado-Vivo codex
  Stop-Process -Id $l3.proceso.Id -Force
  Esperar { (Vivos $arbol) -eq 0 } 10
  $estado = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\cuadrilla.ps1" estado 2>&1 | Out-String
  $res = Mesa-LeerJson (Join-Path $datos "trabajos\$($vivo.id)\resultado.json")
  Caso 'lanzador matado' 'estado lo marca interrumpido y 0 descendientes' "estado=$($res.estado), vivos=$(Vivos $arbol)" ($res.estado -eq 'interrumpido' -and (Vivos $arbol) -eq 0 -and $estado -match 'interrumpido')
  $r = Delegar normal @('-A', 'codex', '-Encargo', $md, '-Dir', $carpeta)
  $entrada = [IO.File]::ReadAllText((Join-Path $r.carpeta 'entrada.txt'), $utf8)
  Caso 'reintento con cabecera REINTENTO' "REINTENTO: el intento $($vivo.id) terminó interrumpido" "codigo=$($r.codigo); $(($entrada -split "`n" | Where-Object { $_ -like 'REINTENTO*' }) -join '')" ($r.codigo -eq 0 -and $entrada -match "REINTENTO: el intento $([regex]::Escape($vivo.id)) terminó interrumpido")

  # --- git ---
  $r = Delegar git @('-A', 'codex', '-Encargo', (Encargo-Md 'encargo-codex-hdr.md' "Objetivo: toca $repo\README.md y $repo\no-existe.txt."), '-Dir', $repo)
  $g = Mesa-LeerJson (Join-Path $r.carpeta 'git.json')
  $wt = $r.resultado.worktree
  Caso 'encargo-codex-hdr.md da codex-hdr' "worktree ...\codex-hdr, rama codex/hdr, cwd en el worktree" "wt=$wt, rama=$($r.resultado.rama), cwd=$([IO.File]::ReadAllText((Join-Path $r.carpeta 'cwd.txt')))" ($wt -like '*\.claude\worktrees\codex-hdr' -and $r.resultado.rama -eq 'codex/hdr' -and [IO.File]::ReadAllText((Join-Path $r.carpeta 'cwd.txt')).TrimEnd('\') -eq $wt)
  $entrada = [IO.File]::ReadAllText((Join-Path $r.carpeta 'entrada.txt'), $utf8)
  Caso 'rutas del repo apuntan al worktree' 'README.md al worktree; no-existe.txt sigue en el repo' ($entrada -split "`n" | Select-Object -Last 1) ($entrada -like "*$wt\README.md*" -and $entrada -like "*$repo\no-existe.txt*")
  $argsCodex = @(Mesa-LeerJson (Join-Path $r.carpeta 'argumentos.json'))
  Caso 'codex: sandbox y sin red por defecto' '-C <wt> -s workspace-write, sin network_access ni --add-dir general' ($argsCodex -join ' ') ($argsCodex -contains $wt -and $argsCodex -contains 'workspace-write' -and ($argsCodex -join ' ') -notmatch 'network_access' -and $argsCodex -notcontains '--add-dir')
  $headWt = & git -C $wt rev-parse HEAD; $headRepo = & git -C $repo rev-parse HEAD; $remoto = & git -C $bare rev-parse main
  Caso 'commit, push y stash fallan en el CLI' 'los tres con error; HEAD y remoto intactos; salida 0 sin avisos' "commit=$($g.commit), push=$($g.push), stash=$($g.stash), codigo=$($r.codigo), avisos=$($r.resultado.avisos -join ';'); $($g.salida -replace "`n", ' | ')" ($g.commit -ne 0 -and $g.push -ne 0 -and $g.stash -ne 0 -and $headWt -eq $headRepo -and $remoto -eq $headRepo -and $r.codigo -eq 0 -and @($r.resultado.avisos).Count -eq 0)
  $r2 = Delegar normal @('-A', 'codex', '-Encargo', (Join-Path $casos 'encargo-codex-hdr.md'), '-Dir', $repo)
  Caso 'el mismo .md ya hecho se rechaza' '3 con «ya se hizo»' "codigo=$($r2.codigo), texto=$($r2.texto.Trim())" ($r2.codigo -eq 3 -and $r2.texto -match 'ya se hizo')
  $r3 = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'hdr-correccion.md' 'Objetivo: corrige.'), '-Dir', $repo, '-Tarea', 'hdr')
  Caso '-Tarea corrige en el mismo worktree' 'salida 0 y el mismo worktree' "codigo=$($r3.codigo), wt=$($r3.resultado.worktree)" ($r3.codigo -eq 0 -and $r3.resultado.worktree -eq $wt)
  $candado = [IO.File]::Open((Join-Path $datos 'trabajos\codex.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
  try { $limpiar1 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\worktrees.ps1" limpiar 2>&1 | Out-String } finally { $candado.Dispose() }
  $limpiar2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\worktrees.ps1" limpiar 2>&1 | Out-String
  Caso 'limpiar respeta el worktree con candado' 'con candado se queda; sin candado se quita (integrado y limpio)' "con=$($limpiar1.Trim()); sin=$($limpiar2.Trim())" ($limpiar1 -match 'Se queda \(codex tiene un encargo en marcha\)' -and $limpiar2 -match 'Quitado' -and -not (Test-Path $wt))

  # --- lectura ---
  $antes = & git -C $repo status --porcelain | Out-String
  $r = Delegar normal @('-A', 'codex', '-Encargo', (Encargo-Md 'lee.md'), '-Dir', $repo, '-Lectura')
  $argsCodex = @(Mesa-LeerJson (Join-Path $r.carpeta 'argumentos.json'))
  Caso '-Lectura: read-only, sin worktree' 'salida 0, -s read-only, cwd el repo, sin worktree' "codigo=$($r.codigo), wt=$($r.resultado.worktree), args=$($argsCodex -join ' ')" ($r.codigo -eq 0 -and -not $r.resultado.worktree -and $argsCodex -contains 'read-only' -and -not (Test-Path (Join-Path $repo '.claude\worktrees\codex-*')) -and ((& git -C $repo status --porcelain | Out-String) -eq $antes))
  $r = Delegar normal @('-A', 'agy', '-Encargo', (Encargo-Md 'lee2.md'), '-Dir', $repo, '-Lectura')
  $argsAgy = @(Mesa-LeerJson (Join-Path $r.carpeta 'argumentos.json'))
  Caso 'agy -Lectura va en plan' '--mode plan' ($argsAgy -join ' ') ($r.codigo -eq 0 -and $argsAgy -contains 'plan')
} catch {
  $script:fallos++; Write-Host "ERROR de la prueba: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
} finally {
  foreach ($p in $lanzados) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
  foreach ($clave in $guardado.Keys) { [Environment]::SetEnvironmentVariable($clave, $guardado[$clave], 'Process') }
  if ($Conservar) { Write-Host "Copia conservada en $raiz" }
  else {
    $destino = [IO.Path]::GetFullPath($raiz)
    if ($destino.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\mesa-cuadrilla-', [StringComparison]::OrdinalIgnoreCase)) { Start-Sleep -Milliseconds 500; Remove-Item -LiteralPath $destino -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
