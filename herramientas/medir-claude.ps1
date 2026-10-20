# Suma los tokens de Claude Code entre dos instantes, leyendo message.usage de las sesiones locales.
# Uso: medir-claude.ps1 -Desde "2026-10-18T09:00" [-Hasta "2026-10-18T10:30"] [-Etiqueta "con plan agy"] [-Registrar]
param(
  [Parameter(Mandatory)][datetime]$Desde,
  [datetime]$Hasta = (Get-Date),
  [string]$Etiqueta = '',
  [switch]$Registrar
)
$ErrorActionPreference = 'Stop'
$raiz = Join-Path $env:USERPROFILE '.claude\projects'
$t = [ordered]@{ entrada = 0L; salida = 0L; cache_escritura = 0L; cache_lectura = 0L; mensajes = 0 }
$desdeUtc = $Desde.ToUniversalTime(); $hastaUtc = $Hasta.ToUniversalTime()
Get-ChildItem -LiteralPath $raiz -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -ge $Desde } | ForEach-Object {
    $fs = [IO.File]::Open($_.FullName, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object IO.StreamReader($fs)
    while ($null -ne ($l = $sr.ReadLine())) {
      if ($l -notmatch '"usage"') { continue }
      try { $o = $l | ConvertFrom-Json } catch { continue }
      if (-not $o.timestamp -or -not $o.message.usage) { continue }
      $ts = [DateTimeOffset]::Parse($o.timestamp).UtcDateTime
      if ($ts -lt $desdeUtc -or $ts -gt $hastaUtc) { continue }
      $u = $o.message.usage
      $t.entrada += [long]$u.input_tokens; $t.salida += [long]$u.output_tokens
      $t.cache_escritura += [long]$u.cache_creation_input_tokens; $t.cache_lectura += [long]$u.cache_read_input_tokens
      $t.mensajes++
    }
    $sr.Close()
  }
# Lo que cuenta para el límite: entrada, salida y escritura en caché; la lectura de caché va aparte.
$t.total_sin_cache_lectura = $t.entrada + $t.salida + $t.cache_escritura
$t.desde = $Desde.ToString('s'); $t.hasta = $Hasta.ToString('s'); $t.etiqueta = $Etiqueta
[pscustomobject]$t | Format-List
if ($Registrar) {
  $archivo = Join-Path $PSScriptRoot '..\datos\mediciones-claude.jsonl'
  Add-Content -LiteralPath $archivo -Value ($t | ConvertTo-Json -Compress) -Encoding UTF8
  "Registrado en datos\mediciones-claude.jsonl"
}
