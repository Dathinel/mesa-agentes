. "$PSScriptRoot\observatorio.ps1"

function Mesa-MuestraSesion([string]$Agente, [datetime]$Desde = [datetime]::MinValue, [string]$Directorio) {
  $sesiones = @{}
  foreach ($f in @(Mesa-Sesiones $Agente | Select-Object -First 24)) {
    $entrada=0L; $salida=0L; $total=0L; $rl=$null; $hora=$null; $cwd=$null; $ids=@{}; $modelo=$null
    foreach ($e in @(Mesa-Jsonl $f.FullName)) {
      $meta = Mesa-Meta $e
      if ($meta.cwd) { $cwd=$meta.cwd }
      if ($meta.modelo) { $modelo=$meta.modelo }
      $fecha = try { [DateTimeOffset]::Parse($e.timestamp).LocalDateTime } catch { [datetime]::MinValue }
      if ($fecha -lt $Desde) { continue }
      if ($e.payload.type -eq 'token_count' -and $e.payload.info.total_token_usage) {
        $u=$e.payload.info.total_token_usage
        $entrada=[long]$u.input_tokens; $salida=[long]$u.output_tokens; $total=[long]$u.total_tokens
        $rl=$e.payload.rate_limits; $hora=$e.timestamp
      }
      if ($Agente -eq 'claude' -and $e.message.usage) {
        $id=[string]$e.message.id
        if ($id -and $ids.ContainsKey($id)) { continue }
        if ($id) { $ids[$id]=$true }
        $u=$e.message.usage
        $entrada += [long]$u.input_tokens + [long]$u.cache_creation_input_tokens + [long]$u.cache_read_input_tokens
        $salida += [long]$u.output_tokens; $total=$entrada+$salida; $hora=$e.timestamp
      }
    }
    if ($Directorio -and $cwd -and $cwd.TrimEnd('\') -ne $Directorio.TrimEnd('\')) { continue }
    if ($hora) { $sesiones[$f.FullName]=@{ entrada=$entrada; salida=$salida; total=$total; rate_limits=$rl; hora=$hora; modelo=$modelo; cwd=$cwd; acotada=($f.Length -gt 262144) } }
  }
  return $sesiones
}

function Mesa-CosteModelo([string]$Agente, [string]$Modelo, $Registros) {
  $muestras = @($Registros | Where-Object { $_.herramienta -eq $Agente -and $_.modelo -eq $Modelo -and $null -ne $_.coste_pct })
  $n=$muestras.Count
  if (!$n) { return @{ media=$null; margen=$null; n=0; calidad='sin muestras' } }
  $media=[double](($muestras | Measure-Object coste_pct -Average).Average)
  $suma=0.0
  foreach ($m in $muestras) { $suma += [Math]::Pow([double]$m.coste_pct-$media,2) }
  $sd=if ($n -gt 1) { [Math]::Sqrt($suma/($n-1)) } else { [Math]::Max($media,1) }
  # Margen orientativo; no confundir atribución entre fotos con medición oficial.
  $margen=1.96*[Math]::Max($sd,0.1)/[Math]::Sqrt($n)
  @{ media=[Math]::Round($media,3); margen=[Math]::Round($margen,2); n=$n; calidad='estimado'; metodo='media y margen orientativo 1.96*s/raiz(N)' }
}

function Mesa-Recalibrar {
  $candado=Mesa-BloquearRegistro
  try {
  $reg = @(Mesa-RegistroLocal $Global:Mesa_Registro)
  $fotos = @(Mesa-RegistroLocal $Global:Mesa_CuotaFotos | Sort-Object fecha)
  $cambios=$false
  foreach ($g in @('claude','flash','argon','claude_gpt')) {
    $serie=@($fotos | Where-Object grupo -eq $g)
    for ($i=1; $i -lt $serie.Count; $i++) {
      $ant=$serie[$i-1]; $fin=$serie[$i]
      $delta=[double]$ant.semanal_libre_pct-[double]$fin.semanal_libre_pct
      if ($delta -lt 0 -or ($ant.reinicia_semanal -and [DateTimeOffset]::Parse($ant.reinicia_semanal) -le [DateTimeOffset]::Parse($fin.fecha))) { continue }
      $tareas=@($reg | Where-Object {
        (($_.herramienta -eq 'claude' -and $g -eq 'claude') -or ($_.herramienta -eq 'agy' -and (Mesa-AgyGrupoPorModelo $_.modelo) -eq $g)) -and
        [DateTimeOffset]::Parse($_.fecha) -gt [DateTimeOffset]::Parse($ant.fecha) -and [DateTimeOffset]::Parse($_.fecha) -le [DateTimeOffset]::Parse($fin.fecha) -and $_.calidad -ne 'simulado'
      })
      if (!$tareas.Count) { continue }
      $dur=0.0; $tok=0.0
      foreach ($t in $tareas) { $dur += [Math]::Max(1,[double]$t.segundos); $tok += [Math]::Max(0,[double]$t.total) }
      foreach ($t in $tareas) {
        $peso=[Math]::Max(1,[double]$t.segundos)/$dur
        if ($tok -gt 0) { $peso=0.5*$peso+0.5*[Math]::Max(0,[double]$t.total)/$tok }
        $coste=[Math]::Round($delta*$peso,5)
        if ($t.calibracion_fin -eq $fin.fecha -and $t.coste_pct -eq $coste) { continue }
        $t | Add-Member coste_pct $coste -Force
        $t | Add-Member coste_calidad 'estimado entre fotos' -Force
        $t | Add-Member calibracion_fin $fin.fecha -Force
        $t | Add-Member calibracion_inicio $ant.fecha -Force
        $cambios=$true
      }
    }
  }
  if ($cambios) {
    # Sólo se recalibran los registros completos, sin truncar el histórico.
    $tmp="$Global:Mesa_Registro.calibracion.$PID"
    [IO.File]::WriteAllLines($tmp, [string[]]@($reg | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress }), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Global:Mesa_Registro -Force
  }
  } finally { $candado.Dispose() }
}
