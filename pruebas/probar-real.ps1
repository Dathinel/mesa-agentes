# Prueba real de solo lectura (gasta muy poca cuota): codex y agy a la vez, con -Lectura sobre un repo, modelos baratos.
# Comprueba salida 0, estado hecho, respuesta y tokens del evento final, git status intacto, ningún worktree y cpu_lanzador_s < 5.
# Uso: probar-real.ps1 [-Dir <repo>] [-Solo codex|agy]
param([string]$Dir = 'D:\Programas de uso libre\Herramientas-IA\Lanzador', [string]$Solo)
$ErrorActionPreference = 'Stop'
$base = Split-Path -Parent $PSScriptRoot
. "$base\herramientas\comun.ps1"
$script:fallos = 0
function Caso($nombre, $esperado, $obtenido, [bool]$ok) { if (-not $ok) { $script:fallos++ }; Write-Host ("[{0}] {1}`n      esperado: {2}`n      obtenido: {3}" -f $(if ($ok) { 'OK' } else { 'FALLO' }), $nombre, $esperado, $obtenido) }
$md = Join-Path $Global:Mesa_Raiz 'encargos\lectura-real.md'
New-Item -ItemType Directory -Force (Split-Path $md) | Out-Null
[IO.File]::WriteAllText($md, "Lee README.md y resume en tres líneas qué hace. No modifiques nada.`n", (New-Object Text.UTF8Encoding $false))
$antes = (& git -C $Dir status --porcelain | Out-String)
$wtAntes = (& git -C $Dir worktree list | Out-String)
# El patrón se compone para que esta misma orden no se cuente; se excluyen este proceso y su padre (la consola que lo lanzó).
$patron = 'mesa-' + 'agentes'; $padre = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId
function Residentes { @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $patron -and $_.ProcessId -notin @($PID, $padre) }).Count }
$procesosAntes = Residentes
$lanzados = @{}
foreach ($a in @(@{ a = 'codex'; m = 'gpt-6-luna'; e = @('-Esfuerzo', 'low') }, @{ a = 'agy'; m = 'gemini-3.8-flash-low'; e = @() })) {
  if ($Solo -and $a.a -ne $Solo) { continue }
  $salida = Join-Path $env:TEMP "cuadrilla-real-$($a.a).txt"
  $lista = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$base\herramientas\cuadrilla.ps1`"", 'delegar', '-A', $a.a, '-Encargo', "`"$md`"", '-Dir', "`"$Dir`"", '-Modelo', $a.m, '-Lectura', '-Minutos', '15') + $a.e
  $lanzados[$a.a] = @{ p = (Start-Process powershell.exe -ArgumentList $lista -WindowStyle Hidden -PassThru -RedirectStandardOutput $salida); salida = $salida }
  $null = $lanzados[$a.a].p.Handle
}
foreach ($a in $lanzados.Keys) {
  $l = $lanzados[$a]; $l.p.WaitForExit()
  $texto = [IO.File]::ReadAllText($l.salida, [Text.Encoding]::UTF8)
  $r = if ($texto -match '(?m)^(.+\\resultado\.json)\s*$') { Mesa-LeerJson $Matches[1] }
  Caso "$a termina bien" 'salida 0, hecho, respuesta no vacía, tokens medidos, cpu_lanzador_s < 5' "codigo=$($l.p.ExitCode), estado=$($r.estado), causa=$($r.causa), tokens=$($r.tokens.total), cpu=$($r.cpu_lanzador_s), avisos=$($r.avisos -join ';')`n$($texto.Trim())" ($l.p.ExitCode -eq 0 -and $r.estado -eq 'hecho' -and $r.respuesta.Length -gt 20 -and $r.tokens.total -gt 0 -and $r.cpu_lanzador_s -lt 5 -and -not $r.worktree)
}
$despues = (& git -C $Dir status --porcelain | Out-String)
Caso 'git status idéntico y sin worktree' 'mismo porcelain y misma lista de worktrees' "igual=$($antes -eq $despues), worktrees=$(($wtAntes -eq (& git -C $Dir worktree list | Out-String)))" ($antes -eq $despues -and $wtAntes -eq (& git -C $Dir worktree list | Out-String))
Caso 'ningún proceso de la mesa en reposo' "$procesosAntes antes y 0 después" (Residentes) ((Residentes) -eq 0)
Write-Host "`nFallos: $script:fallos"
exit $script:fallos
