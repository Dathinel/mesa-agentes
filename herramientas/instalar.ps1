# Prepara una instalación: datos\mesa.json (desde el ejemplo), datos\trabajos\ y la skill de Claude Code en
# %USERPROFILE%\.claude\skills\cuadrilla\, copiada solo si difiere. Idempotente.
. "$PSScriptRoot\comun.ps1"
New-Item -ItemType Directory -Force (Join-Path $Global:Mesa_Raiz 'trabajos') | Out-Null
$cfg = Join-Path $Global:Mesa_Raiz 'mesa.json'
if (-not (Test-Path -LiteralPath $cfg)) { Copy-Item -LiteralPath (Join-Path $Global:Mesa_Base 'datos\mesa.ejemplo.json') -Destination $cfg; "Creada $cfg" }
$excl = Join-Path $Global:Mesa_Raiz 'excluidos.txt'
if (-not (Test-Path -LiteralPath $excl)) { [IO.File]::WriteAllText($excl, "# Una expresión regular por línea: carpetas que ningún agente debe tocar ni mostrar.`r`n", (New-Object Text.UTF8Encoding $false)); "Creado $excl (vacío)" }
$origen = Join-Path $Global:Mesa_Base 'plantillas\cuadrilla\SKILL.md'
$destino = Join-Path $env:USERPROFILE '.claude\skills\cuadrilla\SKILL.md'
if (-not (Test-Path -LiteralPath $destino) -or (Get-FileHash $origen).Hash -ne (Get-FileHash $destino).Hash) {
  New-Item -ItemType Directory -Force (Split-Path $destino) | Out-Null
  Copy-Item -LiteralPath $origen -Destination $destino -Force; "Skill instalada en $destino"
} else { 'Skill al día.' }
