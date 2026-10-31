# Prepara una instalación: datos\mesa.json (desde el ejemplo), datos\trabajos\ y la skill de Claude Code en
# %USERPROFILE%\.claude\skills\cuadrilla\, copiada solo si difiere. Idempotente.
. "$PSScriptRoot\comun.ps1"
New-Item -ItemType Directory -Force (Join-Path $Global:Mesa_Raiz 'trabajos') | Out-Null
$cfg = Join-Path $Global:Mesa_Raiz 'mesa.json'
$ejemplo = Join-Path $Global:Mesa_Base 'datos\mesa.ejemplo.json'
if (-not (Test-Path -LiteralPath $cfg)) { Copy-Item -LiteralPath $ejemplo -Destination $cfg; "Creada $cfg" }
else {
  # Solo las claves del ejemplo (las de la v1 sobran) y las que falten se rellenan; el original queda en mesa.v1.json.
  $ej = Mesa-LeerJson $ejemplo; $real = Mesa-LeerJson $cfg; $nuevo = [ordered]@{}
  foreach ($k in $ej.PSObject.Properties.Name) {
    $v = if ($null -ne $real.$k) { $real.$k } else { $ej.$k }
    if ($ej.$k -is [Management.Automation.PSCustomObject]) { $o = [ordered]@{}; foreach ($s in $ej.$k.PSObject.Properties.Name) { $o[$s] = if ($null -ne $v.$s) { $v.$s } else { $ej.$k.$s } }; $v = $o }
    $nuevo[$k] = $v
  }
  if (($nuevo | ConvertTo-Json -Depth 10) -ne ($real | ConvertTo-Json -Depth 10)) {
    Copy-Item -LiteralPath $cfg -Destination (Join-Path $Global:Mesa_Raiz 'mesa.v1.json'); Mesa-EscribirJson $cfg $nuevo; "Normalizado $cfg (el anterior queda en mesa.v1.json)"
  }
}
$excl = Join-Path $Global:Mesa_Raiz 'excluidos.txt'
if (-not (Test-Path -LiteralPath $excl)) { [IO.File]::WriteAllText($excl, "# Una expresión regular por línea: carpetas que ningún agente debe tocar ni mostrar.`r`n", (New-Object Text.UTF8Encoding $false)); "Creado $excl (vacío)" }
$origen = Join-Path $Global:Mesa_Base 'plantillas\cuadrilla\SKILL.md'
$destino = Join-Path $env:USERPROFILE '.claude\skills\cuadrilla\SKILL.md'
if (-not (Test-Path -LiteralPath $destino) -or (Get-FileHash $origen).Hash -ne (Get-FileHash $destino).Hash) {
  New-Item -ItemType Directory -Force (Split-Path $destino) | Out-Null
  Copy-Item -LiteralPath $origen -Destination $destino -Force; "Skill instalada en $destino"
} else { 'Skill al día.' }
