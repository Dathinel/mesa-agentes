# Lanza ejecutar.ps1 oculto y vuelve enseguida, como delegar.ps1 sin -Visible.
param([Parameter(Mandatory = $true)][string]$Hilo, [Parameter(Mandatory = $true)][int]$N)
$ejecutar = Join-Path (Split-Path $PSScriptRoot) 'ejecutar.ps1'
$argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $ejecutar + '"'), '-Hilo', ('"' + $Hilo.Replace('"', '') + '"'), '-N', [string]$N)
Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden | Out-Null
Write-Output "Lanzado en segundo plano: ${Hilo}#$N"
