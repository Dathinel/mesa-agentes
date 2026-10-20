# Bloquea hasta que llegue a la Mesa algo para este agente y lo imprime: así una sesión interactiva se entera sin que la persona le escriba.
# Uso (en segundo plano en la sesión del agente): esperar-novedades.ps1 -Para claude [-MaxMin 55] [-Intervalo 15]
# Cuenta lo dirigido a mí o a 'todos', los avance inicio/alcance/bloqueo de cualquiera y los cambios de líder. Al salir, se vuelve a lanzar.
param(
  [Parameter(Mandatory = $true)][string]$Para,
  [int]$MaxMin = 55,
  [int]$Intervalo = 15
)
. "$PSScriptRoot\comun.ps1"
$yo = Mesa-NormalizarHerramienta $Para
$desde = Get-Date
$fin = $desde.AddMinutes($MaxMin)
while ((Get-Date) -lt $fin) {
  Start-Sleep -Seconds $Intervalo
  $nuevos = @(Mesa-Novedades $yo $desde)
  if ($nuevos.Count) { 'NOVEDADES PARA ' + $yo; $nuevos; exit 0 }
}
"SIN NOVEDADES en $MaxMin min: vuelve a lanzarme."