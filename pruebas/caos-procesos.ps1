# CLI falsos en una copia aislada: no acceden a cuotas, perfiles ni sesiones reales.
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$raiz = Join-Path $env:TEMP ('mesa-procesos-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$datos = Join-Path $raiz 'datos'; $h = Join-Path $raiz 'herramientas'; $bin = Join-Path $raiz 'bin'
$utf8 = New-Object Text.UTF8Encoding $false
$bom = New-Object Text.UTF8Encoding $true
$guardado = @{}
foreach ($clave in @('MESA_DATOS','MESA_RAIZ_PRUEBA','MESA_SIMULAR','MESA_SIN_AVISOS','MESA_FALSO_DIR','MESA_FALSO_MODO','LOCALAPPDATA')) {
  $guardado[$clave] = [Environment]::GetEnvironmentVariable($clave, 'Process')
}
$script:fallos = 0; $ejecutores = New-Object Collections.ArrayList
function Caso($nombre, $esperado, $obtenido, [bool]$ok) {
  if (-not $ok) { $script:fallos++ }
  Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido)
}
function Esperar([scriptblock]$condicion, [int]$segundos = 20) {
  $fin = (Get-Date).AddSeconds($segundos)
  while (-not (& $condicion)) {
    if ((Get-Date) -ge $fin) { throw "Tiempo de espera de la prueba ($segundos s)." }
    Start-Sleep -Milliseconds 80
  }
}
function Leer-Mensaje([int]$numero) { Mesa-LeerJson (Join-Path $datos "hilos\prueba\$('{0:D4}' -f $numero)-claude.json") }
function Ruta-Mensaje([int]$numero) { Join-Path $datos "hilos\prueba\$('{0:D4}' -f $numero)-claude.json" }
function Preparar([int]$numero, [string]$cli, [string]$modo = 'normal', [double]$minutos = 0.5) {
  $casoDir = Join-Path $raiz "caso-$numero"; New-Item -ItemType Directory -Force $casoDir | Out-Null
  $env:MESA_FALSO_DIR = $casoDir; $env:MESA_FALSO_MODO = $modo
  Mesa-EscribirJson (Join-Path $datos 'mesa.json') @{ topes = @{}; limites = @{ encargo_min = $minutos; charla_min = 0.1 } }
  $texto = ('encargo áéíóú ñ "comillas" & % espacios ' * 1300) + 'FIN'
  Mesa-EscribirJson (Ruta-Mensaje $numero) ([ordered]@{ n = $numero; autor = 'claude'; para = $cli; herramienta = $cli; modelo = 'modelo-falso'; esfuerzo = 'low'; texto = $texto; encargo = $null; dir = $casoDir; estado = 'aprobado'; llamada = $null; traspaso = $null })
  $argumentos = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$h\ejecutar.ps1`"",'-Hilo','prueba','-N',"$numero",'-Sesion',"sesion-$cli")
  $p = Start-Process powershell.exe -ArgumentList $argumentos -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $casoDir 'ejecutor.out') -RedirectStandardError (Join-Path $casoDir 'ejecutor.err')
  $null = $p.Handle
  [void]$ejecutores.Add($p)
  return [pscustomobject]@{ proceso = $p; carpeta = $casoDir; n = $numero }
}
function Terminar($caso) {
  if (-not $caso.proceso.WaitForExit(25000)) { throw "El ejecutor de #$($caso.n) no terminó." }
  $m = Leer-Mensaje $caso.n
  if ($m.estado -eq 'ejecutando') { throw "El mensaje #$($caso.n) quedó ejecutando: $([IO.File]::ReadAllText((Join-Path $caso.carpeta 'ejecutor.err')))" }
  return $m
}
function Arbol($caso) {
  Esperar { Test-Path -LiteralPath (Join-Path $caso.carpeta 'arbol.json') }
  return @(Mesa-LeerJson (Join-Path $caso.carpeta 'arbol.json'))
}
function Vivos($arbol) { return @($arbol | Where-Object { Mesa-ProcesoVivo $_.id $_.inicio $_.nombre }).Count }

try {
  New-Item -ItemType Directory -Force $h, $bin, (Join-Path $datos 'hilos\prueba'), (Join-Path $datos 'agentes') | Out-Null
  foreach ($archivo in @('ejecutar.ps1','proceso.ps1','comun.ps1','mesa.ps1')) { Copy-Item -LiteralPath (Join-Path $base "herramientas\$archivo") -Destination $h }
  # Solo cambia la resolución de ejecutables de la copia para impedir que arranque un CLI real.
  $rutaEjecutar = Join-Path $h 'ejecutar.ps1'
  $copia = [IO.File]::ReadAllText($rutaEjecutar)
  $copia = $copia.Replace('$env:Path = [Environment]', ('$env:Path = ' + "'$bin;' + [Environment]"))
  # Barrera solo de la copia: permite adquirir el candado exactamente antes del callback real.
  $barrera = @'
param($identidad)
    if ($env:MESA_FALSO_MODO -eq 'candado' -and -not (Test-Path (Join-Path $env:MESA_FALSO_DIR 'identidad-lista'))) {
      [IO.File]::WriteAllText((Join-Path $env:MESA_FALSO_DIR 'identidad-lista'), '')
      while (-not (Test-Path (Join-Path $env:MESA_FALSO_DIR 'candado-listo'))) { Start-Sleep -Milliseconds 10 }
    }
'@
  $copia = $copia.Replace('param($identidad)', $barrera)
  [IO.File]::WriteAllText($rutaEjecutar, $copia, $bom)
  [IO.File]::WriteAllText((Join-Path $h 'costes.ps1'), 'function Mesa-MuestraSesion { return @{} }', $bom)
  [IO.File]::WriteAllText((Join-Path $h 'tokens-calibrador.ps1'), '', $bom)
  $env:MESA_DATOS = $datos; $env:MESA_RAIZ_PRUEBA = $datos; $env:MESA_SIMULAR = $null
  $env:MESA_SIN_AVISOS = '1'; $env:LOCALAPPDATA = $raiz
  . "$h\comun.ps1"
  . "$h\proceso.ps1"
  Mesa-EscribirJson (Join-Path $datos 'hilos\prueba\hilo.json') @{ id = 'prueba'; lider = 'claude'; participantes = @('claude','codex','agy'); estado = 'abierto'; actualizado = (Mesa-IsoNow) }

  $falso = @'
[Console]::InputEncoding = New-Object Text.UTF8Encoding $false
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$u = New-Object Text.UTF8Encoding $false
$dir = $env:MESA_FALSO_DIR
if ($env:MESA_FALSO_MODO -eq 'bloqueo') { Start-Sleep -Seconds 300; exit 0 }
if ($env:MESA_FALSO_MODO -like 'muere*') { [Console]::Error.WriteLine('error temprano con acción'); exit ([int]$env:MESA_FALSO_MODO.Substring(5)) }
$texto = [Console]::In.ReadToEnd()
$argumentos = @($args)
$indicePrompt = [Array]::IndexOf($argumentos, '-p')
if ($indicePrompt -ge 0 -and $indicePrompt + 1 -lt $argumentos.Count -and $argumentos[$indicePrompt + 1] -match 'archivo UTF-8 (.+) y ejecuta') {
  $texto = [IO.File]::ReadAllText($Matches[1], [Text.Encoding]::UTF8)
}
[IO.File]::WriteAllText((Join-Path $dir 'entrada.txt'), $texto, $u)
[IO.File]::WriteAllText((Join-Path $dir 'argumentos.json'), (ConvertTo-Json -InputObject $argumentos -Compress), $u)
[Console]::WriteLine('salida áéíóú ñ 中文')
[Console]::Error.WriteLine('stderr también: pingüino, acción')
if ($env:MESA_FALSO_MODO -in @('arbol','candado')) {
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',("`"" + (Join-Path (Split-Path -Parent $PSCommandPath) 'hijo.ps1') + "`"") -PassThru -WindowStyle Hidden
  while (-not (Test-Path (Join-Path $dir 'arbol.json'))) { Start-Sleep -Milliseconds 40 }
  Start-Sleep -Seconds 300
}
$indice = [Array]::IndexOf($argumentos, '-o')
if ($indice -ge 0) { [IO.File]::WriteAllText($argumentos[$indice + 1], 'respuesta final con acción', $u) }
if ($env:MESA_FALSO_MODO -in @('herramienta','herramienta-fallo')) {
  [Console]::WriteLine('{"type":"tool_result","status":"ERROR","message":"quota 401 /login","usage":{"input_tokens":9999}}')
}
$cli = [IO.Path]::GetFileNameWithoutExtension($PSCommandPath)
if ($env:MESA_FALSO_MODO -eq 'fallo-final') {
  if ($cli -eq 'codex') { [Console]::WriteLine('{"type":"turn.failed","error":{"message":"quota exhausted 429"}}') }
  elseif ($cli -eq 'agy') { [Console]::WriteLine('{"event":"result","result":{"status":"RESOURCE_EXHAUSTED","message":"quota exhausted 429"}}') }
  else { [Console]::WriteLine('{"type":"result","is_error":true,"result":"quota exhausted 429"}') }
} elseif ($cli -eq 'codex') {
  [Console]::WriteLine('{"type":"turn.completed","usage":{"input_tokens":13,"output_tokens":7,"total_tokens":20}}')
} else {
  [Console]::WriteLine('{"type":"result","result":"respuesta con acción","usage":{"input_tokens":13,"output_tokens":7,"total_tokens":20}}')
}
if ($env:MESA_FALSO_MODO -eq 'herramienta-fallo') { exit 1 }
'@
  foreach ($cli in @('codex','claude','agy')) { [IO.File]::WriteAllText((Join-Path $bin "$cli.ps1"), $falso, $bom) }
  $hijo = @'
$nieto = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 300' -PassThru -WindowStyle Hidden
$arbol = @((Get-Process -Id $PID), $nieto) | ForEach-Object { @{ id = $_.Id; inicio = $_.StartTime.ToUniversalTime().ToString('o'); nombre = $_.ProcessName } }
[IO.File]::WriteAllText((Join-Path $env:MESA_FALSO_DIR 'arbol.json'), (ConvertTo-Json -InputObject @($arbol) -Compress), (New-Object Text.UTF8Encoding $false))
Start-Sleep -Seconds 300
'@
  [IO.File]::WriteAllText((Join-Path $bin 'hijo.ps1'), $hijo, $bom)

  $numero = 10
  foreach ($cli in @('codex','claude','agy')) {
    $caso = Preparar $numero $cli
    $m = Terminar $caso
    $prompt = [IO.File]::ReadAllText((Join-Path $datos "hilos\prueba\logs\$('{0:D4}' -f $numero)-$cli-prompt.txt"))
    $recibido = [IO.File]::ReadAllText((Join-Path $caso.carpeta 'entrada.txt'))
    $argsCli = @(Mesa-LeerJson (Join-Path $caso.carpeta 'argumentos.json'))
    $sesionFlag = if ($cli -eq 'codex') { 'resume' } elseif ($cli -eq 'claude') { '--resume' } else { '--conversation' }
    $limpio = $m.estado -eq 'hecho' -and $m.llamada.salida -eq 0 -and $m.llamada.cli_pid -gt 0 -and $m.llamada.cli_inicio -and $m.llamada.cli_nombre
    Caso "Prompt largo completo ($cli)" '>40000 caracteres intactos, salida 0 e identidad persistida' "enviados=$($prompt.Length), recibidos=$($recibido.Length), estado=$($m.estado), salida=$($m.llamada.salida)" ($prompt.Length -gt 40000 -and $prompt -ceq $recibido -and $limpio)
    $registro = Get-Content -LiteralPath (Join-Path $datos 'registro-tokens.jsonl') -Encoding UTF8 -Tail 1 | ConvertFrom-Json
    Caso "Sesión y modelo ($cli)" "$sesionFlag, sesion-$cli y modelo-falso preservados; 20 tokens medidos" "$($argsCli -join ' '); tokens=$($registro.total), calidad=$($registro.calidad)" ($argsCli -contains $sesionFlag -and $argsCli -contains "sesion-$cli" -and $argsCli -contains 'modelo-falso' -and $registro.total -eq 20 -and $registro.calidad -eq 'medido')
    $log = $m.llamada.log; $bytes = [IO.File]::ReadAllBytes($log)
    $decodificador = New-Object Text.UTF8Encoding $false, $true
    $textoLog = $decodificador.GetString($bytes)
    $sinBom = $bytes.Length -gt 3 -and -not ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
    Caso "UTF-8 stdout y stderr ($cli)" 'acentos y chino intactos, sin BOM ni bytes NUL' "acentos=$($textoLog.Contains('acción')), stderr=$($textoLog.Contains('stderr también')), sinBOM=$sinBom" ($sinBom -and $bytes -notcontains 0 -and $textoLog.Contains('áéíóú ñ 中文') -and $textoLog.Contains('stderr también: pingüino, acción'))
    $numero += 10
  }

  $caso = Preparar 40 codex arbol
  $arbol = Arbol $caso
  Esperar { (Leer-Mensaje 40).llamada.cli_pid -gt 0 }
  $ll = (Leer-Mensaje 40).llamada
  $enCurso = Mesa-LeerJson (Join-Path $datos "agentes\en-curso-$($caso.proceso.Id).json")
  Caso 'Identidad durante el encargo' 'llamada y en-curso coinciden en PID, inicio, nombre, intento y panel' ($enCurso | ConvertTo-Json -Compress) ($enCurso.cli_pid -eq $ll.cli_pid -and $enCurso.cli_inicio -eq $ll.cli_inicio -and $enCurso.cli_nombre -eq $ll.cli_nombre -and $enCurso.intento -eq $ll.intento -and $enCurso.pid -eq $caso.proceso.Id -and (Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre))
  Stop-Process -Id $ll.cli_pid -Force
  $m = Terminar $caso
  Caso 'CLI muerto a mitad' 'fallo registrado y ningún hijo ni nieto suelto' "estado=$($m.estado), salida=$($m.llamada.salida), vivos=$(Vivos $arbol)" ($m.estado -eq 'fallo' -and $m.llamada.salida -ne 0 -and (Vivos $arbol) -eq 0)

  $caso = Preparar 50 claude arbol
  $arbol = Arbol $caso
  $m = Leer-Mensaje 50; $ll = $m.llamada
  $m.llamada.cli_inicio = (Get-Date).AddDays(-1).ToString('o'); Mesa-EscribirJson (Ruta-Mensaje 50) $m
  $rechazo = try { & "$h\mesa.ps1" cortar -Hilo prueba -N 50 -De claude; 'cortó' } catch { $_.Exception.Message }
  Caso 'Cortar rechaza identidad distinta' 'no se corta nada; el CLI sigue vivo' $rechazo ($rechazo -match 'no se corta nada' -and [bool](Get-Process -Id $ll.cli_pid -ErrorAction SilentlyContinue))
  $m.llamada.cli_inicio = (Get-Process -Id $ll.cli_pid).StartTime.ToUniversalTime().ToString('o'); Mesa-EscribirJson (Ruta-Mensaje 50) $m
  $corte = & "$h\mesa.ps1" cortar -Hilo prueba -N 50 -De claude
  $m = Terminar $caso
  Caso 'Cortar mata el árbol del CLI' 'corte confirmado, fallo registrado y ningún descendiente vivo; ejecutor sale normalmente' "$corte; vivos=$(Vivos $arbol), ejecutor=$($caso.proceso.ExitCode), estado=$($m.estado)" ($corte -match 'CORTADO' -and (Vivos $arbol) -eq 0 -and $m.estado -eq 'fallo' -and $caso.proceso.ExitCode -eq 0)

  $caso = Preparar 60 codex arbol 0.1
  $arbol = Arbol $caso
  $m = Terminar $caso
  Caso 'Límite de tiempo' 'salida 124, causa tiempo, fallo y árbol vacío' "salida=$($m.llamada.salida), causa=$($m.llamada.causa), estado=$($m.estado), vivos=$(Vivos $arbol)" ($m.llamada.salida -eq 124 -and $m.llamada.causa -eq 'tiempo' -and $m.estado -eq 'fallo' -and (Vivos $arbol) -eq 0)

  $actual = Get-Process -Id $PID; $inicio = $actual.StartTime.ToUniversalTime().ToString('o')
  Caso 'PID reutilizado' 'misma identidad vivo; otra hora o nombre no vivo' "correcto=$(Mesa-ProcesoVivo $PID $inicio $actual.ProcessName), hora falsa=$(Mesa-ProcesoVivo $PID ((Get-Date).AddDays(-1).ToString('o')) $actual.ProcessName)" ((Mesa-ProcesoVivo $PID $inicio $actual.ProcessName) -and -not (Mesa-ProcesoVivo $PID ((Get-Date).AddDays(-1).ToString('o')) $actual.ProcessName) -and -not (Mesa-ProcesoVivo $PID $inicio 'otro'))
  Caso 'Límites por hilo' 'encargo=5400s, charla=1200s, configurable=3s' "encargo=$(Mesa-LimiteSegundos @{} prueba), charla=$(Mesa-LimiteSegundos @{} charla-codex), configurado=$(Mesa-LimiteSegundos @{limites=@{charla_min=0.05}} charla-agy)" ((Mesa-LimiteSegundos @{} prueba) -eq 5400 -and (Mesa-LimiteSegundos @{} charla-codex) -eq 1200 -and (Mesa-LimiteSegundos @{limites=@{charla_min=0.05}} charla-agy) -eq 3)

  $env:MESA_FALSO_MODO = 'bloqueo'
  $reloj = [Diagnostics.Stopwatch]::StartNew()
  $r = Invocar-ProcesoMesa -Ejecutable (Join-Path $bin 'codex.ps1') -Entrada ('x' * 1000000) -Directorio $raiz -Log (Join-Path $raiz 'bloqueo.log') -Segundos 1
  Caso 'Stdin bloqueada también vence' 'salida 124 y menos de 5 segundos' "salida=$($r.salida), segundos=$($reloj.Elapsed.TotalSeconds)" ($r.salida -eq 124 -and $reloj.Elapsed.TotalSeconds -lt 5)

  $env:MESA_FALSO_MODO = 'normal'; $script:pintadas = New-Object Collections.ArrayList
  function Mostrar-Linea([string]$linea) { [void]$script:pintadas.Add($linea) }
  $r = Invocar-ProcesoMesa -Ejecutable (Join-Path $bin 'claude.ps1') -Argumentos @('espacio y "comillas" & %', 'fin\') -Entrada 'di hola ñ' -Directorio $raiz -Log (Join-Path $raiz 'ver.log') -Segundos 10 -Ver
  $argsVer = @(Mesa-LeerJson (Join-Path $env:MESA_FALSO_DIR 'argumentos.json'))
  Caso 'Ver pinta lo guardado y argumentos intactos' 'cada línea llega a Mostrar-Linea; espacios, comillas y barra final intactos' "lineas=$($script:pintadas.Count), argumentos=$($argsVer -join ';')" ($r.salida -eq 0 -and $script:pintadas.Count -eq 3 -and $argsVer[0] -ceq 'espacio y "comillas" & %' -and $argsVer[1] -ceq 'fin\')

  # Errores en herramientas no son errores del CLI, tampoco cuando el proceso sale con 1.
  $numero = 100
  foreach ($cli in @('codex','claude','agy')) {
    foreach ($modo in @('herramienta','herramienta-fallo','fallo-final')) {
      $caso = Preparar $numero $cli $modo
      $m = Terminar $caso
      $ok = if ($modo -eq 'herramienta') { $m.estado -eq 'hecho' -and -not $m.llamada.causa }
        elseif ($modo -eq 'herramienta-fallo') { $m.estado -eq 'fallo' -and -not $m.llamada.causa }
        else { $m.estado -eq 'fallo' -and $m.llamada.causa -eq 'sin-cuota' }
      Caso "Evento final ($cli, $modo)" 'solo el evento final determina fallo y cuota' "estado=$($m.estado), causa=$($m.llamada.causa)" $ok
      $numero += 10
    }
  }

  # Reejecutar el mismo mensaje conserva los logs y enlaces de ambas respuestas.
  $caso = Preparar 200 codex
  $m = Terminar $caso; $logPrimero = $m.llamada.log; $contenidoPrimero = [IO.File]::ReadAllText($logPrimero)
  $m.estado = 'aprobado'; $m | Add-Member -NotePropertyName intentos -NotePropertyValue 1 -Force
  Mesa-EscribirJson (Ruta-Mensaje 200) $m
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$h\ejecutar.ps1" -Hilo prueba -N 200 | Out-Null
  $m = Leer-Mensaje 200
  $respuestas = @(Get-ChildItem (Join-Path $datos 'hilos\prueba') -Filter '*-codex.json' | ForEach-Object { Mesa-LeerJson $_.FullName } | Where-Object { $_.tipo -eq 'respuesta' })
  Caso 'Un log por intento y enlaces propios' 'intento1 e intento2 intactos y cada respuesta enlaza el suyo' "$logPrimero; $($m.llamada.log)" ($logPrimero -like '*-intento1.log' -and $m.llamada.log -like '*-intento2.log' -and [IO.File]::ReadAllText($logPrimero) -ceq $contenidoPrimero -and $respuestas.llamada.log -contains $logPrimero -and $respuestas.llamada.log -contains $m.llamada.log)

  # Ejecutable de consola real, sin envoltorio PowerShell y sin modelos.
  $nativo = Join-Path $bin 'falso.exe'
  Add-Type -OutputAssembly $nativo -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Text;
public class CliFalso {
  public static int Main(string[] args) {
    Console.InputEncoding = new UTF8Encoding(false); Console.OutputEncoding = new UTF8Encoding(false);
    Console.Error.WriteLine("diagnóstico temprano: acción");
    if (args.Length > 0 && args[0] == "muere") return int.Parse(args[1]);
    Console.WriteLine(Console.In.ReadToEnd()); return 0;
  }
}
'@
  $node = (Get-Command node.exe -ErrorAction Stop).Source
  $js = Join-Path $bin 'falso.js'
  [IO.File]::WriteAllText($js, 'process.stderr.write("diagnóstico temprano: acción\n"); if(process.argv[2]==="muere") process.exit(Number(process.argv[3])); process.stdin.setEncoding("utf8"); process.stdin.on("data", x=>process.stdout.write(x));', $utf8)
  foreach ($directo in @($nativo, $node)) {
    $prefArgs = @(if ($directo -eq $node) { $js })
    $logDirecto = Join-Path $raiz 'directo.log'
    $r = Invocar-ProcesoMesa -Ejecutable $directo -Argumentos $prefArgs -Entrada 'UTF-8 áéíóú ñ 中文' -Directorio $raiz -Log $logDirecto
    $txt = [IO.File]::ReadAllText($logDirecto, $utf8)
    Caso "UTF-8 directo ($([IO.Path]::GetFileName($directo)))" 'salida y entrada UTF-8 intactas' $txt ($r.salida -eq 0 -and $txt.Contains('UTF-8 áéíóú ñ 中文') -and $txt.Contains('diagnóstico temprano: acción'))
    foreach ($salida in @(0,1)) {
      $r = Invocar-ProcesoMesa -Ejecutable $directo -Argumentos ($prefArgs + @('muere', "$salida")) -Entrada ('x' * 4000000) -Directorio $raiz -Log $logDirecto
      $txt = [IO.File]::ReadAllText($logDirecto, $utf8)
      Caso "Muerte antes de stdin ($([IO.Path]::GetFileName($directo)), $salida)" 'código real, error temprano y aviso stdin incluso al salir con 1' "salida=$($r.salida); $txt" ($r.salida -eq $salida -and $txt.Contains('diagnóstico temprano: acción') -and $txt.Contains('AVISO stdin:'))
    }
    # Callback retrasa la comprobación hasta después de la salida y del límite.
    $r = Invocar-ProcesoMesa -Ejecutable $directo -Argumentos ($prefArgs + @('muere','1')) -Directorio $raiz -Log $logDirecto -Segundos 0.3 -AlIniciar { param($id) Start-Sleep -Milliseconds 700; return $true }
    Caso "Salida al vencer límite ($([IO.Path]::GetFileName($directo)))" 'código 1 real y sin causa tiempo' "salida=$($r.salida), causa=$($r.causa)" ($r.salida -eq 1 -and -not $r.causa)
  }

  # Candado real ocupado cuando el callback intenta guardar la identidad.
  $env:MESA_FALSO_MODO = 'bloqueo'
  $pruebaLock = Join-Path $raiz 'identidad.lock'
  $lock = [IO.File]::Open($pruebaLock,'OpenOrCreate','ReadWrite','None')
  $estado = @{ intentos = 0; vivo = $false; guardado = $false }
  try {
    $r = Invocar-ProcesoMesa -Ejecutable (Join-Path $bin 'codex.ps1') -Directorio $raiz -Log (Join-Path $raiz 'candado.log') -Segundos 3 -AlIniciar {
      param($id)
      $estado.intentos++
      if ($estado.intentos -eq 2) { $estado.vivo = Mesa-ProcesoVivo $id.cli_pid $id.cli_inicio $id.cli_nombre; $lock.Dispose() }
      $c = [IO.File]::Open($pruebaLock,'OpenOrCreate','ReadWrite','None')
      $c.Dispose(); $estado.guardado = $true; return $true
    }
  } finally { $lock.Dispose() }
  Caso 'Candado ocupado no mata CLI y reintenta' 'CLI sigue vivo hasta timeout y segunda escritura funciona' "intentos=$($estado.intentos), vivo=$($estado.vivo), guardado=$($estado.guardado), salida=$($r.salida)" ($estado.intentos -ge 2 -and $estado.vivo -and $estado.guardado -and $r.salida -eq 124)

  $caso = Preparar 210 codex candado
  Esperar { Test-Path (Join-Path $caso.carpeta 'identidad-lista') }
  $lock = [IO.File]::Open((Join-Path $datos 'hilos\prueba\hilo.lock'),'OpenOrCreate','ReadWrite','None')
  try {
    [IO.File]::WriteAllText((Join-Path $caso.carpeta 'candado-listo'), '')
    $arbol = Arbol $caso
    Start-Sleep -Seconds 11
    $vivosBloqueado = Vivos $arbol
  } finally { $lock.Dispose() }
  Esperar { (Leer-Mensaje 210).llamada.cli_pid -gt 0 }
  $ll = (Leer-Mensaje 210).llamada
  $enCurso = Mesa-LeerJson (Join-Path $datos "agentes\en-curso-$($caso.proceso.Id).json")
  Caso 'Persistencia real con candado ocupado' 'CLI y árbol siguen vivos tras 11s; identidad guardada al liberar' "descendientes=$vivosBloqueado, cli=$($ll.cli_pid), enCurso=$($enCurso.cli_pid)" ($vivosBloqueado -eq 2 -and (Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre) -and $ll.cli_pid -eq $enCurso.cli_pid)
  Stop-Process -Id $ll.cli_pid -Force
  $null = Terminar $caso

  $caso = Preparar 70 codex arbol
  $arbol = Arbol $caso
  $ll = (Leer-Mensaje 70).llamada
  Stop-Process -Id $caso.proceso.Id -Force
  Esperar { -not (Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre) -and (Vivos $arbol) -eq 0 } 5
  Caso 'Muerte del lanzador' 'el Job mata CLI, hijo y nieto aunque no se ejecute finally' "CLI vivo=$(Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre), descendientes=$(Vivos $arbol)" (-not (Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre) -and (Vivos $arbol) -eq 0)
} catch {
  $script:fallos++; Write-Host "ERROR de la prueba: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
} finally {
  foreach ($p in $ejecutores) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
  foreach ($clave in $guardado.Keys) { [Environment]::SetEnvironmentVariable($clave, $guardado[$clave], 'Process') }
  if ($Conservar) { Write-Host "Copia conservada en $raiz" }
  else {
    $destino = [IO.Path]::GetFullPath($raiz)
    if ($destino.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\mesa-procesos-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $destino -Recurse -Force }
  }
}
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
