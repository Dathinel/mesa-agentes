# Prepara una instalación: configuración propia, exclusiones y las instrucciones de los tres agentes (CLAUDE.md, AGENTS.md
# y GEMINI.md), generadas desde plantillas\protocolo.md. Nada de esto se versiona. Es idempotente: no pisa lo que ya existe
# salvo con -Regenerar (que solo rehace las tres instrucciones).
# Uso: instalar.ps1 [-Regenerar]
param([switch]$Regenerar)
. "$PSScriptRoot\comun.ps1"
New-Item -ItemType Directory -Force -Path $Global:Mesa_Raiz | Out-Null

$cfg = Join-Path $Global:Mesa_Raiz 'mesa.json'
if (-not (Test-Path -LiteralPath $cfg)) {
  $c = Mesa-LeerJson (Join-Path $Global:Mesa_Base 'datos\mesa.ejemplo.json')
  $c.humano = $env:USERNAME
  Mesa-EscribirJson $cfg $c
  Write-Output "Creada la configuración $cfg (persona: $env:USERNAME; cámbialo en «humano»)."
}
$excl = Join-Path $Global:Mesa_Raiz 'excluidos.txt'
if (-not (Test-Path -LiteralPath $excl)) {
  [IO.File]::WriteAllText($excl, "# Una expresión regular por línea: carpetas o proyectos que ningún agente debe tocar ni mostrar.`r`n", (New-Object Text.UTF8Encoding $false))
  Write-Output "Creado $excl (vacío)."
}

$plantilla = [IO.File]::ReadAllText((Join-Path $Global:Mesa_Base 'plantillas\protocolo.md'), [Text.Encoding]::UTF8)
$lineas = @([IO.File]::ReadAllLines($excl) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
$humano = (Mesa-LeerJson $cfg).humano
$texto = $plantilla.Replace('{HUMANO}', $(if ($humano) { $humano } else { 'el usuario' })).Replace('{HERRAMIENTAS}', (Join-Path $Global:Mesa_Base 'herramientas') + '\').
  Replace('{EXCLUIDOS}', $(if ($lineas.Count) { ' (' + (($lineas -join '|') -split '\|' -join ', ') + ')' } else { '' }))
foreach ($n in 'CLAUDE.md', 'AGENTS.md', 'GEMINI.md') {
  $f = Join-Path $Global:Mesa_Base $n
  if ($Regenerar -or -not (Test-Path -LiteralPath $f)) { [IO.File]::WriteAllText($f, $texto, (New-Object Text.UTF8Encoding $false)); Write-Output "Generado $n." }
}
