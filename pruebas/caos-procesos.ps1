# Lanzador de procesos (proceso.ps1) con CLI falsos en una copia aislada: no toca cuotas, perfiles ni sesiones reales.
param([switch]$Conservar)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$raiz = Join-Path $env:TEMP ('mesa-procesos-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
$datos = Join-Path $raiz 'datos'; $bin = Join-Path $raiz 'bin'
$utf8 = New-Object Text.UTF8Encoding $false
$bom = New-Object Text.UTF8Encoding $true
$guardado = @{}
foreach ($clave in @('MESA_DATOS', 'MESA_FALSO_DIR', 'MESA_FALSO_MODO')) { $guardado[$clave] = [Environment]::GetEnvironmentVariable($clave, 'Process') }
$script:fallos = 0
function Caso($nombre, $esperado, $obtenido, [bool]$ok) {
  if (-not $ok) { $script:fallos++ }
  Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido)
}
function Esperar([scriptblock]$condicion, [int]$segundos = 20) {
  $fin = (Get-Date).AddSeconds($segundos)
  while (-not (& $condicion)) { if ((Get-Date) -ge $fin) { throw "Tiempo de espera de la prueba ($segundos s)." }; Start-Sleep -Milliseconds 80 }
}
function Vivos($arbol) { return @($arbol | Where-Object { Mesa-ProcesoVivo $_.id $_.inicio $_.nombre }).Count }

try {
  New-Item -ItemType Directory -Force $bin, $datos | Out-Null
  $env:MESA_DATOS = $datos; $env:MESA_FALSO_DIR = $raiz
  . "$base\herramientas\comun.ps1"
  . "$base\herramientas\proceso.ps1"

  $falso = @'
[Console]::InputEncoding = New-Object Text.UTF8Encoding $false
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$u = New-Object Text.UTF8Encoding $false
$dir = $env:MESA_FALSO_DIR
if ($env:MESA_FALSO_MODO -eq 'bloqueo') { Start-Sleep -Seconds 300; exit 0 }
$texto = [Console]::In.ReadToEnd()
[IO.File]::WriteAllText((Join-Path $dir 'entrada.txt'), $texto, $u)
[IO.File]::WriteAllText((Join-Path $dir 'argumentos.json'), (ConvertTo-Json -InputObject @($args) -Compress), $u)
[Console]::WriteLine('salida áéíóú ñ 中文')
[Console]::Error.WriteLine('stderr también: pingüino, acción')
if ($env:MESA_FALSO_MODO -eq 'arbol') {
  $p = Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',("`"" + (Join-Path (Split-Path -Parent $PSCommandPath) 'hijo.ps1') + "`"") -PassThru -WindowStyle Hidden
  while (-not (Test-Path (Join-Path $dir 'arbol.json'))) { Start-Sleep -Milliseconds 40 }
  # Mudo a partir de aquí: el corte por inactividad debe llevarse el árbol entero.
  Start-Sleep -Seconds 300
}
[Console]::WriteLine('{"type":"turn.completed","usage":{"input_tokens":13,"output_tokens":7,"total_tokens":20}}')
'@
  [IO.File]::WriteAllText((Join-Path $bin 'codex.ps1'), $falso, $bom)
  $hijo = @'
$nieto = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 300' -PassThru -WindowStyle Hidden
$arbol = @((Get-Process -Id $PID), $nieto) | ForEach-Object { @{ id = $_.Id; inicio = $_.StartTime.ToUniversalTime().ToString('o'); nombre = $_.ProcessName } }
[IO.File]::WriteAllText((Join-Path $env:MESA_FALSO_DIR 'arbol.json'), (ConvertTo-Json -InputObject @($arbol) -Compress), (New-Object Text.UTF8Encoding $false))
Start-Sleep -Seconds 300
'@
  [IO.File]::WriteAllText((Join-Path $bin 'hijo.ps1'), $hijo, $bom)
  $codex = Join-Path $bin 'codex.ps1'

  $env:MESA_FALSO_MODO = 'normal'
  $largo = ('encargo áéíóú ñ "comillas" & % espacios ' * 1300) + 'FIN'
  $log = Join-Path $raiz 'largo.log'
  $r = Invocar-ProcesoMesa -Ejecutable $codex -Argumentos @('exec', '-m', 'modelo-falso', '-') -Entrada $largo -Directorio $raiz -Log $log -Segundos 20
  $recibido = [IO.File]::ReadAllText((Join-Path $raiz 'entrada.txt'), $utf8)
  $argsCli = @(Mesa-LeerJson (Join-Path $raiz 'argumentos.json'))
  Caso 'Prompt largo completo' '>40000 caracteres intactos, salida 0 e identidad' "enviados=$($largo.Length), recibidos=$($recibido.Length), salida=$($r.salida), pid=$($r.identidad.cli_pid)" ($largo.Length -gt 40000 -and $largo -ceq $recibido -and $r.salida -eq 0 -and $r.identidad.cli_pid -gt 0 -and $r.identidad.cli_inicio -and $r.identidad.cli_nombre)
  Caso 'Argumentos intactos' 'exec -m modelo-falso -' ($argsCli -join ' ') ($argsCli -join ' ' -ceq 'exec -m modelo-falso -')
  $bytes = [IO.File]::ReadAllBytes($log); $textoLog = (New-Object Text.UTF8Encoding $false, $true).GetString($bytes)
  $sinBom = $bytes.Length -gt 3 -and -not ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
  Caso 'UTF-8 stdout y stderr' 'acentos y chino intactos, sin BOM ni bytes NUL' "acentos=$($textoLog.Contains('acción')), sinBOM=$sinBom" ($sinBom -and $bytes -notcontains 0 -and $textoLog.Contains('áéíóú ñ 中文') -and $textoLog.Contains('stderr también: pingüino, acción'))

  $env:MESA_FALSO_MODO = 'arbol'; Remove-Item (Join-Path $raiz 'arbol.json') -ErrorAction SilentlyContinue
  $r = Invocar-ProcesoMesa -Ejecutable $codex -Directorio $raiz -Log (Join-Path $raiz 'tiempo.log') -Segundos 3
  $arbol = @(Mesa-LeerJson (Join-Path $raiz 'arbol.json'))
  Caso 'Límite de tiempo' 'salida 124, causa tiempo y árbol vacío' "salida=$($r.salida), causa=$($r.causa), vivos=$(Vivos $arbol)" ($r.salida -eq 124 -and $r.causa -eq 'tiempo' -and (Vivos $arbol) -eq 0)

  Remove-Item (Join-Path $raiz 'arbol.json') -ErrorAction SilentlyContinue
  $reloj = [Diagnostics.Stopwatch]::StartNew()
  $r = Invocar-ProcesoMesa -Ejecutable $codex -Directorio $raiz -Log (Join-Path $raiz 'inactivo.log') -Segundos 60 -Inactivo 2
  $arbol = @(Mesa-LeerJson (Join-Path $raiz 'arbol.json'))
  Caso 'Inactivo' 'salida 124, causa colgado en menos de 15 s y árbol vacío' "salida=$($r.salida), causa=$($r.causa), segundos=$([int]$reloj.Elapsed.TotalSeconds), vivos=$(Vivos $arbol)" ($r.salida -eq 124 -and $r.causa -eq 'colgado' -and $reloj.Elapsed.TotalSeconds -lt 15 -and (Vivos $arbol) -eq 0)

  $actual = Get-Process -Id $PID; $inicio = $actual.StartTime.ToUniversalTime().ToString('o')
  Caso 'PID reutilizado' 'misma identidad vivo; otra hora o nombre no vivo' "correcto=$(Mesa-ProcesoVivo $PID $inicio $actual.ProcessName), hora falsa=$(Mesa-ProcesoVivo $PID ((Get-Date).AddDays(-1).ToString('o')) $actual.ProcessName)" ((Mesa-ProcesoVivo $PID $inicio $actual.ProcessName) -and -not (Mesa-ProcesoVivo $PID ((Get-Date).AddDays(-1).ToString('o')) $actual.ProcessName) -and -not (Mesa-ProcesoVivo $PID $inicio 'otro'))

  $env:MESA_FALSO_MODO = 'bloqueo'
  $reloj = [Diagnostics.Stopwatch]::StartNew()
  $r = Invocar-ProcesoMesa -Ejecutable $codex -Entrada ('x' * 1000000) -Directorio $raiz -Log (Join-Path $raiz 'bloqueo.log') -Segundos 1
  Caso 'Stdin bloqueada también vence' 'salida 124 y menos de 5 segundos' "salida=$($r.salida), segundos=$($reloj.Elapsed.TotalSeconds)" ($r.salida -eq 124 -and $reloj.Elapsed.TotalSeconds -lt 5)

  $env:MESA_FALSO_MODO = 'normal'; $script:pintadas = New-Object Collections.ArrayList
  function Mostrar-Linea([string]$linea) { [void]$script:pintadas.Add($linea) }
  $r = Invocar-ProcesoMesa -Ejecutable $codex -Argumentos @('espacio y "comillas" & %', 'fin\') -Entrada 'di hola ñ' -Directorio $raiz -Log (Join-Path $raiz 'ver.log') -Segundos 10 -Ver
  $argsVer = @(Mesa-LeerJson (Join-Path $raiz 'argumentos.json'))
  Caso 'Ver pinta lo guardado y argumentos intactos' 'cada línea llega a Mostrar-Linea; espacios, comillas y barra final intactos' "lineas=$($script:pintadas.Count), argumentos=$($argsVer -join ';')" ($r.salida -eq 0 -and $script:pintadas.Count -eq 3 -and $argsVer[0] -ceq 'espacio y "comillas" & %' -and $argsVer[1] -ceq 'fin\')

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
    foreach ($salida in @(0, 1)) {
      $r = Invocar-ProcesoMesa -Ejecutable $directo -Argumentos ($prefArgs + @('muere', "$salida")) -Entrada ('x' * 4000000) -Directorio $raiz -Log $logDirecto
      $txt = [IO.File]::ReadAllText($logDirecto, $utf8)
      Caso "Muerte antes de stdin ($([IO.Path]::GetFileName($directo)), $salida)" 'código real, error temprano y aviso stdin incluso al salir con 1' "salida=$($r.salida); $txt" ($r.salida -eq $salida -and $txt.Contains('diagnóstico temprano: acción') -and $txt.Contains('AVISO stdin:'))
    }
    $r = Invocar-ProcesoMesa -Ejecutable $directo -Argumentos ($prefArgs + @('muere', '1')) -Directorio $raiz -Log $logDirecto -Segundos 0.3 -AlIniciar { param($id) Start-Sleep -Milliseconds 700; return $true }
    Caso "Salida al vencer límite ($([IO.Path]::GetFileName($directo)))" 'código 1 real y sin causa tiempo' "salida=$($r.salida), causa=$($r.causa)" ($r.salida -eq 1 -and -not $r.causa)
  }

  # Candado real ocupado cuando el callback intenta guardar la identidad.
  $env:MESA_FALSO_MODO = 'bloqueo'
  $pruebaLock = Join-Path $raiz 'identidad.lock'
  $lock = [IO.File]::Open($pruebaLock, 'OpenOrCreate', 'ReadWrite', 'None')
  $estado = @{ intentos = 0; vivo = $false; guardado = $false }
  try {
    $r = Invocar-ProcesoMesa -Ejecutable $codex -Directorio $raiz -Log (Join-Path $raiz 'candado.log') -Segundos 3 -AlIniciar {
      param($id)
      $estado.intentos++
      if ($estado.intentos -eq 2) { $estado.vivo = Mesa-ProcesoVivo $id.cli_pid $id.cli_inicio $id.cli_nombre; $lock.Dispose() }
      $c = [IO.File]::Open($pruebaLock, 'OpenOrCreate', 'ReadWrite', 'None')
      $c.Dispose(); $estado.guardado = $true; return $true
    }
  } finally { $lock.Dispose() }
  Caso 'Candado ocupado no mata CLI y reintenta' 'CLI sigue vivo hasta timeout y segunda escritura funciona' "intentos=$($estado.intentos), vivo=$($estado.vivo), guardado=$($estado.guardado), salida=$($r.salida)" ($estado.intentos -ge 2 -and $estado.vivo -and $estado.guardado -and $r.salida -eq 124)
} catch {
  $script:fallos++; Write-Host "ERROR de la prueba: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)"
} finally {
  foreach ($clave in $guardado.Keys) { [Environment]::SetEnvironmentVariable($clave, $guardado[$clave], 'Process') }
  if ($Conservar) { Write-Host "Copia conservada en $raiz" }
  else {
    $destino = [IO.Path]::GetFullPath($raiz)
    if ($destino.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\mesa-procesos-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $destino -Recurse -Force -ErrorAction SilentlyContinue }
  }
}
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
