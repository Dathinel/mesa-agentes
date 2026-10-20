# Calibrador continuo de tokens y capacidad de cuotas
# Basado en medicion-tokens.md §4 y §5 (WLS + t de Student)
param(
  [string]$MesaRaiz,
  [switch]$Json,
  [switch]$Silencioso
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\comun.ps1"
. "$PSScriptRoot\costes.ps1"

$raiz = if ($MesaRaiz) { $MesaRaiz }
        elseif ($env:MESA_RAIZ_PRUEBA) { $env:MESA_RAIZ_PRUEBA }
        elseif ($Global:Mesa_Raiz) { $Global:Mesa_Raiz }
        else { Join-Path (Split-Path -Parent $PSScriptRoot) 'datos' }

$rutaFotos = Join-Path $raiz 'cuota-fotos.jsonl'
$rutaRegistro = Join-Path $raiz 'registro-tokens.jsonl'
$rutaCuota = Join-Path $raiz 'cuota-estado.json'
$rutaCalibracion = Join-Path $raiz 'cuota-calibracion.json'

function Obtener-TStudent([int]$df) {
  if ($df -le 0) { return 1.96 }
  $tabla = @{
    1  = 12.706; 2  = 4.303; 3  = 3.182; 4  = 2.776; 5  = 2.571
    6  = 2.447;  7  = 2.365; 8  = 2.306; 9  = 2.262; 10 = 2.228
    11 = 2.201;  12 = 2.179; 13 = 2.160; 14 = 2.145; 15 = 2.131
    16 = 2.120;  17 = 2.110; 18 = 2.101; 19 = 2.093; 20 = 2.086
    21 = 2.080;  22 = 2.074; 23 = 2.069; 24 = 2.064; 25 = 2.060
    26 = 2.056;  27 = 2.052; 28 = 2.048; 29 = 2.045; 30 = 2.042
  }
  if ($tabla.ContainsKey($df)) { return [double]$tabla[$df] }
  if ($df -le 40) { return 2.021 }
  if ($df -le 60) { return 2.000 }
  if ($df -le 120) { return 1.980 }
  return 1.960
}

function Es-TareaDeGrupo($t, [string]$grupo, [string]$herramienta) {
  if ($herramienta -eq 'agy') {
    return ($t.herramienta -eq 'agy' -and (Mesa-AgyGrupoPorModelo $t.modelo) -eq $grupo)
  }
  return ($t.herramienta -eq $herramienta)
}

# Cargar datos
$fotos = @()
if (Test-Path -LiteralPath $rutaFotos) {
  foreach ($l in [System.IO.File]::ReadLines($rutaFotos, [System.Text.Encoding]::UTF8)) {
    if ($l.Trim()) {
      try { $fotos += ($l | ConvertFrom-Json) } catch {}
    }
  }
}

$registro = @()
if (Test-Path -LiteralPath $rutaRegistro) {
  foreach ($l in [System.IO.File]::ReadLines($rutaRegistro, [System.Text.Encoding]::UTF8)) {
    if ($l.Trim()) {
      try {
        $r = $l | ConvertFrom-Json
        if ($r.calidad -ne 'simulado' -and ($null -eq $r.salida_proceso -or $r.salida_proceso -eq 0)) {
          $registro += $r
        }
      } catch {}
    }
  }
}

$cuotaEstado = $null
if (Test-Path -LiteralPath $rutaCuota) {
  try { $cuotaEstado = Mesa-LeerJson $rutaCuota } catch {}
}

function Calibrar-Grupo([string]$grupo, [string]$herramienta, [array]$listaFotos, [array]$listaTareas, [double]$cuotaLibreActual, [double]$costeSemilla) {
  $fotosGrupo = @($listaFotos | Where-Object { $_.grupo -eq $grupo } | Sort-Object { [DateTimeOffset]::Parse($_.fecha) })
  
  $sWTP = 0.0
  $sWTT = 0.0
  
  for ($i = 1; $i -lt $fotosGrupo.Count; $i++) {
    $ant = $fotosGrupo[$i - 1]
    $fin = $fotosGrupo[$i]
    
    $pAnt = if ($null -ne $ant.semanal_libre_pct) { [double]$ant.semanal_libre_pct } else { 100.0 - [double]$ant.semanal_usado_pct }
    $pFin = if ($null -ne $fin.semanal_libre_pct) { [double]$fin.semanal_libre_pct } else { 100.0 - [double]$fin.semanal_usado_pct }
    $deltaP = [Math]::Round($pAnt - $pFin, 4)
    
    if ($ant.reinicia_semanal -and ([DateTimeOffset]::Parse($ant.reinicia_semanal) -le [DateTimeOffset]::Parse($fin.fecha))) { continue }
    if ($deltaP -le 0) { continue }
    
    $fAntDt = [DateTimeOffset]::Parse($ant.fecha)
    $fFinDt = [DateTimeOffset]::Parse($fin.fecha)
    
    $tareasIntervalo = @($listaTareas | Where-Object {
      $tDt = [DateTimeOffset]::Parse($_.fecha)
      $tDt -gt $fAntDt -and $tDt -le $fFinDt -and (Es-TareaDeGrupo $_ $grupo $herramienta)
    })
    
    $deltaT = 0L
    foreach ($t in $tareasIntervalo) {
      $deltaT += [long]$t.total
    }
    
    if ($deltaT -gt 0 -and $deltaP -gt 0) {
      $esDecimal = (([string]$pAnt -match '\.\d+') -or ([string]$pFin -match '\.\d+'))
      $sigma = if ($esDecimal) { 0.005 } else { 0.5 }
      $w = 1.0 / ($sigma * $sigma)
      
      $sWTP += $w * [double]$deltaT * $deltaP
      $sWTT += $w * [double]$deltaT * [double]$deltaT
    }
  }
  
  $kEstimado = $null
  if ($sWTT -gt 0 -and $sWTP -gt 0) {
    $beta = $sWTP / $sWTT
    if ($beta -gt 0) {
      $kEstimado = [long][Math]::Round(100.0 / $beta)
    }
  }
  
  $tareasGrupo = @($listaTareas | Where-Object { Es-TareaDeGrupo $_ $grupo $herramienta })
  
  $muestrasC = @()
  foreach ($t in $tareasGrupo) {
    if ($null -ne $t.coste_pct -and [double]$t.coste_pct -gt 0) {
      $muestrasC += [double]$t.coste_pct
    } elseif ($kEstimado -and $kEstimado -gt 0 -and $t.total -gt 0) {
      $muestrasC += [double](([double]$t.total / $kEstimado) * 100.0)
    }
  }
  
  $n = $muestrasC.Count
  $cBar = 0.0
  $deltaC = 0.0
  $calidad = 'respaldo'
  
  if ($n -ge 2) {
    $sumaC = 0.0
    foreach ($c in $muestrasC) { $sumaC += $c }
    $cBar = $sumaC / $n
    
    $sumaVar = 0.0
    foreach ($c in $muestrasC) { $sumaVar += [Math]::Pow($c - $cBar, 2) }
    $sc = [Math]::Sqrt($sumaVar / ($n - 1))
    
    $tCrit = Obtener-TStudent ($n - 1)
    $deltaC = $tCrit * ($sc / [Math]::Sqrt($n))
    $calidad = 'calibrado'
  } elseif ($n -eq 1) {
    $cBar = $muestrasC[0]
    $sc = [Math]::Max($cBar, 1.0)
    $deltaC = 1.96 * $sc
    $calidad = 'respaldo'
  } else {
    $cBar = $costeSemilla
    $deltaC = [Math]::Round($cBar * 0.25, 3)
    $calidad = 'respaldo'
  }
  
  $pActual = [Math]::Max(0.0, $cuotaLibreActual)
  $rEst = 0
  $rMin = 0
  $rMax = 0
  
  if ($cBar -gt 0 -and $pActual -gt 0) {
    $rEst = [int][Math]::Floor($pActual / $cBar)
    $denMin = $cBar + $deltaC
    $rMin = if ($denMin -gt 0) { [int][Math]::Floor($pActual / $denMin) } else { 0 }
    $denMax = $cBar - $deltaC
    $rMax = if ($denMax -gt 0.0001) { [int][Math]::Floor($pActual / $denMax) } else { [int][Math]::Floor($pActual / ($cBar * 0.1)) }
  }
  
  return [ordered]@{
    coste_medio      = [Math]::Round($cBar, 3)
    margen           = [Math]::Round($deltaC, 3)
    n                = $n
    tareas_restantes = $rEst
    r_min            = $rMin
    r_max            = $rMax
    k_estimado       = $kEstimado
    calidad          = $calidad
  }
}

# Obtener cuotas libres actuales
$claudeLibre = if ($cuotaEstado -and $cuotaEstado.claude -and $null -ne $cuotaEstado.claude.semanal_libre_pct_estimado) { [double]$cuotaEstado.claude.semanal_libre_pct_estimado } else { 100.0 }
$codexLibre  = if ($cuotaEstado -and $cuotaEstado.codex) {
  if ($null -ne $cuotaEstado.codex.semanal_libre_pct) { [double]$cuotaEstado.codex.semanal_libre_pct }
  elseif ($null -ne $cuotaEstado.codex.semanal_usado_pct) { 100.0 - [double]$cuotaEstado.codex.semanal_usado_pct }
  else { 100.0 }
} else { 100.0 }

$flashLibre  = if ($cuotaEstado -and $cuotaEstado.agy -and $cuotaEstado.agy.grupos -and $cuotaEstado.agy.grupos.flash) { [double]$cuotaEstado.agy.grupos.flash.libre_pct_estimado } else { 85.51 }
$argonLibre  = if ($cuotaEstado -and $cuotaEstado.agy -and $cuotaEstado.agy.grupos -and $cuotaEstado.agy.grupos.argon) { [double]$cuotaEstado.agy.grupos.argon.libre_pct_estimado } else { 17.96 }
$cgptLibre   = if ($cuotaEstado -and $cuotaEstado.agy -and $cuotaEstado.agy.grupos -and $cuotaEstado.agy.grupos.claude_gpt) { [double]$cuotaEstado.agy.grupos.claude_gpt.libre_pct_estimado } else { 9.12 }

# Calibrar grupos
$calFlash  = Calibrar-Grupo 'flash'      'agy'    $fotos $registro $flashLibre  1.1
$calArgon  = Calibrar-Grupo 'argon'      'agy'    $fotos $registro $argonLibre  12.8
$calCgpt   = Calibrar-Grupo 'claude_gpt' 'agy'    $fotos $registro $cgptLibre   3.0
$calClaude = Calibrar-Grupo 'claude'     'claude' $fotos $registro $claudeLibre 2.5
$calCodex  = Calibrar-Grupo 'codex'      'codex'  $fotos $registro $codexLibre  14.0

if ($null -eq $calCodex.k_estimado) {
  $calCodex.k_estimado = 82532507L
}
if ($null -eq $calClaude.k_estimado) {
  $calClaude.k_estimado = 48607056L
}

$resultado = [ordered]@{
  actualizado = (Mesa-IsoNow)
  agentes = [ordered]@{
    claude = $calClaude
    codex  = $calCodex
    agy    = $calFlash
  }
  grupos = [ordered]@{
    flash      = $calFlash
    argon      = $calArgon
    claude_gpt = $calCgpt
    claude     = $calClaude
    codex      = $calCodex
  }
}

$carpetaDest = Split-Path -Parent $rutaCalibracion
if ($carpetaDest -and -not (Test-Path -LiteralPath $carpetaDest)) {
  New-Item -ItemType Directory -Force -Path $carpetaDest | Out-Null
}
$jsonSalida = $resultado | ConvertTo-Json -Depth 6
[System.IO.File]::WriteAllText($rutaCalibracion, $jsonSalida, (New-Object System.Text.UTF8Encoding $false))

if ($Json) {
  $jsonSalida
} elseif (-not $Silencioso) {
  Write-Output "Calibración actualizada en $rutaCalibracion"
  Write-Output ("  Claude: coste_medio={0}% ± {1}% (N={2}, rest={3})" -f $calClaude.coste_medio, $calClaude.margen, $calClaude.n, $calClaude.tareas_restantes)
  Write-Output ("  Codex:  coste_medio={0}% ± {1}% (N={2}, rest={3})" -f $calCodex.coste_medio, $calCodex.margen, $calCodex.n, $calCodex.tareas_restantes)
  Write-Output ("  agy:    coste_medio={0}% ± {1}% (N={2}, rest={3})" -f $calFlash.coste_medio, $calFlash.margen, $calFlash.n, $calFlash.tareas_restantes)
}