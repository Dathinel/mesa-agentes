# Hook de Claude Code (SessionStart y UserPromptSubmit): pone delante de Claude lo que la mesa tiene para él, sin depender de
# esperar-novedades.ps1 en segundo plano. Corto y sin bloquear: cualquier fallo sale en silencio con código 0.
# Uso: hook-claude.ps1 -Evento inicio|mensaje
param([ValidateSet('inicio', 'mensaje')][string]$Evento = 'mensaje')
try {
  . "$PSScriptRoot\comun.ps1"
  $visto = Join-Path $Global:Mesa_Raiz 'agentes\claude-visto.txt'
  $desde = if ($Evento -eq 'inicio') { (Get-Date).AddHours(-12) } elseif (Test-Path -LiteralPath $visto) { [datetime]::Parse([IO.File]::ReadAllText($visto).Trim()) } else { (Get-Date).AddHours(-1) }
  $ahora = Get-Date
  $lineas = @(Mesa-Novedades 'claude' $desde 300 3>$null | Select-Object -Last 8)
  if ($Evento -eq 'inicio') {
    # Claude pasa por stdin el id de la sesión: Cuadrilla.bat lo usa para reanudar esta conversación y no la última de la carpeta.
    if ([Console]::IsInputRedirected) { $e = [Console]::In.ReadToEnd() | ConvertFrom-Json; if ($e.session_id) { [IO.File]::WriteAllText((Join-Path $Global:Mesa_Raiz 'sesion-claude.txt'), [string]$e.session_id) } }
    $mios = @(Mesa-Reclamos | Where-Object { (Mesa-NormalizarHerramienta $_.agente) -eq 'claude' } | ForEach-Object { "$($_.tarea) ($($_.hilo))" })
    "[Mesa] Eres claude en la mesa de agentes. Tus reclamos: $(if ($mios.Count) { $mios -join '; ' } else { 'ninguno' }). Protocolo en CLAUDE.md."
  }
  if ($lineas.Count) { "[Mesa] Novedades para claude desde $($desde.ToString('HH:mm')):"; $lineas }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $visto) | Out-Null
  [IO.File]::WriteAllText($visto, $ahora.ToString('o'))
} catch {}
exit 0