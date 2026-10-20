# Atajo que crea el encargo en un hilo (o abre uno) y, si queda aprobado, lo lanza.
# Uso: delegar.ps1 -A codex|agy|claude [-Modelo <modelo>] -Encargo <archivo.md> [-Dir <carpeta>] [-Hilo <id>] [-Esfuerzo low|medium|high] [-Esperar] [-Visible] [-De <autor>] [-MesaJson <ruta>] [-Simular]
# -Visible: deja el encargo en la cola del panel de ese agente en la Mesa (trabajador.ps1 -Agente), que lo ejecuta a la vista; no abre paneles nuevos.
#   Si el panel no da señales de vida, se lanza oculto como siempre y se avisa.
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('codex','agy','antigravity','claude')]
  [string]$A,

  [string]$Modelo,

  [Parameter(Mandatory = $true)]
  [string]$Encargo,

  [string]$Dir,

  [string]$Hilo,

  [ValidateSet('low','medium','high')]
  [string]$Esfuerzo = 'medium',

  [switch]$Esperar,

  [string]$De = 'claude',

  [string]$Texto,

  [string]$MesaJson,

  [switch]$Simular,

  [switch]$Visible,

  # Qué hace el encargo, para la autoaprobación: lectura, mesa, relevo, repo, carpeta, red o irreversible. Sin él se deduce de -Dir.
  [ValidateSet('lectura','mesa','relevo','repo','carpeta','red','irreversible')]
  [string]$Tipo
)
if ($Simular) { $env:MESA_SIMULAR = '1' }

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"

if (-not $Dir) { $Dir = $Global:Mesa_DefaultDir }
$paraNorm = Mesa-NormalizarHerramienta $A
if (-not $paraNorm) {
  throw "Herramienta desconocida: '$A'. Solo se permite codex, agy o claude."
}

if (-not $Modelo) {
  $cfgTmp = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)
  $Modelo = Mesa-ModeloPorDefecto $paraNorm $cfgTmp
}
$hojaEncargo = Split-Path -Leaf $Encargo
$tituloBase = ($hojaEncargo -replace '\.md$', '')

if (-not $Hilo) {
  $Hilo = (& "$PSScriptRoot\mesa.ps1" abrir -Titulo "Encargo $tituloBase" -Lider $De -Participantes @($De, $paraNorm) | Select-Object -Last 1).Trim()
} else {
  $rutaHilo = Join-Path (Join-Path $Global:Mesa_Hilos $Hilo) 'hilo.json'
  if (-not (Test-Path -LiteralPath $rutaHilo)) {
    $Hilo = (& "$PSScriptRoot\mesa.ps1" abrir -Hilo $Hilo -Titulo "Encargo $tituloBase" -Lider $De -Participantes @($De, $paraNorm) | Select-Object -Last 1).Trim()
  }
}

$textoMsg = if ($Texto) { $Texto } else { "Delegación a $paraNorm ($Modelo): $hojaEncargo" }
$paramsEnv = @{
  Hilo     = $Hilo
  De       = $De
  Para     = $paraNorm
  Texto    = $textoMsg
  Encargo  = $Encargo
  Dir      = $Dir
  Modelo   = $Modelo
  Esfuerzo = $Esfuerzo
}
if ($MesaJson) { $paramsEnv['MesaJson'] = $MesaJson }
if ($Tipo) { $paramsEnv['Tipo'] = $Tipo }

$salidaEnv = (& "$PSScriptRoot\mesa.ps1" enviar @paramsEnv | Select-Object -Last 1).Trim()
$carpetaHilo = Join-Path $Global:Mesa_Hilos $Hilo
$ultimoArch = Get-ChildItem -LiteralPath $carpetaHilo -Filter '*-*.json' | Sort-Object Name | Select-Object -Last 1
$msg = Mesa-LeerJson $ultimoArch.FullName

Write-Output "Hilo: $Hilo | Mensaje: #$($msg.n) | Estado inicial: $($msg.estado)"

if ($msg.estado -eq 'aprobado') {
  # Comprobar topes antes de lanzar (incluso sin -Esperar)
  $cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)
  $herr = $msg.herramienta
  $cont = Mesa-ContadoresLlamadas
  $usadosHora = [int]$cont[$herr].hora
  $usadosDia  = [int]$cont[$herr].dia
  $topeHora   = if ($cfg -and $cfg.topes -and $cfg.topes.$herr) { [int]$cfg.topes.$herr.hora } else { 999 }
  $topeDia    = if ($cfg -and $cfg.topes -and $cfg.topes.$herr) { [int]$cfg.topes.$herr.dia } else { 999 }

  # Vale el panel propio del agente (trabajador.ps1 -Agente) o el general sin -Agente.
  $panelVivo = @("trabajador-$herr.latido", 'trabajador.latido' | ForEach-Object { Join-Path $Global:Mesa_Raiz $_ } | Where-Object {
    (Test-Path -LiteralPath $_) -and (((Get-Date) - [DateTime]::Parse([IO.File]::ReadAllText($_))).TotalSeconds -lt 30)
  }).Count -gt 0
  if ($Visible -and -not $Simular -and -not $panelVivo) { Write-Warning "El panel de $herr no está en marcha (trabajador.ps1 -Agente $herr): se lanza oculto." }

  if ($Visible -and -not $Simular -and $panelVivo) {
    # Los topes los comprueba ejecutar.ps1 al sacarlo de la cola.
    $msg | Add-Member -NotePropertyName cola -NotePropertyValue $true -Force
    Mesa-EscribirJson $ultimoArch.FullName $msg
    Write-Output "En cola del panel de ${herr}: $herr ($Modelo) con ${Hilo}#$($msg.n)"
  } elseif ($Esperar -or $Simular -or ($usadosHora -ge $topeHora) -or ($usadosDia -ge $topeDia)) {
    $paramsEj = @{ Hilo = $Hilo; N = [int]$msg.n }
    if ($MesaJson) { $paramsEj['MesaJson'] = $MesaJson }
    if ($Simular)  { $paramsEj['Simular']  = $true }
    & "$PSScriptRoot\ejecutar.ps1" @paramsEj
  } else {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"'+$PSScriptRoot+'\ejecutar.ps1"'), '-Hilo', ('"'+$Hilo.Replace('"','')+'"'), '-N', [string]$msg.n)
    if ($MesaJson) { $argList += @('-MesaJson', $MesaJson) }
    Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden | Out-Null
    Write-Output "Lanzado en segundo plano: ${Hilo}#$($msg.n)"
  }
} else {
  Write-Output "El encargo ${Hilo}#$($msg.n) quedó en estado '$($msg.estado)' (requiere aprobación)."
}
