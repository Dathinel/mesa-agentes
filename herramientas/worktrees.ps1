# Un worktree por agente y tarea, con la misma regla en todos los repos: <repo>\.claude\worktrees\<agente>-<tarea>,
# rama <agente>/<tarea>, creado desde la rama principal actualizada. Solo en carpetas que son repositorios git.
# Uso:
#   worktrees.ps1 crear -Dir <carpeta del repo> -Agente codex -Tarea <id>     (escribe la ruta del worktree)
#   worktrees.ps1 lista [-Json]                                              (los de la mesa en los repos de la carpeta de trabajo)
#   worktrees.ps1 limpiar                                                    (quita solo los integrados y limpios; lista los demás)
param(
  [Parameter(Position = 0, Mandatory = $true)][ValidateSet('crear', 'lista', 'limpiar')][string]$Comando,
  [string]$Dir,
  [string]$Agente,
  [string]$Tarea,
  [switch]$Json
)
# Continue y no Stop (aunque lo herede de quien llama): en PowerShell 5.1 el stderr de git, aunque vaya a $null, se volvería una excepción.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\comun.ps1"

function Raiz-Repo($d) { $r = (& git -C $d rev-parse --show-toplevel 2>$null); if ($LASTEXITCODE -eq 0 -and $r) { [IO.Path]::GetFullPath($r) } }
function Rama-Principal($repo) {
  $r = (& git -C $repo symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null)
  if ($r) { return $r }
  foreach ($c in 'origin/main', 'origin/master', 'main', 'master') { & git -C $repo rev-parse --verify --quiet $c 2>$null | Out-Null; if ($LASTEXITCODE -eq 0) { return $c } }
  'HEAD'
}
# Los worktrees de la mesa: los de .claude\worktrees con rama claude/, codex/ o agy/. Los demás (de otras herramientas) no se tocan.
function Worktrees-Mesa($repo) {
  $actual = $null
  foreach ($l in @(& git -C $repo worktree list --porcelain 2>$null) + '') {
    if ($l -like 'worktree *') { $actual = @{ ruta = [IO.Path]::GetFullPath($l.Substring(9)) } }
    elseif ($l -like 'branch refs/heads/*') { $actual.rama = $l.Substring(18) }
    elseif (-not $l -and $actual) {
      if ($actual.rama -match '^(claude|codex|agy)/(.+)$' -and $actual.ruta -like "*\.claude\worktrees\*") {
        $sucio = @(& git -C $actual.ruta status --porcelain 2>$null).Count
        $principal = Rama-Principal $repo
        & git -C $repo merge-base --is-ancestor $actual.rama $principal 2>$null; $integrada = $LASTEXITCODE -eq 0
        [pscustomobject]@{ repo = $repo; ruta = $actual.ruta; rama = $actual.rama; agente = $Matches[1]; tarea = $Matches[2]; sin_confirmar = $sucio; integrada = $integrada }
      }
      $actual = $null
    }
  }
}
# A dos niveles: Herramientas-IA\Subtitular, Rastrear y Lanzador quedaban fuera de lista, limpiar y del tope.
function Repos { @(Get-ChildItem -LiteralPath $Global:Mesa_DefaultDir -Directory -Depth 1 -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } | ForEach-Object FullName) }
# Agente con un encargo en marcha: su candado datos	rabajos\<agente>.lock está tomado.
function Ocupado($agente) {
  try { $c = [IO.File]::Open((Join-Path $Global:Mesa_Raiz "trabajos\$agente.lock"), 'OpenOrCreate', 'ReadWrite', 'None'); $c.Dispose(); $false } catch { $true }
}

switch ($Comando) {
  'crear' {
    if (-not $Dir -or -not $Agente -or -not $Tarea) { throw 'Uso: worktrees.ps1 crear -Dir <repo> -Agente <agente> -Tarea <id>' }
    if ($Tarea -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Tarea: solo minúsculas, cifras y guiones.' }
    $repo = Raiz-Repo $Dir
    if (-not $repo) { throw "$Dir no es un repositorio git: se trabaja con reclamos, sin worktree." }
    $max = [int]$(if ((Mesa-LeerJson (Mesa-ConfigPath)).worktrees.max_por_agente) { (Mesa-LeerJson (Mesa-ConfigPath)).worktrees.max_por_agente } else { 3 })
    $vivos = @(@(Repos) + $repo | Select-Object -Unique | ForEach-Object { Worktrees-Mesa $_ } | Where-Object { $_.agente -eq $Agente })
    $ruta = Join-Path $repo ".claude\worktrees\$Agente-$Tarea"
    if (Test-Path -LiteralPath $ruta) {
      # Un apagón a mitad de git worktree add deja la carpeta sin su .git: no se arranca un CLI sobre un árbol a medias.
      if (-not (Test-Path -LiteralPath (Join-Path $ruta '.git'))) { throw "$ruta existe pero no es un worktree (quedó a medias): bórralo y ejecuta git worktree prune en el repo" }
      Write-Output $ruta; return
    }
    if ($vivos.Count -ge $max) { throw "$Agente ya tiene $($vivos.Count) worktrees vivos (tope $max): $(@($vivos | ForEach-Object rama) -join ', '). Intégralos o límpialos antes." }
    # Que .claude\worktrees no aparezca como cambio del repo: exclusión local, sin tocar su .gitignore.
    $excl = Join-Path $repo '.git\info\exclude'
    & git -C $repo check-ignore -q '.claude/worktrees/x' 2>$null
    if ($LASTEXITCODE -ne 0 -and (Test-Path -LiteralPath (Split-Path $excl))) { Add-Content -LiteralPath $excl -Value '/.claude/worktrees/' -Encoding ASCII }
    & git -C $repo fetch --quiet origin 2>$null
    $base = Rama-Principal $repo
    $rama = "$Agente/$Tarea"
    # Dos delegar a la vez sobre el mismo repo (codex y agy) chocan en los candados de git: se reintenta.
    $error_ = ''
    foreach ($intento in 1..3) {
      & git -C $repo show-ref --verify --quiet "refs/heads/$rama" 2>$null
      $error_ = if ($LASTEXITCODE -eq 0) { & git -C $repo worktree add --quiet $ruta $rama 2>&1 | Out-String } else { & git -C $repo worktree add --quiet -b $rama $ruta $base 2>&1 | Out-String }
      if (Test-Path -LiteralPath $ruta) { break }
      Start-Sleep -Seconds (2 * $intento)
    }
    if (-not (Test-Path -LiteralPath $ruta)) { throw "git worktree add falló en $repo ($rama desde $base): $($error_.Trim())" }
    Write-Output $ruta
  }
  'lista' {
    $items = @(Repos | ForEach-Object { Worktrees-Mesa $_ })
    if ($Json) { ConvertTo-Json -InputObject $items -Depth 3 } elseif (-not $items.Count) { '(sin worktrees de la mesa)' }
    else { $items | Format-Table agente, rama, sin_confirmar, integrada, ruta -AutoSize | Out-String -Width 220 }
  }
  'limpiar' {
    foreach ($w in @(Repos | ForEach-Object { Worktrees-Mesa $_ })) {
      # Nunca se borra trabajo: con cambios sin confirmar o sin integrar, decide la persona. Uno recién creado está «integrado y limpio»: se respeta mientras el agente trabaja.
      if (Ocupado $w.agente) { "Se queda ($($w.agente) tiene un encargo en marcha): $($w.ruta)"; continue }
      if ($w.integrada -and $w.sin_confirmar -eq 0) {
        & git -C $w.repo worktree remove $w.ruta 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { & git -C $w.repo branch -d $w.rama 2>&1 | Out-Null; "Quitado (integrado y limpio): $($w.rama)" } else { "No se pudo quitar: $($w.ruta)" }
      } else {
        "Se queda para que decidas: $($w.rama) en $($w.ruta) ($(if ($w.sin_confirmar) { "$($w.sin_confirmar) cambios sin confirmar" } else { 'sin cambios pendientes' }), $(if ($w.integrada) { 'integrada' } else { 'sin integrar' }))"
      }
    }
  }
}
