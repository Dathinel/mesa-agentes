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
  $nuevos = @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Recurse -Filter '*-*.json' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -gt $desde -and $_.Directory.Name -ne 'logs' } | ForEach-Object {
      $m = Mesa-LeerMensaje $_.FullName
      if ($m -and $m.tipo -ne 'encargo' -and (Mesa-NormalizarHerramienta $m.autor) -ne $yo -and
          ($m.tipo -in @('avance-inicio', 'avance-alcance', 'avance-bloqueo', 'lider') -or
           @(([string]$m.para) -split '[,;]' | Where-Object { (Mesa-NormalizarHerramienta $_.Trim()) -eq $yo -or $_.Trim() -eq 'todos' }).Count)) {
        $t = [string]$m.texto
        '{0} #{1} {2} -> {3} [{4}]: {5}' -f $_.Directory.Name, $m.n, $m.autor, $m.para, $m.tipo, $(if ($t.Length -gt 600) { $t.Substring(0, 600) + '…' } else { $t })
      }
    })
  if ($nuevos.Count) { 'NOVEDADES PARA ' + $yo; $nuevos; exit 0 }
}
"SIN NOVEDADES en $MaxMin min: vuelve a lanzarme."
