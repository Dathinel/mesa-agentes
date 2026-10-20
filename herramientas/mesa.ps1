# Herramienta principal de coordinación de la Mesa de agentes.
# Solo para Claude, Codex y Antigravity (agy).
# Subcomandos:
#   abrir -Titulo -Lider -Participantes [-Hilo <id>]
#   enviar -Hilo -De -Para -Texto [-Encargo archivo.md] [-Dir carpeta] [-Modelo] [-Esfuerzo] [-TraspasoHecho] [-TraspasoFalta] [-TraspasoArchivos]
#   leer -Hilo
#   lider -Hilo -Nuevo
#   hilos
#   pendientes [-Para <agente>]
#   aprobar -Hilo -N [-Simular] [-NoLanzar] [-MesaJson <ruta>]
#   rechazar -Hilo -N -Motivo
#   cuota [-Json]
#   llamadas
#   foto -Grupo flash|claude_gpt|argon|claude [-SemanalLibre <pct>] [-SemanalUsado <pct>] [-CincoHLibre <pct>] [-ReiniciaSemanal 148h30m] [-ReiniciaCincoH 1h25m] [-Fecha ISO]
#   reclamar -Tarea <id> -De <agente> [-Hilo <id>] [-Texto <archivos que toca>]   (sale con código 2 si otro la tiene)
#   reclamos | soltar -Tarea <id> -De <agente>
#   entregar -Hilo -Tarea -De -Texto <resumen> [-TraspasoHecho <pruebas>] [-TraspasoFalta <pendientes>] [-TraspasoArchivos <lista>]
#   revisar -Hilo -Tarea -De <líder> -Veredicto aceptada|devuelta [-Motivo]   |   entregas [-Hilo] [-Json]
#   avance -Hilo -Tarea -De -Fase inicio|hito|bloqueo|alcance -Texto   (inicio obligatorio antes de entregar)
#   tareas -Hilo [-De <líder> -Tarea a,b,c]   (inventario que exige archivar; solo se suma)   |   archivar -Hilo -De <líder>
#   reintentar -Hilo -N -De <líder>   (relanza un encargo huérfano o fallido; a los 3 intentos lo escala a la persona)
#   cortar -Hilo -N -De <líder>       (mata el CLI colgado de un encargo en curso; el panel sigue vivo)
#   diagnostico                       (resumen pegable en el chat: estados, versiones, errores; sin secretos)
#   bitacora [-Fecha AAAA-MM-DD]      (el día en español llano)   |   limpiar   (archiva reclamos caducados y restos)
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [ValidateSet('abrir','enviar','leer','lider','hilos','pendientes','aprobar','rechazar','cuota','llamadas','foto','actividad','alertas','sugerir-lider','reclamar','reclamos','soltar','entregar','revisar','archivar','entregas','tareas','avance','reintentar','cortar','diagnostico','bitacora','limpiar')]
  [string]$Comando,

  [string]$Tarea,
  [ValidateSet('aceptada','devuelta')][string]$Veredicto,

  [Alias('Id')]
  [string]$Hilo,
  [string]$Titulo,
  [string]$Lider,
  [string[]]$Participantes,
  [Alias('Autor')]
  [string]$De,
  [Alias('A')]
  [string]$Para,
  [string]$Texto,
  [string]$Encargo,
  [string]$Dir,
  [string]$Modelo,
  [string]$Esfuerzo,
  [string]$Nuevo,
  [int]$N = 0,
  [string]$Motivo,
  [string]$MesaJson,
  [string]$TraspasoHecho,
  [string]$TraspasoFalta,
  [string[]]$TraspasoArchivos,
  [string]$TraspasoDecoracion,
  [switch]$Simular,
  [switch]$NoLanzar,
  [switch]$SoloNota,
  [switch]$Json,

  [ValidateSet('flash','claude_gpt','argon','claude','codex')]
  [string]$Grupo,
  [double]$SemanalLibre,
  [double]$SemanalUsado,
  [double]$CincoHLibre,
  [double]$CincoHUsado,
  [string]$ReiniciaSemanal,
  [string]$ReiniciaCincoH,
  [string]$Fecha,
  [ValidateSet('claude','codex','agy')][string]$Agente,
  [ValidateRange(1,8760)][int]$Horas = 24,
  [ValidateSet('alto','medio')][string]$Nivel,
  [string]$Revisada,
  [string]$Fase,
  [ValidateSet('lectura','mesa','relevo','repo','carpeta','red','irreversible')][string]$Tipo
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\comun.ps1"
. "$PSScriptRoot\costes.ps1"

function Generar-SlugHilo($titulo) {
  $fecha = Get-Date -Format 'yyyyMMdd'
  $limpio = ($titulo.ToLowerInvariant() -replace '[áàäâ]', 'a' -replace '[éèëê]', 'e' -replace '[íìïî]', 'i' -replace '[óòöô]', 'o' -replace '[úùüû]', 'u' -replace 'ñ', 'n' -replace '[^a-z0-9]+', '-').Trim('-')
  if ($limpio.Length -gt 24) { $limpio = $limpio.Substring(0, 24).Trim('-') }
  if (-not $limpio) { $limpio = 'hilo' }
  $base = "$fecha-$limpio"
  $cand = $base
  $i = 2
  while (Test-Path -LiteralPath (Join-Path $Global:Mesa_Hilos $cand)) {
    $cand = "$base-$i"
    $i++
  }
  return $cand
}

function Nota-Hilo($carpeta, $de, $para, $tipo, $texto, $archivos, $tarea = $null) {
  $msg = [ordered]@{
    tarea = $tarea
    n = 0; autor = $de; para = $para; herramienta = $null; modelo = $null; fecha = (Mesa-IsoNow); tipo = $tipo
    texto = $texto; encargo = $null; dir = $Global:Mesa_DefaultDir; estado = 'hecho'
    traspaso = [ordered]@{ hecho = $texto; falta = ''; archivos = @($archivos | Where-Object { $_ }) }
    llamada = [ordered]@{ inicio = $null; fin = $null; salida = $null; log = $null }
  }
  Mesa-EscribirMensaje $carpeta $msg $de
}

function Exigir-Lider($h, $de) {
  if ($de -ne $Global:Mesa_Humano -and (Mesa-NormalizarHerramienta $de) -ne (Mesa-NormalizarHerramienta $h.lider)) {
    throw "Solo el líder del hilo ($($h.lider)) o $($Global:Mesa_Humano) puede hacerlo."
  }
}

function Buscar-ArchivoMensaje($carpetaHilo, [int]$num) {
  Get-ChildItem -LiteralPath $carpetaHilo -Filter ('{0:D4}-*.json' -f $num) -ErrorAction SilentlyContinue | Select-Object -First 1
}

switch ($Comando) {
  'reintentar' {
    if (-not $Hilo -or $N -le 0 -or -not $De) { throw 'Uso: mesa.ps1 reintentar -Hilo <id> -N <num> -De <líder>' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    Exigir-Lider $h $De
    $arch = Buscar-ArchivoMensaje $carpeta $N
    if (-not $arch) { throw "No existe el mensaje #$N en '$Hilo'" }
    $maxIntentos = if ((Mesa-LeerJson (Mesa-ConfigPath $MesaJson)).supervisor.max_intentos) { [int](Mesa-LeerJson (Mesa-ConfigPath $MesaJson)).supervisor.max_intentos } else { 3 }
    $candado = Mesa-BloquearHilo $carpeta
    try {
      $m = Mesa-LeerJson $arch.FullName
      if ($m.tipo -ne 'encargo' -or $m.estado -notin @('huerfano', 'fallo')) { throw "Solo se reintenta un encargo huérfano o fallido; #$N está '$($m.estado)'." }
      $intentos = 1 + $(if ($m.PSObject.Properties['intentos']) { [int]$m.intentos } else { 0 })
      $m | Add-Member intentos $intentos -Force
      $escalar = $intentos -ge $maxIntentos
      $m.estado = if ($escalar) { 'escalado' } else { 'aprobado' }
      $panel = Join-Path $Global:Mesa_Raiz "trabajador-$($m.herramienta).latido"
      $vivo = (Test-Path -LiteralPath $panel) -and ((Get-Date) - (Get-Item -LiteralPath $panel).LastWriteTime).TotalSeconds -lt 30
      $m | Add-Member cola ([bool]($vivo -and -not $escalar)) -Force
      Mesa-EscribirJson $arch.FullName $m
    } finally { $candado.Dispose() }
    if ($escalar) {
      Nota-Hilo $carpeta $De $Global:Mesa_Humano 'nota' "Encargo #$N de $($m.herramienta) escalado a $($Global:Mesa_Humano): falló o quedó huérfano $intentos veces. Revisa el log $($m.llamada.log) y decide." @($m.llamada.log) | Out-Null
      Write-Output "ESCALADO #$N a $($Global:Mesa_Humano) ($intentos intentos)"
    } elseif ($vivo) { Write-Output "REINTENTO $intentos de #$N en la cola del panel de $($m.herramienta)" }
    else {
      Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSScriptRoot\ejecutar.ps1`"", '-Hilo', $Hilo, '-N', $N) -WindowStyle Hidden | Out-Null
      Write-Output "REINTENTO $intentos de #$N lanzado en segundo plano (el panel de $($m.herramienta) no da latido)"
    }
  }
  'cortar' {
    if (-not $Hilo -or $N -le 0 -or -not $De) { throw 'Uso: mesa.ps1 cortar -Hilo <id> -N <num> -De <líder>' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    Exigir-Lider (Mesa-LeerJson (Join-Path $carpeta 'hilo.json')) $De
    $m = Mesa-LeerJson (Buscar-ArchivoMensaje $carpeta $N).FullName
    if ($m.estado -ne 'ejecutando' -or -not $m.llamada.pid) { throw "#$N no está en curso con un proceso conocido." }
    # Solo si ese proceso sigue con este mismo intento: un panel que ya pasó al encargo siguiente no se toca.
    $enCurso = Mesa-LeerMensaje (Join-Path $Global:Mesa_Raiz "agentes\en-curso-$($m.llamada.pid).json")
    if (-not $enCurso -or $enCurso.hilo -ne $Hilo -or [int]$enCurso.n -ne $N -or $enCurso.intento -ne $m.llamada.intento) { throw "El proceso $($m.llamada.pid) ya no ejecuta #$N`: no se corta nada. Si quedó huérfano, usa reintentar." }
    $ll = $m.llamada
    if (-not $ll.cli_pid -or $enCurso.cli_pid -ne $ll.cli_pid -or $enCurso.cli_inicio -ne $ll.cli_inicio -or $enCurso.cli_nombre -ne $ll.cli_nombre -or
        -not (Mesa-ProcesoVivo $ll.cli_pid $ll.cli_inicio $ll.cli_nombre)) { throw "La identidad del CLI de #$N ya no coincide: no se corta nada." }
    # El Job de ejecutar.ps1 recoge todos los descendientes al morir su raíz, incluso si ya quedaron huérfanos.
    Stop-Process -Id $ll.cli_pid -Force -ErrorAction Stop
    Write-Output "CORTADO #$N`: CLI $($ll.cli_pid) ($($ll.cli_nombre)) y sus descendientes. Luego: mesa.ps1 reintentar -Hilo $Hilo -N $N -De $De"
  }
  'diagnostico' {
    # Por cmd: codex es un .ps1/.cmd de npm que escribe avisos en stderr y, con ErrorAction Stop, parecía no estar.
    $v = { param($c) $r = (cmd.exe /c "$c --version 2>nul" | Select-Object -First 1); if ($r) { $r -replace '\s+', ' ' } else { 'no encontrado' } }
    Write-Output "## Diagnóstico de la Mesa · $(Mesa-IsoNow)"
    Write-Output "Windows $([Environment]::OSVersion.Version) · PowerShell $($PSVersionTable.PSVersion) · claude $(& $v claude) · codex $(& $v codex) · agy $(& $v agy)"
    Write-Output "Raíz: $Global:Mesa_Raiz · Trabajo: $Global:Mesa_DefaultDir"
    Write-Output "`n### Agentes"
    foreach ($a in $Global:Mesa_Agentes) { $e = Mesa-LeerMensaje (Join-Path $Global:Mesa_Raiz "agentes\$a.json"); Write-Output ("- {0}: {1} {2} (último latido {3}; supervisor {4})" -f $a, $e.estado, $e.motivo, $e.latido, $e.actualizado) }
    Write-Output "`n### Reclamos"; Mesa-Reclamos | ForEach-Object { "- $($_.tarea): $($_.agente) desde $($_.fecha) ($($_.hilo))" }
    Write-Output "`n### Encargos en curso, huérfanos o escalados"
    Get-ChildItem -Path (Join-Path $Global:Mesa_Hilos '*\*-*.json') -ErrorAction SilentlyContinue | ForEach-Object { $m = Mesa-LeerMensaje $_.FullName; if ($m.tipo -eq 'encargo' -and $m.estado -in @('ejecutando', 'huerfano', 'escalado', 'pendiente')) { "- $($_.Directory.Name) #$($m.n) $($m.herramienta) $($m.estado) desde $($m.llamada.inicio)" } }
    Write-Output "`n### Últimos errores de paneles y supervisor"
    $err = Join-Path $Global:Mesa_Raiz 'errores-paneles.log'; if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Tail 10 -Encoding UTF8 }
    Write-Output "`n### Bitácora de hoy (últimas 15)"
    $bit = Join-Path $Global:Mesa_Raiz ("bitacora\{0}.md" -f (Get-Date -Format 'yyyy-MM-dd')); if (Test-Path -LiteralPath $bit) { Get-Content -LiteralPath $bit -Tail 15 -Encoding UTF8 }
    Write-Output "`n### Configuración (mesa.json, sin cuota manual)"
    $cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson); Write-Output (($cfg | Select-Object topes, autoaprobar, supervisor | ConvertTo-Json -Depth 4 -Compress))
  }
  'bitacora' {
    $dia = if ($Fecha) { [datetime]::Parse($Fecha).Date } else { (Get-Date).Date }
    $verbos = @{ 'encargo' = 'encarga a'; 'respuesta' = 'responde a'; 'nota' = 'escribe a'; 'entrega' = 'entrega a'; 'revision' = 'revisa para'; 'lider' = 'cambia el líder:'; 'avance-inicio' = 'empieza, avisa a'; 'avance-hito' = 'avanza, avisa a'; 'avance-bloqueo' = 'SE ATASCA, avisa a'; 'avance-alcance' = 'cambia el alcance, avisa a' }
    $lineas = foreach ($f in @(Get-ChildItem -Path (Join-Path $Global:Mesa_Hilos '*\*-*.json') -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime.Date -ge $dia })) {
      $m = Mesa-LeerMensaje $f.FullName
      if (-not $m -or -not $m.fecha -or ([datetime]::Parse($m.fecha)).Date -ne $dia) { continue }
      $t = ([string]$m.texto -replace '\s+', ' '); if ($t.Length -gt 140) { $t = $t.Substring(0, 140) + '…' }
      [pscustomobject]@{ hora = [datetime]::Parse($m.fecha); txt = "- {0} · {1} {2} {3} ({4}): {5}" -f ([datetime]::Parse($m.fecha)).ToString('HH:mm'), $m.autor, $(if ($verbos[$m.tipo]) { $verbos[$m.tipo] } else { $m.tipo }), $m.para, $f.Directory.Name, $t }
    }
    Write-Output "# Bitácora del $($dia.ToString('yyyy-MM-dd'))"
    @($lineas | Sort-Object hora | ForEach-Object txt)
    $bit = Join-Path $Global:Mesa_Raiz ("bitacora\{0}.md" -f $dia.ToString('yyyy-MM-dd'))
    if (Test-Path -LiteralPath $bit) { Write-Output "`n## Supervisor"; Get-Content -LiteralPath $bit -Encoding UTF8 }
  }
  'limpiar' {
    # Reinicio seguro: nada se borra, se mueve a datos\archivo\limpieza-<fecha>.
    $destino = Join-Path $Global:Mesa_Raiz ("archivo\limpieza-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $mover = @()
    $horas = if ($PSBoundParameters.ContainsKey('Horas')) { $Horas } else { 12 }
    foreach ($r in @(Mesa-Reclamos | Where-Object { $_.tarea -ne 'lider' })) {
      $a = Mesa-NormalizarHerramienta $r.agente
      $ult = @((Mesa-UltimaActividad $a), [datetime]::Parse($r.fecha)) | Sort-Object | Select-Object -Last 1
      if (((Get-Date) - $ult).TotalHours -ge $horas) { $mover += $r.ruta }
    }
    $mover += @(Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Raiz 'reclamos') -Filter 'lider.json' -ErrorAction SilentlyContinue | ForEach-Object FullName)
    $mover += @(Get-ChildItem -LiteralPath (Join-Path $Global:Mesa_Raiz 'reclamos') -Filter 'relevo-*.lock' -ErrorAction SilentlyContinue | Where-Object { ((Get-Date) - $_.LastWriteTime).TotalHours -ge 24 } | ForEach-Object FullName)
    $mover += @(Get-ChildItem -LiteralPath $Global:Mesa_Raiz -Recurse -Filter '*.tmp.*' -ErrorAction SilentlyContinue | Where-Object { ((Get-Date) - $_.LastWriteTime).TotalHours -ge 1 } | ForEach-Object FullName)
    # Hilos cerrados hace más de 30 días: se mueven enteros a datos\archivo\hilos, nunca se borran.
    $mover += @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Where-Object {
      $hj = Mesa-LeerMensaje (Join-Path $_.FullName 'hilo.json'); $hj -and $hj.estado -eq 'cerrado' -and $hj.actualizado -and ([datetime]::Parse($hj.actualizado) -lt (Get-Date).AddDays(-30)) } | ForEach-Object FullName)
    $viejos = @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Where-Object { $hj = Mesa-LeerMensaje (Join-Path $_.FullName 'hilo.json'); $hj -and $hj.estado -eq 'abierto' -and ([datetime]::Parse($hj.actualizado) -lt (Get-Date).AddDays(-30)) } | ForEach-Object Name)
    if ($viejos.Count) { Write-Output "Abiertos sin actividad en 30 días (ciérralos con archivar si están terminados): $($viejos -join ', ')" }
    if (-not $mover.Count) { Write-Output 'Nada que limpiar.'; return }
    New-Item -ItemType Directory -Force -Path $destino | Out-Null
    # Se conserva la ruta relativa: dos claims\ui.json de hilos distintos no se pisan.
    foreach ($x in $mover) {
      $dest = Join-Path $destino $x.Substring($Global:Mesa_Raiz.TrimEnd('\').Length + 1)
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
      Move-Item -LiteralPath $x -Destination $dest; Write-Output "Archivado: $x"
    }
    Write-Output "Movidos $($mover.Count) a $destino"
  }
  'actividad' {
    & "$PSScriptRoot\vigia.ps1"
    if (!$PSBoundParameters.ContainsKey('Horas')) { $Horas=8 }
    $items=@(Mesa-Actividades $Horas $Agente)
    if ($Json) { ConvertTo-Json -InputObject $items -Depth 5 } else { $items | Select-Object agente,hora,valor,herramienta | Format-Table -AutoSize | Out-String -Width 220 }
  }
  'alertas' {
    if ($Revisada) {
      $ruta=Join-Path $Global:Mesa_Raiz 'alertas-revisadas.json'
      $vistas=Mesa-LeerJson $ruta
      $existe=@(Mesa-RegistroLocal (Join-Path $Global:Mesa_Raiz 'alertas.jsonl') | Where-Object id -eq $Revisada)
      if (!$existe.Count) { throw 'No existe esa alerta.' }
      Mesa-EscribirJson $ruta @{ ids=@(@($vistas.ids)+$Revisada | Where-Object { $_ } | Select-Object -Unique); actualizado=(Mesa-IsoNow) }
      Write-Output "Alerta $Revisada revisada."
    } else {
      $items=@(Mesa-Alertas $Horas $Nivel)
      if ($Json) { ConvertTo-Json -InputObject $items -Depth 5 } else { $items | Select-Object id,agente,hora,nivel,motivo,revisada,valor | Format-Table -Wrap | Out-String -Width 220 }
    }
  }
  'sugerir-lider' {
    if (!$Hilo) { throw 'Indica -Hilo.' }
    $h=Mesa-LeerJson (Join-Path (Join-Path $Global:Mesa_Hilos $Hilo) 'hilo.json')
    if (!$h) { throw 'Hilo inexistente.' }
    $q=Mesa-LeerJson $Global:Mesa_CuotaEstado
    $faseEf=if ($Fase) { $Fase } elseif ($h.fase) { $h.fase } else { $h.titulo }
    $propuesta=$null; $razon='No hay cuota suficiente confirmada para esta fase.'
    if ($faseEf -match '(?i)plan|revisi[oó]n|decisi[oó]n' -and $null -ne $q.claude.semanal_libre_pct_estimado -and $q.claude.semanal_libre_pct_estimado -ge 20) { $propuesta='claude'; $razon='Plan/revisión y cuota semanal estimada >=20%.' }
    elseif ($faseEf -match '(?i)volumen|document|auditor' -and $q.agy.grupos.flash.libre_pct_estimado -ge 10) { $propuesta='agy'; $razon='Volumen/documentación/auditoría: modelo flash.' }
    elseif ($null -ne $q.codex.cinco_horas_usado_pct -and (100-$q.codex.cinco_horas_usado_pct) -ge 25) { $propuesta='codex'; $razon='Código y capacidad de 5 h >=25%; alternativa disponible para coordinar.' }
    elseif ($q.agy.grupos.flash.libre_pct_estimado -ge 10) { $propuesta='agy'; $razon='Alternativa por capacidad estimada de flash.' }
    [pscustomobject]@{ hilo=$Hilo; fase=$faseEf; actual=$h.lider; sugerido=$propuesta; motivo=$razon; aplicado=$false } | ConvertTo-Json
  }
  'reclamar' {
    if (-not $Tarea -or -not $De) { throw 'Uso: mesa.ps1 reclamar -Tarea <id> -De <agente> [-Hilo <id>] [-Texto <archivos>]' }
    if ($Tarea -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Tarea: solo minúsculas, cifras y guiones.' }
    if ($Tarea -eq 'lider') { throw "El liderazgo no se reclama: vive en el hilo.json de cada hilo. Cámbialo con 'mesa.ps1 lider -Hilo <id> -Nuevo <agente>'." }
    # Una sola tarea por agente: los reclamos de archivo sueltos (archivo-*) y el de líder no cuentan.
    $esTarea = { param($t) $t -notlike 'archivo-*' -and $t -ne 'lider' }
    if (& $esTarea $Tarea) {
      $otra = @(Mesa-Reclamos | Where-Object { (Mesa-NormalizarHerramienta $_.agente) -eq (Mesa-NormalizarHerramienta $De) -and $_.tarea -ne $Tarea -and (& $esTarea $_.tarea) })
      if ($otra.Count) { Write-Output "YA TIENES $($otra[0].tarea): entrégala o suéltala (o pide relevo al líder) antes de reclamar otra."; exit 3 }
    }
    $dirR = Join-Path $Global:Mesa_Raiz 'reclamos'
    New-Item -ItemType Directory -Force -Path $dirR | Out-Null
    $ruta = Join-Path $dirR "$Tarea.json"
    $contenido = [ordered]@{ tarea=$Tarea; agente=$De; fecha=(Mesa-IsoNow); hilo=$Hilo; toca=$Texto } | ConvertTo-Json -Compress
    # CreateNew es atómico en NTFS: de varios que lo intentan a la vez, solo uno lo crea.
    try { $f = [IO.File]::Open($ruta, 'CreateNew', 'Write', 'None') }
    catch [System.IO.IOException] {
      $dueno = Mesa-LeerJson $ruta
      Write-Output "OCUPADA $Tarea por $($dueno.agente) desde $($dueno.fecha)"
      exit 2
    }
    try { $b = [Text.Encoding]::UTF8.GetBytes($contenido); $f.Write($b, 0, $b.Length) } finally { $f.Dispose() }
    Write-Output "RECLAMADA $Tarea por $De"
  }
  'reclamos' {
    $items = @(Mesa-Reclamos)
    # Los líderes se muestran derivados de los hilos abiertos, nunca de un archivo aparte.
    $items += @(Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | ForEach-Object { $hj = Mesa-LeerMensaje (Join-Path $_.FullName 'hilo.json'); if ($hj -and $hj.estado -eq 'abierto' -and $hj.lider -and ([datetime]::Parse($hj.actualizado) -gt (Get-Date).AddDays(-2))) { [pscustomobject]@{ tarea = 'lider'; agente = $hj.lider; fecha = $hj.actualizado; hilo = $hj.id; toca = '(hilo.json)'; ruta = $null } } })
    if ($Json) { ConvertTo-Json -InputObject $items -Depth 3 } elseif (!$items.Count) { '(sin reclamos)' } else { $items | Format-Table tarea,agente,fecha,hilo,toca -AutoSize | Out-String -Width 220 }
  }
  'soltar' {
    if (-not $Tarea -or -not $De) { throw 'Uso: mesa.ps1 soltar -Tarea <id> -De <agente> [-Hilo <id>]' }
    $items = @(Mesa-Reclamos | Where-Object { $_.tarea -eq $Tarea -and (-not $Hilo -or $_.hilo -eq $Hilo) })
    if (-not $items.Count) { throw "No hay reclamo de '$Tarea'." }
    foreach ($r in $items) {
      # Lo suelta su dueño, la persona o el líder del hilo del reclamo (para reasignar).
      $liderR = if ($r.hilo) { (Mesa-LeerJson (Join-Path (Join-Path $Global:Mesa_Hilos $r.hilo) 'hilo.json')).lider } else { $null }
      $puede = $De -eq $Global:Mesa_Humano -or (Mesa-NormalizarHerramienta $De) -eq (Mesa-NormalizarHerramienta $r.agente) -or ($liderR -and (Mesa-NormalizarHerramienta $De) -eq (Mesa-NormalizarHerramienta $liderR))
      if (-not $puede) { throw "La tiene $($r.agente); solo ese agente, el líder de su hilo o $($Global:Mesa_Humano) la sueltan." }
      Remove-Item -LiteralPath $r.ruta
      Write-Output "Soltada $Tarea ($($r.agente))"
    }
  }

  'avance' {
    if (-not $Hilo -or -not $Tarea -or -not $De -or -not $Fase -or -not $Texto) { throw 'Uso: mesa.ps1 avance -Hilo <id> -Tarea <id> -De <yo> -Fase inicio|hito|bloqueo|alcance -Texto <qué>' }
    if ($Fase -notin @('inicio','hito','bloqueo','alcance')) { throw 'Fase: inicio, hito, bloqueo o alcance.' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    $mio = @(Mesa-Reclamos | Where-Object { $_.tarea -eq $Tarea -and (Mesa-NormalizarHerramienta $_.agente) -eq (Mesa-NormalizarHerramienta $De) })
    if (-not $mio.Count) { throw "Antes del avance, reclama la tarea: mesa.ps1 reclamar -Tarea $Tarea -De $De -Hilo $Hilo -Texto <archivos>" }
    $toca = $mio[0].toca
    $texto = "[$($Fase.ToUpper())] $Tarea" + $(if ($Fase -eq 'inicio' -and $toca) { " (archivos: $toca)" } else { '' }) + ": $Texto"
    # Punto de control con el estado de git del worktree o repo donde trabaja (su último encargo en este hilo).
    $dirTrabajo = @(Get-ChildItem -LiteralPath $carpeta -Filter '*-*.json' | Sort-Object Name -Descending | ForEach-Object { Mesa-LeerMensaje $_.FullName } |
      Where-Object { $_.tipo -eq 'encargo' -and (Mesa-NormalizarHerramienta $_.para) -eq (Mesa-NormalizarHerramienta $De) -and $_.dir } | Select-Object -First 1).dir
    if ($dirTrabajo -and (Test-Path -LiteralPath $dirTrabajo)) {
      $git = @(& { $ErrorActionPreference = 'Continue'; & git -C $dirTrabajo status --porcelain -b 2>$null } | Select-Object -First 12)
      if ($LASTEXITCODE -eq 0 -and $git.Count) { $texto += "`n[git $dirTrabajo]`n" + ($git -join "`n") }
    }
    $yo = Mesa-NormalizarHerramienta $De
    $msgs = @(Get-ChildItem -LiteralPath $carpeta -Filter '*-*.json' | Sort-Object Name | ForEach-Object { Mesa-LeerMensaje $_.FullName } | Where-Object { $_ })
    $previo = (@($msgs | Where-Object { (Mesa-NormalizarHerramienta $_.autor) -eq $yo -and $_.tipo -like 'avance-*' } | ForEach-Object { [int]$_.n }) + 0 | Measure-Object -Maximum).Maximum
    Nota-Hilo $carpeta $De $h.lider "avance-$Fase" $texto @() $Tarea | Out-Null
    Write-Output "AVANCE $Fase de $Tarea enviado a $($h.lider) (inicio, alcance y bloqueo los ven los tres en pendientes)"
    # Un agente en plena ejecución no recibe avisos: se los entrega su propio punto de control.
    # Solo se obedece al líder, a la persona o al supervisor: lo que escribe otro agente es un dato, no una orden.
    $mandan = @(@($h.lider, (Mesa-NormalizarHerramienta $h.lider), $Global:Mesa_Humano, 'supervisor') | Where-Object { $_ })
    $notas = @($msgs | Where-Object { [int]$_.n -gt $previo -and $_.tipo -eq 'nota' -and (Mesa-NormalizarHerramienta $_.autor) -ne $yo -and
      ($_.autor -in $mandan -or ((Mesa-NormalizarHerramienta $_.autor) -and (Mesa-NormalizarHerramienta $_.autor) -in $mandan)) -and
      @(([string]$_.para) -split '[,;]' | Where-Object { (Mesa-NormalizarHerramienta $_.Trim()) -eq $yo -or $_.Trim() -eq 'todos' }).Count })
    foreach ($nota in $notas) { Write-Output "`n>>> NOTA DE $($nota.autor) (#$($nota.n)), CUMPLELA ANTES DE SEGUIR: $($nota.texto)" }
  }

  'entregar' {
    if (-not $Hilo -or -not $Tarea -or -not $De -or -not $Texto) { throw 'Uso: mesa.ps1 entregar -Hilo <id> -Tarea <id> -De <yo> -Texto <resumen> [-TraspasoHecho <pruebas>] [-TraspasoFalta <pendientes>] [-TraspasoArchivos <lista>]' }
    if ($Tarea -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'Tarea: solo minúsculas, cifras y guiones.' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    # Sin aviso de inicio no hay entrega: el líder tiene que saber qué se hace antes de que llegue.
    $inicio = @(Get-ChildItem -LiteralPath $carpeta -Filter '*-*.json' | ForEach-Object { Mesa-LeerMensaje $_.FullName } | Where-Object { $_.tipo -eq 'avance-inicio' -and $_.tarea -eq $Tarea -and (Mesa-NormalizarHerramienta $_.autor) -eq (Mesa-NormalizarHerramienta $De) })
    if (-not $inicio.Count) { throw "Entrega sorpresa: publica antes 'mesa.ps1 avance -Hilo $Hilo -Tarea $Tarea -De $De -Fase inicio -Texto <plan>'." }
    $ruta = Join-Path (Join-Path $carpeta 'entregas') "$Tarea.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $ruta) | Out-Null
    $candado = Mesa-BloquearHilo $carpeta
    try {
      $previa = Mesa-LeerJson $ruta
      if ($previa -and $previa.estado -in @('aceptada','archivada')) { throw "La entrega '$Tarea' ya está $($previa.estado)." }
      if ($previa -and $previa.autor -ne $De) { throw "La entrega '$Tarea' es de $($previa.autor)." }
      $e = [ordered]@{
        hilo = $Hilo; tarea = $Tarea; autor = $De; estado = 'entregada'; fecha = (Mesa-IsoNow)
        ronda = if ($previa) { [int]$previa.ronda + 1 } else { 1 }
        resumen = $Texto; pruebas = $TraspasoHecho; pendientes = $TraspasoFalta
        archivos = @($TraspasoArchivos | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        revisor = $null; motivo = $null; revisado = $null; archivada = $null
      }
      Mesa-EscribirJson $ruta $e
    } finally { $candado.Dispose() }
    $revisa = if ((Mesa-NormalizarHerramienta $De) -eq (Mesa-NormalizarHerramienta $h.lider)) { (@($h.participantes | Where-Object { (Mesa-NormalizarHerramienta $_) -and (Mesa-NormalizarHerramienta $_) -ne (Mesa-NormalizarHerramienta $De) }) + $Global:Mesa_Humano) -join ',' } else { $h.lider }
    Mesa-ActualizarHilo $carpeta { param($x) if (-not $x.PSObject.Properties['tareas']) { $x | Add-Member tareas @() }; if (@($x.tareas) -notcontains $Tarea) { $x.tareas = @(@($x.tareas) + $Tarea) } } | Out-Null
    Nota-Hilo $carpeta $De $revisa 'entrega' "Entrega '$Tarea' (ronda $($e.ronda)) en la bandeja: $Texto" @($ruta) | Out-Null
    Write-Output "ENTREGADA $Tarea (ronda $($e.ronda)); revisa $revisa"
  }
  'revisar' {
    if (-not $Hilo -or -not $Tarea -or -not $De -or -not $Veredicto) { throw 'Uso: mesa.ps1 revisar -Hilo <id> -Tarea <id> -De <líder> -Veredicto aceptada|devuelta [-Motivo <obs>]' }
    if ($Veredicto -eq 'devuelta' -and -not $Motivo) { throw 'Devolver exige -Motivo.' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    $ruta = Join-Path (Join-Path $carpeta 'entregas') "$Tarea.json"
    $candado = Mesa-BloquearHilo $carpeta
    try {
      $e = Mesa-LeerJson $ruta
      if (-not $e) { throw "No hay entrega '$Tarea' en $Hilo." }
      $autorN = Mesa-NormalizarHerramienta $e.autor
      if ($De -ne $Global:Mesa_Humano -and (Mesa-NormalizarHerramienta $De) -eq $autorN) { throw 'Nadie revisa su propia entrega.' }
      # La entrega del líder la revisa otro participante; las demás, el líder.
      if ($autorN -ne (Mesa-NormalizarHerramienta $h.lider)) { Exigir-Lider $h $De }
      if ($e.estado -ne 'entregada') { throw "La entrega '$Tarea' está $($e.estado), no pendiente de revisión." }
      $e.estado = $Veredicto; $e.revisor = $De; $e.motivo = $Motivo; $e.revisado = (Mesa-IsoNow)
      Mesa-EscribirJson $ruta $e
    } finally { $candado.Dispose() }
    $txt = if ($Veredicto -eq 'aceptada') { "Entrega '$Tarea' ACEPTADA." } else { "Entrega '$Tarea' DEVUELTA: $Motivo" }
    if ($Motivo -and $Veredicto -eq 'aceptada') { $txt += " $Motivo" }
    Nota-Hilo $carpeta $De $e.autor 'revision' $txt @($ruta) $Tarea | Out-Null
    if ($Veredicto -eq 'aceptada') {
      # Aceptada = terminada: se suelta el reclamo de su autor para que pueda coger la siguiente.
      foreach ($r in @(Mesa-Reclamos | Where-Object { $_.tarea -eq $Tarea -and (Mesa-NormalizarHerramienta $_.agente) -eq $autorN })) {
        Remove-Item -LiteralPath $r.ruta -ErrorAction SilentlyContinue; $txt += " Reclamo '$Tarea' de $($r.agente) soltado."
      }
    }
    Write-Output $txt
  }
  'archivar' {
    if (-not $Hilo -or -not $De) { throw 'Uso: mesa.ps1 archivar -Hilo <id> -De <líder> [-Tarea <esperadas a,b,c>]' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    Exigir-Lider $h $De
    $dirE = Join-Path $carpeta 'entregas'
    $candado = Mesa-BloquearHilo $carpeta
    try {
      $abiertas = @(Get-ChildItem -LiteralPath $dirE -Filter '*.json' -ErrorAction SilentlyContinue | ForEach-Object { @{ ruta = $_.FullName; e = (Mesa-LeerMensaje $_.FullName) } } | Where-Object { $_.e.estado -ne 'archivada' })
      if (-not $abiertas.Count) { throw 'No hay entregas por archivar.' }
      $sinAceptar = @($abiertas | Where-Object { $_.e.estado -ne 'aceptada' } | ForEach-Object { "$($_.e.tarea)=$($_.e.estado)" })
      if ($sinAceptar.Count) { throw "Faltan por aceptar: $($sinAceptar -join ', ')" }
      # Sin esto se podría archivar dejando fuera a quien reclamó trabajo y aún no lo entregó.
      $conEntrega = @($abiertas | ForEach-Object { Mesa-NormalizarHerramienta $_.e.autor })
      $sinEntregar = @(Mesa-Reclamos | Where-Object { $_.hilo -eq $Hilo -and $_.tarea -ne 'lider' -and $conEntrega -notcontains (Mesa-NormalizarHerramienta $_.agente) } | ForEach-Object { "$($_.agente):$($_.tarea)" } | Select-Object -Unique)
      if ($sinEntregar.Count) { throw "Hay reclamos sin entrega aceptada: $($sinEntregar -join ', ')" }
      $esperadas = @(@($h.tareas) + @($Tarea -split '[,;]') | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Unique)
      if (-not $esperadas.Count) { throw "El hilo no tiene inventario de tareas: defínelo con 'mesa.ps1 tareas -Hilo $Hilo -De $De -Tarea a,b,c'." }
      $faltan = @($esperadas | Where-Object { @($abiertas | ForEach-Object { $_.e.tarea }) -notcontains $_ })
      if ($faltan.Count) { throw "Tareas del inventario sin entrega aceptada: $($faltan -join ', ')" }
      $ahora = Mesa-IsoNow
      $lineas = @("# Archivo de entregas: $($h.titulo)", '', "Archivado por $De el $ahora.", '')
      foreach ($x in $abiertas) {
        $x.e.estado = 'archivada'; $x.e.archivada = $ahora
        Mesa-EscribirJson $x.ruta $x.e
        $lineas += "- **$($x.e.tarea)** ($($x.e.autor), ronda $($x.e.ronda)): $($x.e.resumen). Pruebas: $($x.e.pruebas). Archivos: $(@($x.e.archivos) -join ', ')."
      }
      $informe = Join-Path $dirE ('informe-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
      [IO.File]::WriteAllText($informe, ($lineas -join "`n") + "`n", (New-Object Text.UTF8Encoding $false))
    } finally { $candado.Dispose() }
    Nota-Hilo $carpeta $De 'todos' 'archivo' "Archivadas $($abiertas.Count) entregas; informe en $informe" @($informe) | Out-Null
    # Todo aceptado y archivado: el hilo queda cerrado (a los 30 días, limpiar lo mueve a datos\archivo\hilos).
    Mesa-ActualizarHilo $carpeta { param($x) $x.estado = 'cerrado'; $x.actualizado = (Mesa-IsoNow) } | Out-Null
    Write-Output "ARCHIVADAS $($abiertas.Count); informe: $informe"
  }
  'tareas' {
    if (-not $Hilo) { throw 'Uso: mesa.ps1 tareas -Hilo <id> [-De <líder> -Tarea a,b,c]' }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $h = Mesa-LeerJson (Join-Path $carpeta 'hilo.json')
    if (-not $h) { throw "No existe el hilo '$Hilo'" }
    if ($Tarea) {
      if (-not $De) { throw 'Definir el inventario exige -De <líder>.' }
      Exigir-Lider $h $De
      $lista = @($Tarea -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
      if (@($lista | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9-]*$' }).Count) { throw 'Tareas: solo minúsculas, cifras y guiones.' }
      # Se suma, nunca se quita: una tarea esperada no desaparece del cierre por editar el inventario.
      $h = Mesa-ActualizarHilo $carpeta { param($x) if (-not $x.PSObject.Properties['tareas']) { $x | Add-Member tareas @() }; $x.tareas = @(@($x.tareas) + $lista | Select-Object -Unique) }
      Nota-Hilo $carpeta $De 'todos' 'inventario' "Inventario de tareas: $(@($h.tareas) -join ', ')" @() | Out-Null
    }
    $ent = @(Mesa-Entregas -ConArchivadas | Where-Object { $_.hilo -eq $Hilo })
    @($h.tareas) | Where-Object { $_ } | ForEach-Object { $t = $_; $e = $ent | Where-Object { $_.tarea -eq $t } | Select-Object -First 1
      [pscustomobject]@{ tarea = $t; estado = if ($e) { $e.estado } else { 'sin entregar' }; autor = $e.autor; ronda = $e.ronda } } | Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() }
  }
  'entregas' {
    $items = @(Mesa-Entregas -ConArchivadas | Where-Object { -not $Hilo -or $_.hilo -eq $Hilo })
    if ($Json) { ConvertTo-Json -InputObject $items -Depth 4 } elseif (!$items.Count) { '(bandeja vacía)' } else { $items | Format-Table hilo,tarea,autor,estado,ronda,fecha,revisor,motivo -AutoSize | Out-String -Width 220 }
  }

  'abrir' {
    if (-not $Titulo -or -not $Lider -or -not $Participantes) {
      throw "Uso: mesa.ps1 abrir -Titulo <texto> -Lider <agente> -Participantes <lista> [-Hilo <id>]"
    }
    New-Item -ItemType Directory -Force -Path $Global:Mesa_Hilos | Out-Null
    $candado = Mesa-Bloquear (Join-Path $Global:Mesa_Hilos 'hilos')
    try {
    $hiloId = if ($Hilo) { $Hilo } else { Generar-SlugHilo $Titulo }
    $carpeta = Join-Path $Global:Mesa_Hilos $hiloId
    if (Test-Path -LiteralPath (Join-Path $carpeta 'hilo.json')) {
      Write-Warning "El hilo '$hiloId' ya existe: no se sobrescribe."
      Write-Output $hiloId
      return
    }
    New-Item -ItemType Directory -Force -Path $carpeta | Out-Null

    $listaPart = @($Participantes | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($listaPart -notcontains $Lider) { $listaPart = @($Lider) + $listaPart }

    $ahora = Mesa-IsoNow
    $hiloObj = [ordered]@{
      id            = $hiloId
      titulo        = $Titulo
      estado        = 'abierto'
      lider         = $Lider
      participantes = $listaPart
      creado        = $ahora
      actualizado   = $ahora
    }
    if ($Fase) { $hiloObj['fase']=$Fase }
    Mesa-EscribirJson (Join-Path $carpeta 'hilo.json') $hiloObj
    } finally { $candado.Dispose() }
    Write-Output $hiloId
  }

  'enviar' {
    if (-not $Hilo -or -not $De -or -not $Para) {
      throw "Uso: mesa.ps1 enviar -Hilo <id> -De <autor> -Para <destino> -Texto <texto> [-Encargo archivo.md] [-Dir carpeta] [-Modelo] [-Esfuerzo] [-TraspasoHecho <txt>] [-TraspasoFalta <txt>] [-TraspasoArchivos <lista>]"
    }
    if (-not $Texto -and -not $Encargo) {
      throw "Debe indicar -Texto o -Encargo."
    }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $archivoHilo = Join-Path $carpeta 'hilo.json'
    if (-not (Test-Path -LiteralPath $archivoHilo)) {
      throw "No existe el hilo '$Hilo' en $Global:Mesa_Hilos"
    }

    $cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)
    $herramienta = Mesa-NormalizarHerramienta $Para
    $esAgenteEjecutable = ($herramienta -in @('codex', 'agy', 'claude'))
    $modeloEf = if ($Modelo) { $Modelo } elseif ($esAgenteEjecutable) { Mesa-ModeloPorDefecto $herramienta $cfg } else { $null }
    $dirEf = if ($Dir) { $Dir } else { $Global:Mesa_DefaultDir }
    $textoEf = if ($Texto) { $Texto } else { "Encargo en $Encargo" }

    $ahora = Mesa-IsoNow

    $autoAprobado = $false
    $notaHecho = if ($TraspasoHecho) { $TraspasoHecho } else { 'Mensaje registrado' }
    $notaFalta = if ($TraspasoFalta) { $TraspasoFalta } else { '' }
    # Solo el líder (o la persona) lanza trabajo: un agente que escribe a otro deja nota, no otra ejecución.
    $liderHilo = Mesa-NormalizarHerramienta (Mesa-LeerJson $archivoHilo).lider
    $deAgente = Mesa-NormalizarHerramienta $De
    if ($deAgente -in @('codex', 'agy', 'claude') -and $liderHilo -and $deAgente -ne $liderHilo) { $SoloNota = $true }
    if ($esAgenteEjecutable -and !$SoloNota) {
      $tipoMsg = 'encargo'
      $listaAuto = if ($cfg -and $cfg.autoaprobar) { @($cfg.autoaprobar) } else { @() }
      $apr = Mesa-Aprobacion $cfg
      $tipoEnc = Mesa-TipoEncargo $dirEf $Tipo
      $deConfianza = $listaAuto -contains $De -or $listaAuto -contains (Mesa-NormalizarHerramienta $De)
      $porTipo = $apr.modo -eq 'todo' -or ($apr.modo -eq 'por-tipo' -and $apr.tipos -contains $tipoEnc)
      if ($deConfianza -and $porTipo) {
        $estadoMsg = 'aprobado'
        $autoAprobado = $true
        if (-not $TraspasoHecho) { $notaHecho = "autoaprobado ($tipoEnc)" }
      } else {
        $estadoMsg = 'pendiente'
        if (-not $TraspasoFalta) { $notaFalta = "Espera a $($Global:Mesa_Humano): encargo de tipo '$tipoEnc' (modo $($apr.modo))" }
      }
    } else {
      $tipoMsg = 'nota'
      $estadoMsg = 'hecho'
    }

    $archivosLista = @()
    if ($TraspasoArchivos) {
      $archivosLista = @($TraspasoArchivos)
    } elseif ($Encargo) {
      $archivosLista += $Encargo
    }

    $msg = [ordered]@{
      n           = 0
      autor       = $De
      para        = $Para
      herramienta = $herramienta
      modelo      = $modeloEf
      fecha       = $ahora
      tipo        = $tipoMsg
      texto       = $textoEf
      encargo     = if ($Encargo) { $Encargo } else { $null }
      dir         = $dirEf
      estado      = $estadoMsg
      traspaso    = [ordered]@{
        hecho    = $notaHecho
        falta    = $notaFalta
        archivos = $archivosLista
      }
      llamada     = [ordered]@{
        inicio = $null
        fin    = $null
        salida = $null
        log    = $null
      }
    }
    if ($Esfuerzo) {
      $msg['esfuerzo'] = $Esfuerzo
    }
    if ($tipoMsg -eq 'encargo') { $msg['tipo_encargo'] = $tipoEnc }

    $nombreArchivo = Mesa-EscribirMensaje $carpeta $msg $De
    $num = $msg.n

    if ($autoAprobado) {
      Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tAPROBADO`thilo={1}`tn={2}`tde={3}`tpara={4}`tmodelo={5}`tmotivo=autoaprobado" -f $ahora, $Hilo, $num, $De, $Para, $modeloEf)
    }

    if ($TraspasoDecoracion) {
      $agenteDecora = Mesa-NormalizarHerramienta $De
      if (-not $agenteDecora) { $agenteDecora = $De.ToLowerInvariant() }
      
      $motivoRechazo = $null
      $decJson = $null
      
      try {
        $decJson = $TraspasoDecoracion | ConvertFrom-Json
      } catch {
        $motivoRechazo = "JSON de decoracion no valido: $($_.Exception.Message)"
      }
      
      if (-not $motivoRechazo) {
        if (-not $TraspasoHecho -or -not $TraspasoHecho.Trim()) {
          $motivoRechazo = 'TraspasoHecho vacio; requiere merito explicito'
        }
      }
      
      if (-not $motivoRechazo) {
        $mensajesHilo = @(Get-ChildItem -LiteralPath $carpeta -Filter '*-*.json' -ErrorAction SilentlyContinue | ForEach-Object { Mesa-LeerMensaje $_.FullName })
        $encargoAceptado = @($mensajesHilo | Where-Object {
          ($_.tipo -eq 'encargo') -and
          ($_.para -eq $De -or (Mesa-NormalizarHerramienta $_.para) -eq $agenteDecora -or $_.herramienta -eq $agenteDecora) -and
          ($_.estado -in @('aprobado', 'ejecutando', 'hecho'))
        })
        
        if ($encargoAceptado.Count -eq 0) {
          $motivoRechazo = "El hilo no contiene un encargo aceptado para el agente $De"
        }
      }
      
      $rutaDespacho = Join-Path $Global:Mesa_Raiz "despachos\$agenteDecora.json"
      
      if (-not $motivoRechazo) {
        $despacho = if (Test-Path -LiteralPath $rutaDespacho) { Mesa-LeerJson $rutaDespacho } else { $null }
        if (-not $despacho) {
          $despacho = [ordered]@{
            '$schema'            = 'http://json-schema.org/draft-07/schema#'
            agente               = $agenteDecora
            actualizado          = $ahora
            estilo               = [ordered]@{ paleta_acento = 'personal'; pared_color = '#1f2937'; suelo_patron = 'madera' }
            muebles              = @()
            decoraciones         = @()
            disposicion_personal = [ordered]@{ posicion_cafe = 'derecha'; planta_interior = 'pixel' }
          }
        }
        
        $accion = if ($decJson.accion) { [string]$decJson.accion } else { 'anadir' }
        $objId = if ($decJson.id) { [string]$decJson.id } elseif ($decJson.objeto) { [string]$decJson.objeto } else { 'decoracion' }
        $objTipo = if ($decJson.tipo) { [string]$decJson.tipo } elseif ($decJson.objeto) { [string]$decJson.objeto } else { 'objeto' }
        $objX = if ($null -ne $decJson.x) { [int]$decJson.x } else { 542 }
        $objY = if ($null -ne $decJson.y) { [int]$decJson.y } else { 182 }
        $objMotivo = if ($decJson.motivo) { [string]$decJson.motivo } else { $TraspasoHecho }
        
        $decsActuales = [System.Collections.Generic.List[object]]::new()
        if ($despacho.decoraciones) {
          foreach ($d in $despacho.decoraciones) { $decsActuales.Add($d) }
        }
        
        switch ($accion.ToLowerInvariant()) {
          'anadir' {
            $existente = $decsActuales | Where-Object { $_.id -eq $objId }
            if ($existente) { [void]$decsActuales.Remove($existente) }
            $nuevaDec = [ordered]@{
              id            = $objId
              tipo          = $objTipo
              x             = $objX
              y             = $objY
              merito_origen = [ordered]@{
                hilo        = $Hilo
                descripcion = $objMotivo
              }
            }
            $decsActuales.Add($nuevaDec)
          }
          'mover' {
            $item = $decsActuales | Where-Object { $_.id -eq $objId }
            if ($item) {
              $item.x = $objX
              $item.y = $objY
            } else {
              $motivoRechazo = "No existe la decoracion '$objId' para mover"
            }
          }
          'quitar' {
            $item = $decsActuales | Where-Object { $_.id -eq $objId }
            if ($item) {
              [void]$decsActuales.Remove($item)
            } else {
              $motivoRechazo = "No existe la decoracion '$objId' para quitar"
            }
          }
          default {
            $motivoRechazo = "Accion de decoracion desconocida: $accion"
          }
        }
        
        if (-not $motivoRechazo) {
          $despacho.decoraciones = @($decsActuales)
          $despacho.actualizado = $ahora
          Mesa-EscribirJson $rutaDespacho $despacho
          Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tDECORACION_APROBADA`thilo={1}`tn={2}`tde={3}`tpara={4}`tmodelo={5}`tmotivo=Decoracion {6} {7}" -f $ahora, $Hilo, $num, $De, $De, $modeloEf, $accion, $objId)
          Write-Output "Decoracion aplicada en despacho de ${De}: $accion $objId"
        }
      }
      
      if ($motivoRechazo) {
        Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tDECORACION_RECHAZADA`thilo={1}`tn={2}`tde={3}`tpara={4}`tmodelo={5}`tmotivo={6}" -f $ahora, $Hilo, $num, $De, $De, $modeloEf, $motivoRechazo)
        Write-Warning "Decoracion rechazada: $motivoRechazo"
      }
    }

    Mesa-ActualizarHilo $carpeta {
      param($h)
      $h.actualizado = $ahora
      foreach ($p in @($De) + @($Para -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'todos' })) {
        if ($h.participantes -notcontains $p) { $h.participantes += $p }
      }
    } | Out-Null

    Write-Output "$nombreArchivo ($estadoMsg)"
  }

  'leer' {
    if (-not $Hilo) { throw "Uso: mesa.ps1 leer -Hilo <id>" }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $archivoHilo = Join-Path $carpeta 'hilo.json'
    if (-not (Test-Path -LiteralPath $archivoHilo)) {
      throw "No existe el hilo '$Hilo'"
    }
    $h = Mesa-LeerJson $archivoHilo
    Write-Output "=== Hilo: $($h.id) | $($h.titulo) ==="
    Write-Output "Estado: $($h.estado) | Líder: $($h.lider) | Participantes: $($h.participantes -join ', ') | Actualizado: $($h.actualizado)"
    Get-ChildItem -LiteralPath $carpeta -Filter '*-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
      $m = Mesa-LeerMensaje $_.FullName
      Write-Output ("[{0:D4}] {1} | {2} -> {3} ({4}/{5}) | tipo={6} | estado={7}" -f [int]$m.n, $m.fecha, $m.autor, $m.para, $m.herramienta, $m.modelo, $m.tipo, $m.estado)
      Write-Output "       Texto: $($m.texto)"
      if ($m.encargo) { Write-Output "       Encargo: $($m.encargo) (dir: $($m.dir))" }
      if ($m.traspaso -and ($m.traspaso.hecho -or $m.traspaso.falta -or ($m.traspaso.archivos -and $m.traspaso.archivos.Count -gt 0))) {
        Write-Output "       Traspaso: hecho='$($m.traspaso.hecho)' | falta='$($m.traspaso.falta)' | archivos=$($m.traspaso.archivos -join ',')"
      }
    }
  }

  'lider' {
    if (-not $Hilo -or -not $Nuevo) { throw "Uso: mesa.ps1 lider -Hilo <id> -Nuevo <participante>" }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $archivoHilo = Join-Path $carpeta 'hilo.json'
    if (-not (Test-Path -LiteralPath $archivoHilo)) {
      throw "No existe el hilo '$Hilo'"
    }
    $ahora = Mesa-IsoNow
    $previo = @{}
    Mesa-ActualizarHilo $carpeta {
      param($h)
      $previo.lider = $h.lider
      $h.lider = $Nuevo
      $h.actualizado = $ahora
      if ($h.participantes -notcontains $Nuevo) { $h.participantes += $Nuevo }
    } | Out-Null
    $anterior = $previo.lider

    $autorCambio = if ($De) { $De } else { $Global:Mesa_Humano }
    $msg = [ordered]@{
      n           = 0
      autor       = $autorCambio
      para        = $Nuevo
      herramienta = $null
      modelo      = $null
      fecha       = $ahora
      tipo        = 'lider'
      texto       = "Cambio de líder de $anterior a $Nuevo"
      encargo     = $null
      dir         = $Global:Mesa_DefaultDir
      estado      = 'hecho'
      traspaso    = [ordered]@{
        hecho    = "Líder actualizado a $Nuevo"
        falta    = ''
        archivos = @()
      }
      llamada     = [ordered]@{
        inicio = $null
        fin    = $null
        salida = $null
        log    = $null
      }
    }
    Mesa-EscribirMensaje $carpeta $msg $autorCambio | Out-Null
    Write-Output "Líder de $Hilo cambiado a $Nuevo"
  }

  'hilos' {
    if (-not (Test-Path -LiteralPath $Global:Mesa_Hilos)) {
      Write-Output "(sin hilos)"
      return
    }
    $lista = @()
    Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
      $ah = Join-Path $_.FullName 'hilo.json'
      if (Test-Path -LiteralPath $ah) {
        $h = Mesa-LeerJson $ah
        $nMsgs = @(Get-ChildItem -LiteralPath $_.FullName -Filter '*-*.json' -ErrorAction SilentlyContinue).Count
        $lista += [pscustomobject]@{
          Id            = $h.id
          Estado        = $h.estado
          Lider         = $h.lider
          Mensajes      = $nMsgs
          Participantes = ($h.participantes -join ',')
          Actualizado   = $h.actualizado
          Titulo        = $h.titulo
        }
      }
    }
    if ($lista.Count -eq 0) {
      Write-Output "(sin hilos)"
    } else {
      $lista | Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() }
    }
  }

  'pendientes' {
    $pend = @(); $novedades = @()
    $yo = Mesa-NormalizarHerramienta $Para
    if (Test-Path -LiteralPath $Global:Mesa_Hilos) {
      Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        $hId = $_.Name
        $msgs = @(Get-ChildItem -LiteralPath $_.FullName -Filter '*-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { Mesa-LeerMensaje $_.FullName } | Where-Object { $_ })
        $hj = Mesa-LeerJson (Join-Path $_.FullName 'hilo.json')
        $reciente = $hj -and $hj.actualizado -and ([DateTime]::Parse($hj.actualizado) -gt (Get-Date).AddHours(-$Horas))
        if ($yo -and $reciente) {
          # Novedades: lo dirigido a mí después de mi último mensaje en el hilo (las sesiones interactivas no reciben avisos).
          $ultimoMio = (@($msgs | Where-Object { (Mesa-NormalizarHerramienta $_.autor) -eq $yo } | ForEach-Object { [int]$_.n }) + 0 | Measure-Object -Maximum).Maximum
          $novedades += @($msgs | Where-Object {
            [int]$_.n -gt $ultimoMio -and $_.tipo -ne 'encargo' -and (Mesa-NormalizarHerramienta $_.autor) -ne $yo -and
            # Inicio, alcance y bloqueo afectan a los tres, aunque vayan al líder o a una charla con la persona.
            ($_.tipo -in @('avance-inicio','avance-alcance','avance-bloqueo') -or
             @(([string]$_.para) -split '[,;]' | Where-Object { (Mesa-NormalizarHerramienta $_.Trim()) -eq $yo -or $_.Trim() -eq 'todos' }).Count)
          } | ForEach-Object { $t = [string]$_.texto; [pscustomobject]@{ Hilo = $hId; N = $_.n; De = $_.autor; Tipo = $_.tipo; Texto = if ($t.Length -gt 300) { $t.Substring(0, 300) + '…' } else { $t } } })
        }
        $msgs | ForEach-Object {
          $m = $_
          if ($m -and $m.estado -eq 'pendiente') {
            if (-not $Para -or ($m.para -eq $Para) -or ((Mesa-NormalizarHerramienta $m.para) -eq (Mesa-NormalizarHerramienta $Para))) {
              $pend += [pscustomobject]@{
                Hilo        = $hId
                N           = $m.n
                De          = $m.autor
                Para        = $m.para
                Herramienta = $m.herramienta
                Modelo      = $m.modelo
                Encargo     = if ($m.encargo) { $m.encargo } else { $m.texto }
                Motivo      = if ($m.traspaso) { $m.traspaso.falta } else { '' }
              }
            }
          }
        }
      }
    }
    if ($pend.Count -eq 0) {
      Write-Output "(sin encargos pendientes)"
    } else {
      $pend | Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() }
    }
    if ($yo) {
      if ($novedades.Count -eq 0) { Write-Output "(sin novedades para $yo)" }
      else { Write-Output "=== Novedades para $yo (responde en el hilo para darlas por leídas) ==="; $novedades | Format-Table -Wrap -AutoSize | Out-String -Width 220 | ForEach-Object { $_.TrimEnd() } }
    }
  }

  'aprobar' {
    if (-not $Hilo -or $N -le 0) { throw "Uso: mesa.ps1 aprobar -Hilo <id> -N <numero> [-Simular] [-NoLanzar] [-MesaJson <ruta>] [-Motivo <texto>]" }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $arch = Buscar-ArchivoMensaje $carpeta $N
    if (-not $arch) { throw "No existe el mensaje #$N en el hilo '$Hilo'" }

    $m = Mesa-LeerJson $arch.FullName
    $ahora = Mesa-IsoNow
    $m.estado = 'aprobado'
    if ($m.traspaso) {
      $m.traspaso.hecho = "Aprobado el $ahora"
      $m.traspaso.falta = ''
    }
    Mesa-EscribirJson $arch.FullName $m

    $motivoLog = if ($Motivo) { $Motivo } else { 'aprobado manualmente' }
    Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tAPROBADO`thilo={1}`tn={2}`tde={3}`tpara={4}`tmodelo={5}`tmotivo={6}" -f $ahora, $Hilo, $N, $m.autor, $m.para, $m.modelo, $motivoLog)
    Write-Output "Aprobado ${Hilo}#$N"

    if (-not $NoLanzar) {
      $paramsEj = @{ Hilo = $Hilo; N = $N }
      if ($MesaJson) { $paramsEj['MesaJson'] = $MesaJson }
      if ($Simular)  { $paramsEj['Simular']  = $true }
      & "$PSScriptRoot\ejecutar.ps1" @paramsEj
    }
  }

  'rechazar' {
    if (-not $Hilo -or $N -le 0 -or -not $Motivo) { throw "Uso: mesa.ps1 rechazar -Hilo <id> -N <numero> -Motivo <texto>" }
    $carpeta = Join-Path $Global:Mesa_Hilos $Hilo
    $arch = Buscar-ArchivoMensaje $carpeta $N
    if (-not $arch) { throw "No existe el mensaje #$N en el hilo '$Hilo'" }

    $m = Mesa-LeerJson $arch.FullName
    $ahora = Mesa-IsoNow
    $m.estado = 'rechazado'
    if (-not $m.traspaso) {
      $m | Add-Member -NotePropertyName traspaso -NotePropertyValue ([ordered]@{ hecho = ''; falta = "Rechazado: $Motivo"; archivos = @() }) -Force
    } else {
      $m.traspaso.falta = "Rechazado: $Motivo"
    }
    Mesa-EscribirJson $arch.FullName $m

    Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tRECHAZADO`thilo={1}`tn={2}`tde={3}`tpara={4}`tmodelo={5}`tmotivo={6}" -f $ahora, $Hilo, $N, $m.autor, $m.para, $m.modelo, $Motivo)
    Write-Output "Rechazado ${Hilo}#$N ($Motivo)"
  }

  'cuota' {
    $paramsCuota = @{}
    if ($Json)     { $paramsCuota['Json'] = $true }
    if ($MesaJson) { $paramsCuota['MesaJson'] = $MesaJson }
    & "$PSScriptRoot\cuota.ps1" @paramsCuota
  }

  'llamadas' {
    $cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)
    $cont = Mesa-ContadoresLlamadas
    Write-Output "=== Contadores actuales vs Topes ==="
    foreach ($h in @('codex', 'agy', 'claude')) {
      $th = if ($cfg -and $cfg.topes -and $cfg.topes.$h) { $cfg.topes.$h.hora } else { '-' }
      $td = if ($cfg -and $cfg.topes -and $cfg.topes.$h) { $cfg.topes.$h.dia } else { '-' }
      Write-Output ("  {0,-8}: última hora {1}/{2} | hoy {3}/{4}" -f $h, $cont[$h].hora, $th, $cont[$h].dia, $td)
    }
    $hist = @(Mesa-ObtenerLlamadas)
    if ($hist.Count -eq 0) {
      Write-Output "(sin llamadas registradas en registro-tokens.jsonl)"
    } else {
      Write-Output "`n=== Historial de llamadas ==="
      $hist | Select-Object fecha, herramienta, modelo, hilo, n, entrada, salida, total, calidad, segundos, salida_proceso |
        Format-Table -AutoSize | Out-String | ForEach-Object { $_.TrimEnd() }
    }
  }

  'foto' {
    if (-not $Grupo) {
      throw "Uso: mesa.ps1 foto -Grupo flash|claude_gpt|argon|claude [-SemanalLibre <pct>] [-SemanalUsado <pct>] [-CincoHLibre <pct>] [-CincoHUsado <pct>] [-ReiniciaSemanal <xhym>] [-ReiniciaCincoH <xhym>] [-Fecha <ISO>]"
    }
    $fechaDt = if ($Fecha) { [DateTimeOffset]::Parse($Fecha) } else { [DateTimeOffset]::Now }
    $fechaIso = $fechaDt.ToString('yyyy-MM-ddTHH:mm:sszzz')

    $tieneLibre = $PSBoundParameters.ContainsKey('SemanalLibre')
    $tieneUsado = $PSBoundParameters.ContainsKey('SemanalUsado')
    if (-not $tieneLibre -and -not $tieneUsado) {
      throw "Debe indicar -SemanalLibre o -SemanalUsado"
    }
    if ($tieneUsado -and -not $tieneLibre) {
      $SemanalLibre = [Math]::Round(100.0 - $SemanalUsado, 2)
    } elseif ($tieneLibre -and -not $tieneUsado) {
      $SemanalUsado = [Math]::Round(100.0 - $SemanalLibre, 2)
    }

    $objFoto = [ordered]@{
      fecha             = $fechaIso
      grupo             = $Grupo
      semanal_libre_pct = $SemanalLibre
    }
    if ($tieneUsado -or $Grupo -eq 'claude') {
      $objFoto['semanal_usado_pct'] = $SemanalUsado
    }

    if ($PSBoundParameters.ContainsKey('CincoHLibre') -or $PSBoundParameters.ContainsKey('CincoHUsado')) {
      $cLibre = if ($PSBoundParameters.ContainsKey('CincoHLibre')) { $CincoHLibre } else { [Math]::Round(100.0 - $CincoHUsado, 2) }
      $cUsado = if ($PSBoundParameters.ContainsKey('CincoHUsado')) { $CincoHUsado } else { [Math]::Round(100.0 - $CincoHLibre, 2) }
      $objFoto['cinco_h_libre_pct'] = $cLibre
      if ($PSBoundParameters.ContainsKey('CincoHUsado')) {
        $objFoto['cinco_h_usado_pct'] = $cUsado
      }
    }

    if ($ReiniciaSemanal) {
      $objFoto['reinicia_semanal'] = Mesa-ConvertirRelativoAIso $ReiniciaSemanal $fechaDt
    }
    if ($ReiniciaCincoH) {
      $objFoto['reinicia_5h'] = Mesa-ConvertirRelativoAIso $ReiniciaCincoH $fechaDt
    }

    Mesa-AnexarLinea $Global:Mesa_CuotaFotos ($objFoto | ConvertTo-Json -Compress)
    Mesa-Recalibrar
    Write-Output "Foto registrada: grupo=$Grupo fecha=$fechaIso semanal_libre=$SemanalLibre%"

    # Refrescar cuota-estado.json
    try {
      & "$PSScriptRoot\cuota.ps1" | Out-Null
    } catch {}

    # Calibrar tokens
    try {
      & "$PSScriptRoot\tokens-calibrador.ps1" -Silencioso | Out-Null
    } catch {}
  }
}
