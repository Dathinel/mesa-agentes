# Los callbacks nativos no tienen runspace: encolan las líneas y la consola las pinta desde PowerShell.
if (-not ('Mesa.Proceso' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace Mesa {
  public sealed class Proceso : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct Limites {
      public long TiempoProceso, TiempoJob;
      public uint Banderas;
      public UIntPtr Minimo, Maximo;
      public uint Procesos;
      public UIntPtr Afinidad;
      public uint Prioridad, Planificacion;
    }
    [StructLayout(LayoutKind.Sequential)] struct Contadores {
      public ulong Lecturas, Escrituras, Otros, BytesLectura, BytesEscritura, BytesOtros;
    }
    [StructLayout(LayoutKind.Sequential)] struct LimitesExtendidos {
      public Limites Basicos;
      public Contadores IO;
      public UIntPtr MemoriaProceso, MemoriaJob, PicoProceso, PicoJob;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr seguridad, string nombre);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int clase, ref LimitesExtendidos info, uint tamano);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proceso);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job, uint codigo);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    readonly Process proceso = new Process();
    readonly object cerrojo = new object();
    readonly ConcurrentQueue<string> lineas = new ConcurrentQueue<string>();
    readonly ManualResetEvent salidaFin = new ManualResetEvent(false), errorFin = new ManualResetEvent(false);
    StreamWriter log;
    IntPtr job;
    Task entrada;
    bool ver, cerrado;
    string fallo;
    public int Id { get; private set; }
    public string Inicio { get; private set; }
    public string Nombre { get; private set; }
    public bool Terminado { get { return proceso.HasExited; } }
    public int Codigo { get { return proceso.ExitCode; } }
    public string Fallo { get { return fallo; } }

    public static string Citar(string valor) {
      StringBuilder s = new StringBuilder("\"");
      int barras = 0;
      foreach (char c in valor) {
        if (c == '\\') { barras++; continue; }
        if (c == '"') { s.Append('\\', barras * 2 + 1); s.Append(c); }
        else { s.Append('\\', barras); s.Append(c); }
        barras = 0;
      }
      s.Append('\\', barras * 2); s.Append('"'); return s.ToString();
    }
    void Guardar(string linea) {
      if (linea == null) return;
      lock (cerrojo) {
        if (cerrado) return;
        try { log.WriteLine(linea); if (ver) lineas.Enqueue(linea); }
        catch (Exception e) { fallo = e.Message; }
      }
    }
    public string Siguiente() { string linea; return lineas.TryDequeue(out linea) ? linea : null; }
    public void Iniciar(string ejecutable, string argumentos, string directorio, string archivoLog, string texto, bool mostrar) {
      ver = mostrar;
      log = new StreamWriter(archivoLog, false, new UTF8Encoding(false)); log.AutoFlush = true;
      job = CreateJobObject(IntPtr.Zero, null);
      if (job == IntPtr.Zero) throw new Win32Exception();
      var limites = new LimitesExtendidos(); limites.Basicos.Banderas = 0x2000; // KILL_ON_JOB_CLOSE conserva el árbol aunque muera su raíz.
      if (!SetInformationJobObject(job, 9, ref limites, (uint)Marshal.SizeOf(limites))) throw new Win32Exception();
      var info = new ProcessStartInfo(ejecutable, argumentos);
      info.WorkingDirectory = directorio; info.UseShellExecute = false; info.CreateNoWindow = true;
      info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
      info.StandardOutputEncoding = new UTF8Encoding(false); info.StandardErrorEncoding = new UTF8Encoding(false);
      proceso.StartInfo = info;
      proceso.OutputDataReceived += (s,e) => { if (e.Data == null) salidaFin.Set(); else Guardar(e.Data); };
      proceso.ErrorDataReceived += (s,e) => { if (e.Data == null) errorFin.Set(); else Guardar(e.Data); };
      proceso.Start();
      Id = proceso.Id; Inicio = proceso.StartTime.ToUniversalTime().ToString("o"); Nombre = proceso.ProcessName;
      if (!AssignProcessToJobObject(job, proceso.Handle)) {
        int error = Marshal.GetLastWin32Error();
        if (!proceso.HasExited) { proceso.Kill(); throw new Win32Exception(error); }
      }
      proceso.BeginOutputReadLine(); proceso.BeginErrorReadLine();
      entrada = Task.Run(() => {
        try {
          byte[] bytes = new UTF8Encoding(false).GetBytes(texto ?? "");
          proceso.StandardInput.BaseStream.Write(bytes, 0, bytes.Length);
          proceso.StandardInput.BaseStream.Flush();
        } catch (Exception e) { fallo = "stdin: " + e.Message; }
        finally { try { proceso.StandardInput.Close(); } catch {} }
      });
    }
    public void Cortar() {
      if (job != IntPtr.Zero && !TerminateJobObject(job, 124)) throw new Win32Exception();
    }
    public void Drenar() {
      // Un descendiente puede retener stdout aun después de morir el CLI.
      Cortar();
      if (!proceso.WaitForExit(5000)) throw new TimeoutException("El árbol no terminó.");
      if (!salidaFin.WaitOne(5000) || !errorFin.WaitOne(5000)) throw new TimeoutException("No se cerraron las tuberías del CLI.");
      if (entrada != null) entrada.Wait(2000);
    }
    public void Dispose() {
      if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
      lock (cerrojo) { cerrado = true; if (log != null) log.Dispose(); }
      proceso.Dispose();
      // Los callbacks pueden estar terminando si falló Iniciar; sus eventos siguen siendo válidos.
    }
  }
}
'@
}

function Mesa-LimiteSegundos($cfg, [string]$hiloId) {
  $clave = if ($hiloId -like 'charla-*') { 'charla_min' } else { 'encargo_min' }
  $minutos = if ($clave -eq 'charla_min') { 20.0 } else { 90.0 }
  if ($cfg.limites -and $cfg.limites.$clave -and [double]$cfg.limites.$clave -gt 0) { $minutos = [double]$cfg.limites.$clave }
  return $minutos * 60.0
}

function Invocar-ProcesoMesa {
  param([string]$Ejecutable, [string[]]$Argumentos = @(), [string]$Entrada = '', [string]$Directorio,
    [string]$Log, [double]$Segundos = 5400, [switch]$Ver, [scriptblock]$AlIniciar)
  $ruta = (Get-Command $Ejecutable -ErrorAction Stop | Select-Object -First 1).Source
  $shimCodex = Join-Path (Split-Path -Parent $ruta) 'node_modules\@openai\codex\bin\codex.js'
  if ([IO.Path]::GetFileNameWithoutExtension($ruta) -eq 'codex' -and [IO.Path]::GetExtension($ruta) -in @('.ps1', '.cmd') -and (Test-Path -LiteralPath $shimCodex)) {
    $nodeLocal = Join-Path (Split-Path -Parent $ruta) 'node.exe'
    $ruta = if (Test-Path -LiteralPath $nodeLocal) { $nodeLocal } else { (Get-Command node.exe -ErrorAction Stop).Source }
    $Argumentos = @($shimCodex) + $Argumentos
  }
  if ([IO.Path]::GetExtension($ruta) -in @('.cmd', '.bat')) {
    # Los shims npm tienen un .ps1 hermano: evita una segunda interpretación de cmd.exe (% y metacaracteres).
    $hermano = [IO.Path]::ChangeExtension($ruta, '.ps1')
    if (-not (Test-Path -LiteralPath $hermano)) { throw "El lanzador requiere el shim .ps1 junto a $ruta" }
    $ruta = $hermano
  }
  if ([IO.Path]::GetExtension($ruta) -eq '.ps1') {
    $literales = @($ruta) + @($Argumentos) | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
    $orden = '$ProgressPreference = "SilentlyContinue"; $OutputEncoding = [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; & ' + ($literales -join ' ')
    $orden += '; if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }'
    $ruta = (Get-Command powershell.exe -ErrorAction Stop).Source
    $Argumentos = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($orden)))
  }
  $argsTexto = (@($Argumentos | ForEach-Object { [Mesa.Proceso]::Citar($_) }) -join ' ')
  $proceso = New-Object Mesa.Proceso
  $reloj = [Diagnostics.Stopwatch]::StartNew()
  $tiempo = $false
  try {
    $proceso.Iniciar($ruta, $argsTexto, $Directorio, $Log, $Entrada, [bool]$Ver)
    $identidad = [pscustomobject]@{ cli_pid = $proceso.Id; cli_inicio = $proceso.Inicio; cli_nombre = $proceso.Nombre }
    if ($AlIniciar) { & $AlIniciar $identidad | Out-Null }
    while (-not $proceso.Terminado) {
      if ($reloj.Elapsed.TotalSeconds -ge $Segundos) { $tiempo = $true; $proceso.Cortar(); break }
      if ($Ver) { while ($null -ne ($linea = $proceso.Siguiente())) { Mostrar-Linea $linea } }
      Start-Sleep -Milliseconds 40
    }
    $proceso.Drenar()
    if ($Ver) { while ($null -ne ($linea = $proceso.Siguiente())) { Mostrar-Linea $linea } }
    $codigo = if ($tiempo) { 124 } else { $proceso.Codigo }
    if ($proceso.Fallo -and -not $tiempo -and $codigo -eq 0) {
      [IO.File]::AppendAllText($Log, "ERROR: $($proceso.Fallo)`n", (New-Object Text.UTF8Encoding $false)); $codigo = 1
    }
    return [pscustomobject]@{ salida = $codigo; causa = $(if ($tiempo) { 'tiempo' } else { $null }); identidad = $identidad }
  } finally { $proceso.Dispose() }
}
