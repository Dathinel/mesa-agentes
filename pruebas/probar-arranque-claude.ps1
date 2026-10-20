# Captura los argumentos de Terminal y usa un Claude falso: sin ventanas, modelos ni sesiones reales.
param()
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
$raiz = Join-Path $env:TEMP ('cuadrilla-arranque-' + [Guid]::NewGuid().ToString('N'))
$mesa = Join-Path $raiz 'mesa con espacios'
$datos = Join-Path $mesa 'datos'
$trabajo = Join-Path $raiz 'trabajo con espacios'
$script:fallos = 0
function Caso($nombre, [bool]$ok, $detalle) {
  if (-not $ok) { $script:fallos++ }
  Write-Host "$(if ($ok) { 'OK' } else { 'FALLO' }) $nombre`: $detalle"
}
function Ejecutar-Cmd([string]$orden) {
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $env:ComSpec
  $info.Arguments = '/d /c ' + $orden
  $info.UseShellExecute = $false; $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
  $info.EnvironmentVariables['MESA_DATOS'] = $datos
  $info.EnvironmentVariables['MESA_TRABAJO'] = $trabajo
  $info.EnvironmentVariables['PATH'] = $raiz + ';' + $env:PATH
  $info.EnvironmentVariables['CUADRILLA_CAPTURA'] = Join-Path $raiz 'argumentos.txt'
  $info.EnvironmentVariables['CUADRILLA_LLAMADAS'] = Join-Path $raiz 'llamadas.txt'
  $proceso = New-Object Diagnostics.Process
  $proceso.StartInfo = $info
  try {
    [void]$proceso.Start()
    $salida = $proceso.StandardOutput.ReadToEndAsync(); $errores = $proceso.StandardError.ReadToEndAsync()
    if (-not $proceso.WaitForExit(10000)) { $proceso.Kill(); throw 'La prueba de arranque se atascó.' }
    return [pscustomobject]@{ salida = $salida.Result; error = $errores.Result; codigo = $proceso.ExitCode }
  } finally { $proceso.Dispose() }
}
function Decodificar([string]$valor) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($valor)) }
function Llamadas {
  $f = Join-Path $raiz 'llamadas.txt'
  if (Test-Path -LiteralPath $f) { foreach ($linea in [IO.File]::ReadAllLines($f)) { ,@($linea.Split('|') | ForEach-Object { Decodificar $_ }) } }
}
try {
  New-Item -ItemType Directory -Force (Join-Path $mesa 'herramientas'), $datos, $trabajo | Out-Null
  Copy-Item -LiteralPath (Join-Path $base 'Cuadrilla.bat') -Destination $mesa
  Copy-Item -LiteralPath (Join-Path $base 'herramientas\abrir-claude.cmd') -Destination (Join-Path $mesa 'herramientas')
  $fuente = @'
using System;
using System.IO;
using System.Text;
class CliFalso {
  static int Main(string[] args) {
    string[] codificados = Array.ConvertAll(args, a => Convert.ToBase64String(Encoding.UTF8.GetBytes(a)));
    if (Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]) == "wt-falso") {
      File.WriteAllLines(Environment.GetEnvironmentVariable("CUADRILLA_CAPTURA"), codificados);
      return 0;
    }
    File.AppendAllText(Environment.GetEnvironmentVariable("CUADRILLA_LLAMADAS"), string.Join("|", codificados) + "\n");
    return args.Length > 0 && args[0] == "--continue" ? 1 : 0;
  }
}
'@
  Add-Type -TypeDefinition $fuente -OutputAssembly (Join-Path $raiz 'wt-falso.exe') -OutputType ConsoleApplication
  Copy-Item -LiteralPath (Join-Path $raiz 'wt-falso.exe') -Destination (Join-Path $raiz 'claude.exe')
  $r = Ejecutar-Cmd ('call "' + (Join-Path $mesa 'Cuadrilla.bat') + '" prueba')
  $comando = $r.salida.Trim().Replace('COMANDO_WT: wt ', ('"' + (Join-Path $raiz 'wt-falso.exe') + '" '))
  $archivo = Join-Path $raiz 'capturar.cmd'
  [IO.File]::WriteAllText($archivo, "@echo off`r`n$comando`r`n", [Text.Encoding]::Default)
  $r = Ejecutar-Cmd ('call "' + $archivo + '"')
  $argumentos = @([IO.File]::ReadAllLines((Join-Path $raiz 'argumentos.txt')) | ForEach-Object { Decodificar $_ })
  $inicioCmd = [Array]::IndexOf($argumentos, 'cmd')
  $separador = [Array]::IndexOf($argumentos, ';')
  $panel = @($argumentos[($inicioCmd + 1)..($separador - 1)])
  $lanzador = Join-Path $mesa 'herramientas\abrir-claude.cmd'
  Caso 'Terminal recibe la ruta del lanzador entera' ($panel -contains $lanzador) ($panel -join ' | ')
  Caso 'Terminal recibe la carpeta de trabajo entera' ($panel -contains $trabajo) $trabajo
  Caso 'Los cuatro paneles siguen separados' (@($argumentos | Where-Object { $_ -eq ';' }).Count -eq 3) 'tres separadores'
  if ($panel -contains $lanzador -and $panel -contains $trabajo) {
    # /c sustituye a /k solo en la prueba para que la consola termine por sí sola.
    $ordenPanel = @($panel | ForEach-Object { if ($_ -eq '/k') { '/c' } elseif ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $r = Ejecutar-Cmd ($ordenPanel -replace '^/d /c ', '')
    $ll = @(Llamadas)
    Caso 'Sin conversación anterior abre una nueva' ($r.codigo -eq 0 -and $ll.Count -eq 2 -and $ll[0][0] -eq '--continue' -and $ll[1][0] -eq '--add-dir' -and $ll[1][1] -eq $trabajo) "llamadas=$($ll.Count), codigo=$($r.codigo), error=$($r.error)"
  }
  [IO.File]::WriteAllText((Join-Path $raiz 'llamadas.txt'), '')
  $r = Ejecutar-Cmd ('call "' + $lanzador + '" "' + $trabajo + '" nuevo')
  $ll = @(Llamadas)
  Caso 'Modo nuevo inicia directamente' ($r.codigo -eq 0 -and $ll.Count -eq 1 -and $ll[0][0] -eq '--add-dir' -and $ll[0][1] -eq $trabajo) "llamadas=$($ll.Count), codigo=$($r.codigo)"
  [IO.File]::WriteAllText((Join-Path $datos 'sesion-claude.txt'), '00000000-0000-4000-8000-000000000001')
  [IO.File]::WriteAllText((Join-Path $raiz 'llamadas.txt'), '')
  $r = Ejecutar-Cmd ('call "' + $lanzador + '" "' + $trabajo + '"')
  $ll = @(Llamadas)
  Caso 'Reanuda un identificador sintético' ($r.codigo -eq 0 -and $ll.Count -eq 1 -and $ll[0][0] -eq '--resume' -and $ll[0][3] -eq $trabajo) "llamadas=$($ll.Count), codigo=$($r.codigo)"
} catch { $script:fallos++; Write-Host "ERROR: $($_.Exception.Message) $($_.InvocationInfo.PositionMessage)" }
finally {
  $destino = [IO.Path]::GetFullPath($raiz)
  if ($destino.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\cuadrilla-arranque-', [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $destino -Recurse -Force }
}
Write-Host "Fallos: $script:fallos"
exit $script:fallos
