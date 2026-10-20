# Lanza mensajes en estado «aprobado» de los hilos de la Mesa, respetando topes de mesa.json.
# Solo para Claude, Codex y Antigravity (agy).
# Uso: ejecutar.ps1 [-Hilo <id>] [-N <num>] [-MesaJson <ruta>] [-Simular] [-Ver]
# -Ver: muestra en la consola lo que hace el agente (herramientas, texto, resultado) mientras lo guarda en el log.
# -Sesion <id>: continúa esa conversación del agente en vez de empezar otra (charla en el panel del agente).
param(
  [string]$Hilo,
  [int]$N = 0,
  [string]$MesaJson,
  [switch]$Simular,
  [switch]$Ver,
  [string]$Sesion
)
if ($Simular) { $env:MESA_SIMULAR = '1' } elseif ($env:MESA_SIMULAR -eq '1') { $Simular = [switch]$true }

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\comun.ps1"
. "$PSScriptRoot\costes.ps1"

$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User') +
            ";$env:USERPROFILE\.local\bin;$env:LOCALAPPDATA\agy\bin;$env:APPDATA\npm"

# Pinta una línea de la salida en streaming (JSON de agy, codex o claude) de forma legible; lo que no es JSON va tal cual.
function Mostrar-Linea([string]$l) {
  if (-not $l.Trim()) { return }
  try { $o = $l | ConvertFrom-Json -ErrorAction Stop } catch { Write-Host $l -ForegroundColor DarkGray; return }
  $corto = { param($s) $s = ([string]$s) -replace '\s+', ' '; if ($s.Length -gt 160) { $s.Substring(0, 160) + '…' } else { $s } }
  if ($o.event -eq 'step_update') {
    $s = $o.step_update
    if ($s.step_type -eq 'tool' -and $s.state -eq 'ACTIVE') {
      $p = $s.tool_info.parameters; $det = if ($p.CommandLine) { $p.CommandLine } elseif ($p.AbsolutePath) { $p.AbsolutePath } elseif ($p.TargetFile) { $p.TargetFile } else { ($p | ConvertTo-Json -Compress -Depth 2) }
      Write-Host "`n  ▶ $($s.tool_name): $(& $corto $det)" -ForegroundColor Cyan
    } elseif ($s.text_delta) { Write-Host $s.text_delta -NoNewline }
  } elseif ($o.event -eq 'result') {
    Write-Host "`n  ✔ $($o.result.status) en $([int]$o.result.duration_seconds) s" -ForegroundColor Green
  } elseif ($o.type -eq 'assistant' -and $o.message.content) {
    foreach ($c in $o.message.content) {
      if ($c.type -eq 'tool_use') { Write-Host "`n  ▶ $($c.name): $(& $corto ($c.input | ConvertTo-Json -Compress -Depth 2))" -ForegroundColor Cyan }
      elseif ($c.type -eq 'text') { Write-Host $c.text }
    }
  } elseif ($o.type -eq 'result') {
    Write-Host "`n  ✔ $($o.subtype) en $([int]($o.duration_ms / 1000)) s" -ForegroundColor Green
  } else {
    # codex exec --json: órdenes y mensajes del agente; el resto (tokens, razonamiento) no se pinta.
    $it = if ($o.item) { $o.item } elseif ($o.msg) { $o.msg } else { $o }
    if ($it.command -and $o.type -notlike '*completed*') { Write-Host "`n  ▶ $(& $corto (@($it.command) -join ' '))" -ForegroundColor Cyan }
    elseif ($it.type -in @('agent_message', 'assistant_message') -and ($it.text -or $it.message)) { Write-Host "`n$(if ($it.text) { $it.text } else { $it.message })" }
  }
}

filter Ver-Y-Guardar([string]$logPath) {
  $l = [string]$_
  [IO.File]::AppendAllText($logPath, $l + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding $false))
  Mostrar-Linea $l
}

function Resolver-RutaEncargo($encargo, $dirBase) {
  if (-not $encargo) { return $null }
  if ([IO.Path]::IsPathRooted($encargo) -and (Test-Path -LiteralPath $encargo)) { return (Resolve-Path -LiteralPath $encargo).Path }
  foreach ($base in @($dirBase, $Global:Mesa_DefaultDir, $Global:Mesa_Base, $Global:Mesa_Raiz)) {
    if ($base) {
      $cand = Join-Path $base $encargo
      if (Test-Path -LiteralPath $cand) { return (Resolve-Path -LiteralPath $cand).Path }
    }
  }
  return $encargo
}

function Extraer-ResultadoYTokens($herramienta, $logPath, $finalTxt, $promptTexto) {
  $entrada = 0; $salida = 0; $total = 0; $medido = $false
  $textoResp = ''

  if ($herramienta -eq 'codex') {
    if ($finalTxt -and (Test-Path -LiteralPath $finalTxt)) {
      $textoResp = ([IO.File]::ReadAllText($finalTxt, [System.Text.Encoding]::UTF8)).Trim()
    }
    if (Test-Path -LiteralPath $logPath) {
      foreach ($linea in [IO.File]::ReadLines($logPath, [System.Text.Encoding]::UTF8)) {
        if (-not $linea.Trim()) { continue }
        if ($linea -match 'token_count|usage|agent_message|message') {
          try {
            $ev = $linea | ConvertFrom-Json
            if ($ev.type -eq 'token_count' -or $ev.payload.type -eq 'token_count') {
              $tc = if ($ev.payload.info.total_token_usage) { $ev.payload.info.total_token_usage }
                    elseif ($ev.info.total_token_usage) { $ev.info.total_token_usage }
                    elseif ($ev.token_count) { $ev.token_count }
                    else { $null }
              if ($tc) {
                $entrada = [int64]$tc.input_tokens + [int64]$tc.cached_input_tokens
                $salida  = [int64]$tc.output_tokens
                $total   = if ($tc.total_tokens) { [int64]$tc.total_tokens } else { $entrada + $salida }
                if ($total -gt 0) { $medido = $true }
              }
            }
            if ($ev.usage) {
              $u = $ev.usage
              $entrada = [int64]$u.input_tokens + [int64]$u.cached_input_tokens
              $salida  = [int64]$u.output_tokens
              $total   = if ($u.total_tokens) { [int64]$u.total_tokens } else { $entrada + $salida }
              if ($total -gt 0) { $medido = $true }
            }
            if (-not $textoResp -and $ev.text) { $textoResp = [string]$ev.text }
            if (-not $textoResp -and $ev.payload.message) { $textoResp = [string]$ev.payload.message }
          } catch {}
        }
      }
      if (-not $textoResp) {
        $textoResp = ([IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)).Trim()
      }
    }
  } else {
    if (Test-Path -LiteralPath $logPath) {
      $raw = ([IO.File]::ReadAllText($logPath, [System.Text.Encoding]::UTF8)).Trim()
      if ($raw) {
        # El log mezcla avisos de la consola con el JSON final: se toma la última línea JSON con «usage».
        $lineaJson = @($raw -split "`r?`n" | Where-Object { $_ -match '^\s*\{' -and $_ -match '"usage"' }) | Select-Object -Last 1
        if ($lineaJson) { $raw = $lineaJson }
        try {
          $obj = $raw | ConvertFrom-Json
          $u = if ($obj.usage) { $obj.usage } elseif ($obj.message.usage) { $obj.message.usage } elseif ($obj.result.usage) { $obj.result.usage } else { $null }
          if ($u) {
            $entrada = [int64]$u.input_tokens + [int64]$u.cache_creation_input_tokens
            $salida  = [int64]$u.output_tokens
            $total   = if ($u.total_tokens) { [int64]$u.total_tokens } else { $entrada + $salida }
            if ($total -gt 0) { $medido = $true }
          }
          if ($obj.result -is [string]) { $textoResp = $obj.result }
          elseif ($obj.response -is [string]) { $textoResp = $obj.response }
          elseif ($obj.result.response -is [string]) { $textoResp = $obj.result.response }
          elseif ($obj.text -is [string]) { $textoResp = $obj.text }
          elseif ($obj.content -is [string]) { $textoResp = $obj.content }
          else { $textoResp = $raw }
        } catch {
          $textoResp = $raw
        }
      }
    }
  }

  if (-not $textoResp) { $textoResp = "(sin texto de salida)" }
  # Si cayó al log crudo (llamada cortada), solo la cola: el log entero llenaba el hilo y el JSON.
  if ($textoResp.Length -gt 4000) { $textoResp = $textoResp.Substring($textoResp.Length - 3000) + "`n[…recortado: ver $logPath]" }
  if (-not $medido) {
    $entrada = [Math]::Max(1, [int64][Math]::Ceiling($promptTexto.Length / 4.0))
    $salida  = [Math]::Max(1, [int64][Math]::Ceiling($textoResp.Length / 4.0))
    $total   = $entrada + $salida
  }
  return [pscustomobject]@{
    texto   = $textoResp
    entrada = $entrada
    salida  = $salida
    total   = $total
    calidad = if ($medido) { 'medido' } else { 'estimado' }
  }
}

function Ejecutar-Mensaje($carpetaHilo, $archivoMsg) {
  $m = Mesa-LeerJson $archivoMsg
  if (-not $m -or $m.estado -ne 'aprobado') { return $false }

  $hiloId = Split-Path -Leaf $carpetaHilo
  $herramienta = if ($m.herramienta) { $m.herramienta } else { Mesa-NormalizarHerramienta $m.para }
  if ($herramienta -notin @('codex', 'agy', 'claude')) {
    return $false
  }

  $cfg = Mesa-LeerJson (Mesa-ConfigPath $MesaJson)
  $contadores = Mesa-ContadoresLlamadas
  $usadosHora = [int]$contadores[$herramienta].hora
  $usadosDia  = [int]$contadores[$herramienta].dia
  $topeHora   = if ($cfg -and $cfg.topes -and $cfg.topes.$herramienta) { [int]$cfg.topes.$herramienta.hora } else { 999 }
  $topeDia    = if ($cfg -and $cfg.topes -and $cfg.topes.$herramienta) { [int]$cfg.topes.$herramienta.dia } else { 999 }

  if ($usadosHora -ge $topeHora -or $usadosDia -ge $topeDia) {
    $motivo = if ($usadosHora -ge $topeHora) {
      "Tope por hora superado para $herramienta ($usadosHora/$topeHora en la última hora)"
    } else {
      "Tope diario superado para $herramienta ($usadosDia/$topeDia hoy)"
    }
    $m.estado = 'pendiente'
    if (-not $m.traspaso) {
      $m | Add-Member -NotePropertyName traspaso -NotePropertyValue ([ordered]@{ hecho = ''; falta = $motivo; archivos = @() }) -Force
    } else {
      $m.traspaso.falta = $motivo
    }
    Mesa-EscribirJson $archivoMsg $m
    Mesa-AnexarLinea $Global:Mesa_Aprobaciones ("{0}`tTOPE_BLOQUEADO`thilo={1}`tn={2}`therramienta={3}`tmotivo={4}" -f (Mesa-IsoNow), $hiloId, $m.n, $herramienta, $motivo)
    Write-Warning "AVISO: No se lanza ${hiloId}#$($m.n): $motivo"
    Write-Output "AVISO: $motivo (el mensaje queda pendiente)"
    return $false
  }

  $workDir = if ($m.dir -and (Test-Path -LiteralPath $m.dir)) { (Resolve-Path -LiteralPath $m.dir).Path } else { $Global:Mesa_DefaultDir }
  $modelo = if ($m.modelo) { $m.modelo } else { Mesa-ModeloPorDefecto $herramienta $cfg }
  $esfuerzo = if ($m.PSObject.Properties['esfuerzo'] -and $m.esfuerzo) { [string]$m.esfuerzo } else { 'medium' }

  $carpetaLogs = Join-Path $carpetaHilo 'logs'
  New-Item -ItemType Directory -Force -Path $carpetaLogs | Out-Null
  $prefijo = '{0:D4}-{1}' -f [int]$m.n, $herramienta
  $logPath  = Join-Path $carpetaLogs "$prefijo.log"
  $finalTxt = Join-Path $carpetaLogs "$prefijo-final.txt"
  $promptTmp = Join-Path $carpetaLogs "$prefijo-prompt.txt"

  $rutaEncargo = Resolver-RutaEncargo $m.encargo $workDir
  $contenidoEncargo = ''
  if ($rutaEncargo -and (Test-Path -LiteralPath $rutaEncargo)) {
    $contenidoEncargo = [IO.File]::ReadAllText($rutaEncargo, [System.Text.Encoding]::UTF8)
  }
  $promptTexto = if ($m.texto -and $contenidoEncargo -and ($m.texto.Trim() -ne $contenidoEncargo.Trim())) {
    "$($m.texto)`n`n$contenidoEncargo"
  } elseif ($contenidoEncargo) {
    $contenidoEncargo
  } else {
    [string]$m.texto
  }
  # Un reintento parte de los puntos de control que dejó el intento cortado, no de cero.
  $intentos = if ($m.PSObject.Properties['intentos']) { [int]$m.intentos } else { 0 }
  if ($intentos -gt 0) {
    $yoN = Mesa-NormalizarHerramienta $m.para
    $avances = @(Get-ChildItem -LiteralPath $carpetaHilo -Filter '*-*.json' | Sort-Object Name | ForEach-Object { Mesa-LeerMensaje $_.FullName } |
      Where-Object { $_ -and $_.tipo -like 'avance-*' -and (Mesa-NormalizarHerramienta $_.autor) -eq $yoN } | Select-Object -Last 5 | ForEach-Object { "- #$($_.n) $($_.texto)" })
    $promptTexto = "REINTENTO $intentos`: tu intento anterior de este encargo quedó cortado. Antes de nada revisa el hilo (mesa.ps1 leer -Hilo $hiloId), tu reclamo y git status; no repitas pasos ya hechos.`n" +
      $(if ($avances.Count) { "Tus últimos puntos de control:`n$($avances -join "`n")`n" } else { "No dejaste puntos de control.`n" }) + "`n$promptTexto"
  }
  # Sin esto el agente atribuía a Daniel lo que manda el líder.
  $promptTexto = "[Mesa de agentes · de $($m.autor) para $($m.para) · hilo $hiloId #$($m.n)]`n$promptTexto"
  [IO.File]::WriteAllText($promptTmp, $promptTexto, (New-Object System.Text.UTF8Encoding $false))
  # PowerShell 5.1 no escapa las comillas al pasar un argumento a un .exe: un encargo con "…" llegaba partido.
  # Regla de Windows: las barras solo cuentan justo antes de una comilla (o al final, que PowerShell cierra con comilla).
  $promptArg = [regex]::Replace($promptTexto, '(\\*)"', { param($c) ($c.Groups[1].Value * 2) + '\"' })
  $promptArg = [regex]::Replace($promptArg, '(\\+)$', { param($c) $c.Groups[1].Value * 2 })

  $inicioDt  = Get-Date
  $muestraAntes = if (!$Simular) { Mesa-MuestraSesion $herramienta ([datetime]::MinValue) $workDir } else { @{} }
  $limiteAntes=@($muestraAntes.Values | Where-Object { $_.rate_limits } | Sort-Object hora -Descending | Select-Object -First 1)
  $inicioIso = Mesa-IsoNow
  # Se vuelve a leer bajo candado: si otro ejecutar.ps1 ya lo tomó, no se lanza dos veces.
  $candado = Mesa-BloquearHilo $carpetaHilo
  try {
    if ((Mesa-LeerJson $archivoMsg).estado -ne 'aprobado') { return $false }
    $m.estado  = 'ejecutando'
    # pid: el supervisor distingue así un encargo vivo de uno huérfano (proceso muerto).
    $m.llamada = [ordered]@{ inicio = $inicioIso; fin = $null; salida = $null; log = $logPath; pid = $PID }
    Mesa-EscribirJson $archivoMsg $m
  } finally { $candado.Dispose() }

  $codigoSalida = 0
  if ($Simular) {
    $simResp = "Respuesta simulada de $($m.para) ($herramienta/$modelo) al mensaje #$($m.n) en $hiloId."
    if ($herramienta -eq 'codex') {
      [IO.File]::WriteAllText($finalTxt, $simResp, (New-Object System.Text.UTF8Encoding $false))
      [IO.File]::WriteAllText($logPath, (@{ type = 'simulado'; message = $simResp } | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
    } else {
      [IO.File]::WriteAllText($logPath, (@{ result = $simResp; simulado = $true } | ConvertTo-Json -Compress), (New-Object System.Text.UTF8Encoding $false))
    }
    $codigoSalida = 0
  } else {
    try {
      switch ($herramienta) {
        'codex' {
          $archivoEntrada = if ($rutaEncargo -and (Test-Path -LiteralPath $rutaEncargo) -and -not $m.texto) { $rutaEncargo } else { $promptTmp }
          # resume no admite -C/-s/--add-dir: el directorio lo da Push-Location y el sandbox, la configuración.
          $argsCodex = if ($Sesion) { @('exec', 'resume', $Sesion, '--skip-git-repo-check', '-c', 'sandbox_mode=workspace-write') }
                       else { @('exec', '--skip-git-repo-check', '-C', $workDir, '-s', 'workspace-write', '--add-dir', $Global:Mesa_DefaultDir) }
          # Red dentro del sandbox: autorizada por Daniel el 18-oct (git, gh y delegar en otros agentes la necesitan).
          $argsCodex += @('-c', 'sandbox_workspace_write.network_access=true', '--json', '-m', $modelo, '-c', "model_reasoning_effort=`"$esfuerzo`"", '-o', $finalTxt, '-')
          Push-Location -LiteralPath $workDir
          try {
            if ($Ver) {
              [IO.File]::WriteAllText($logPath, '')
              Get-Content -Raw -Encoding UTF8 -LiteralPath $archivoEntrada | & codex @argsCodex 2>&1 | Ver-Y-Guardar $logPath
            } else {
              Get-Content -Raw -Encoding UTF8 -LiteralPath $archivoEntrada | & codex @argsCodex *> $logPath
            }
            $codigoSalida = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
          } finally { Pop-Location }
        }
        'agy' {
          $agyCmd = if (Test-Path "$env:LOCALAPPDATA\agy\bin\agy.exe") { "$env:LOCALAPPDATA\agy\bin\agy.exe" } else { 'agy' }
          Push-Location -LiteralPath $workDir
          try {
            $sigue = if ($Sesion) { @('--conversation', $Sesion) } else { @() }
            # 'auto' no está disponible en esta cuenta y agy caía al modo por defecto; accept-edits sí (Daniel, 18-oct).
            if ($Ver) { [IO.File]::WriteAllText($logPath, ''); & $agyCmd -p $promptArg @sigue --model $modelo --mode accept-edits --output-format stream-json 2>&1 | Ver-Y-Guardar $logPath }
            else { & $agyCmd -p $promptArg @sigue --model $modelo --mode accept-edits --output-format json *> $logPath }
            $codigoSalida = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
          } finally {
            Pop-Location
          }
        }
        'claude' {
          Push-Location -LiteralPath $workDir
          try {
            $sigue = if ($Sesion) { @('--resume', $Sesion) } else { @() }
            if ($Ver) { [IO.File]::WriteAllText($logPath, ''); & claude -p $promptArg @sigue --model $modelo --output-format stream-json --verbose 2>&1 | Ver-Y-Guardar $logPath }
            else { & claude -p $promptArg @sigue --model $modelo --output-format json *> $logPath }
            $codigoSalida = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
          } finally {
            Pop-Location
          }
        }
      }
    } catch {
      [IO.File]::AppendAllText($logPath, "`nERROR: $($_.Exception.Message)", (New-Object System.Text.UTF8Encoding $false))
      $codigoSalida = 1
    }
  }

  $finDt  = Get-Date
  $finIso = Mesa-IsoNow
  $segundos = [Math]::Max(0, [int][Math]::Round(($finDt - $inicioDt).TotalSeconds))

  $datos = Extraer-ResultadoYTokens $herramienta $logPath $finalTxt $promptTexto
  $costePct=$null; $coste5h=$null; $costeCalidad='sin medición'; $sesionMedida=$null
  if (!$Simular -and $herramienta -in @('codex','claude')) {
    $muestraDespues=Mesa-MuestraSesion $herramienta $inicioDt $workDir
    # Sólo atribuir si hay una única sesión compatible activa en el intervalo.
    $claves=@($muestraDespues.Keys | Where-Object { !$muestraDespues[$_].modelo -or $muestraDespues[$_].modelo -eq $modelo -or $muestraDespues[$_].modelo -like "claude-$modelo*" })
    if ($claves.Count -eq 1) {
      $clave=$claves[0]; $finM=$muestraDespues[$clave]; $antM=$muestraAntes[$clave]
      $rateAntes=if ($antM.rate_limits) { $antM.rate_limits } elseif ($limiteAntes.Count) { $limiteAntes[0].rate_limits } else { $null }
      $sesionMedida=Split-Path -Leaf $clave
      if ($herramienta -eq 'codex') {
        $baseEntrada=if ($antM) { $antM.entrada } else { 0L }; $baseSalida=if ($antM) { $antM.salida } else { 0L }; $baseTotal=if ($antM) { $antM.total } else { 0L }
        if ($finM.total -ge $baseTotal) {
          $datos.entrada=$finM.entrada-$baseEntrada; $datos.salida=$finM.salida-$baseSalida; $datos.total=$finM.total-$baseTotal; $datos.calidad='medido'
        }
        if ($rateAntes.secondary -and $finM.rate_limits.secondary -and $rateAntes.secondary.resets_at -eq $finM.rate_limits.secondary.resets_at) {
          $delta=[double]$finM.rate_limits.secondary.used_percent-[double]$rateAntes.secondary.used_percent
          if ($delta -ge 0) { $costePct=$delta; $costeCalidad='delta oficial de cuenta; atribución temporal' }
        }
        if ($rateAntes.primary -and $finM.rate_limits.primary -and $rateAntes.primary.resets_at -eq $finM.rate_limits.primary.resets_at) {
          $delta=[double]$finM.rate_limits.primary.used_percent-[double]$rateAntes.primary.used_percent
          if ($delta -ge 0) { $coste5h=$delta }
        }
      } elseif ($finM.total -gt 0) {
        $datos.entrada=$finM.entrada; $datos.salida=$finM.salida; $datos.total=$finM.total
        $datos.calidad=if ($finM.acotada) { 'medido parcial (cola 256 KB)' } else { 'medido' }
      }
    }
  }
  if ($Simular) {
    if ($datos.total -eq 0) {
      $datos.entrada = [Math]::Max(1, [int64][Math]::Ceiling($promptTexto.Length / 4.0))
      $datos.salida  = [Math]::Max(1, [int64][Math]::Ceiling($datos.texto.Length / 4.0))
      $datos.total   = $datos.entrada + $datos.salida
    }
    $datos.calidad = 'simulado'
  }

  $cola = if (Test-Path -LiteralPath $logPath) { $t = [IO.File]::ReadAllText($logPath); $t.Substring([Math]::Max(0, $t.Length - 4000)) } else { '' }
  $causa = if ($codigoSalida -ne 0 -or $cola -match '"status"\s*:\s*"ERROR"') { Mesa-CausaFallo $cola } else { $null }
  if ($causa -and $codigoSalida -eq 0) { $codigoSalida = 1 }
  $estadoFinal = if ($codigoSalida -eq 0) { 'hecho' } else { 'fallo' }
  $m.estado = $estadoFinal
  $m.llamada = [ordered]@{ inicio = $inicioIso; fin = $finIso; salida = [int]$codigoSalida; log = $logPath; causa = $causa.causa; hasta = $causa.hasta }
  if (-not $m.traspaso) {
    $m | Add-Member -NotePropertyName traspaso -NotePropertyValue ([ordered]@{ hecho = $datos.texto; falta = ''; archivos = @($logPath) }) -Force
  } else {
    $m.traspaso.hecho = $datos.texto
  }
  Mesa-EscribirJson $archivoMsg $m

  # Escribir mensaje de respuesta en el hilo con el resultado
  $autorResp = if ($m.para) { $m.para } else { $herramienta }
  $archivosTraspaso = @($logPath)
  if ($herramienta -eq 'codex' -and (Test-Path -LiteralPath $finalTxt)) { $archivosTraspaso += $finalTxt }
  $msgResp = [ordered]@{
    n           = 0
    autor       = $autorResp
    para        = $m.autor
    herramienta = $herramienta
    modelo      = $modelo
    fecha       = $finIso
    tipo        = 'respuesta'
    texto       = $datos.texto
    encargo     = $null
    dir         = $workDir
    estado      = $estadoFinal
    traspaso    = [ordered]@{
      hecho    = $datos.texto
      falta    = if ($codigoSalida -eq 0) { '' } elseif ($causa) { "Código de salida $codigoSalida ($($causa.causa)$(if ($causa.hasta) { " hasta $($causa.hasta)" }))" } else { "Código de salida $codigoSalida" }
      archivos = $archivosTraspaso
    }
    llamada     = [ordered]@{
      inicio = $inicioIso
      fin    = $finIso
      salida = [int]$codigoSalida
      log    = $logPath
    }
  }
  Mesa-EscribirMensaje $carpetaHilo $msgResp $autorResp | Out-Null
  $nResp = $msgResp.n
  Mesa-ActualizarHilo $carpetaHilo { param($h) $h.actualizado = $finIso } | Out-Null

  $regLinea = [ordered]@{
    fecha          = $finIso
    herramienta    = $herramienta
    modelo         = $modelo
    esfuerzo       = $esfuerzo
    inicio         = $inicioIso
    fin            = $finIso
    sesion         = $sesionMedida
    coste_pct      = $costePct
    coste_5h_pct   = $coste5h
    coste_calidad  = $costeCalidad
    hilo           = $hiloId
    n              = [int]$m.n
    entrada        = [int64]$datos.entrada
    salida         = [int64]$datos.salida
    total          = [int64]$datos.total
    calidad        = $datos.calidad
    segundos       = $segundos
    salida_proceso = [int]$codigoSalida
  } | ConvertTo-Json -Compress
  Mesa-AnexarLinea $Global:Mesa_Registro $regLinea

  Write-Output "Llamada $estadoFinal en ${hiloId}#$($m.n) -> respuesta #$nResp ($($datos.total) tokens, $($datos.calidad))"
  return $true
}

if ($Hilo) {
  $carpetaHilo = Join-Path $Global:Mesa_Hilos $Hilo
  if (-not (Test-Path -LiteralPath $carpetaHilo)) {
    Write-Error "No existe el hilo: $Hilo"
    exit 1
  }
  if ($N -gt 0) {
    $arch = Get-ChildItem -LiteralPath $carpetaHilo -Filter ('{0:D4}-*.json' -f $N) -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $arch) {
      Write-Error "No existe el mensaje #$N en el hilo $Hilo"
      exit 1
    }
    Ejecutar-Mensaje $carpetaHilo $arch.FullName | Out-Null
  } else {
    Get-ChildItem -LiteralPath $carpetaHilo -Filter '*-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
      Ejecutar-Mensaje $carpetaHilo $_.FullName | Out-Null
    }
  }
} else {
  if (Test-Path -LiteralPath $Global:Mesa_Hilos) {
    Get-ChildItem -LiteralPath $Global:Mesa_Hilos -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
      $cHilo = $_.FullName
      Get-ChildItem -LiteralPath $cHilo -Filter '*-*.json' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        Ejecutar-Mensaje $cHilo $_.FullName | Out-Null
      }
    }
  }
}

try {
  & "$PSScriptRoot\tokens-calibrador.ps1" -Silencioso | Out-Null
} catch {}
