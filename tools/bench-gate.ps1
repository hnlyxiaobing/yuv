# bench-gate.ps1 -- yuv performance threshold gate (fail-closed).
#
# Runs `moon bench --target wasm`, parses each benchmark's mean time, and fails
# whenever a threshold is exceeded, a named benchmark is missing/unparsed, or
# the fast path is not faster than the reference path. Any unexpected condition
# fails the gate (fail-closed): there is no "skip" outcome.
#
# Usage:  pwsh -File tools/bench-gate.ps1        (from the module root)
# Exit:   0 = all gates pass, 1 = gate failed (see summary lines).
#
# Thresholds are absolute upper bounds in milliseconds with ~3x headroom over
# 2026-11-09 local measurements (wasm-gc/wasm debug-independent release run):
#   to_rgb nv21 640x480        19.17 ms  ->  60 ms
#   to_rgb_fast nv21 640x480    7.71 ms  ->  30 ms
#   to_rgb i420 640x480        22.77 ms  ->  70 ms
#   to_rgb_fast i420 640x480    8.05 ms  ->  30 ms
#   rotate d90 640x480          2.24 ms  ->  10 ms
#   mirror_x 640x480            2.33 ms  ->  10 ms
# Relative gate: to_rgb_fast must be <= to_rgb for the same input (hard check).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $PSScriptRoot
$thresholdsMs = [ordered]@{
  'to_rgb nv21 640x480'       = 60.0
  'to_rgb_fast nv21 640x480'  = 30.0
  'to_rgb i420 640x480'       = 70.0
  'to_rgb_fast i420 640x480'  = 30.0
  'rotate d90 640x480'        = 10.0
  'mirror_x 640x480'          = 10.0
}
$relativePairs = @(
  @('to_rgb_fast nv21 640x480', 'to_rgb nv21 640x480'),
  @('to_rgb_fast i420 640x480', 'to_rgb i420 640x480')
)

$failures = New-Object System.Collections.Generic.List[string]

# --- run moon bench (non-zero exit or missing tool => fail) -----------------
$benchOutput = ''
$benchExit = 1
try {
  $benchOutput = (& moon -C $moduleRoot bench --target wasm 2>&1 | Out-String)
  $benchExit = $LASTEXITCODE
} catch {
  $failures.Add("moon bench could not be executed: $($_.Exception.Message)")
}
if ($benchExit -ne 0 -and $failures.Count -eq 0) {
  $failures.Add("moon bench exited with code $benchExit")
}

# --- parse benchmark lines: "<name>  <val> <unit> +/- ..." -----------------
$measuredMs = @{}
$linePattern = '^(?<name>.+?)\s+(?<val>[0-9]+(?:\.[0-9]+)?)\s+(?<unit>ns|ms|s|\u00B5s|\u03BCs)\s+\u00b1'
foreach ($line in ($benchOutput -split "`r?`n")) {
  if ($line -match $linePattern) {
    $name = $Matches['name'].Trim()
    $unit = $Matches['unit']
    $value = [double]::Parse($Matches['val'], [Globalization.CultureInfo]::InvariantCulture)
    # Convert to milliseconds.
    $divisor = 1.0
    if ($unit -eq 'ns') { $divisor = 1e-6 }
    elseif ($unit -eq 'ms') { $divisor = 1.0 }
    elseif ($unit -eq 's') { $divisor = 1e3 }
    else { $divisor = 1e-3 } # microseconds (U+00B5 or U+03BC)
    $measuredMs[$name] = $value * $divisor
  }
}

# --- absolute thresholds (missing or over => fail) -------------------------
foreach ($name in $thresholdsMs.Keys) {
  if (-not $measuredMs.ContainsKey($name)) {
    $failures.Add("bench '$name' missing or unparsed (fail-closed)")
    continue
  }
  $ms = $measuredMs[$name]
  $limit = [double]$thresholdsMs[$name]
  if ($ms -gt $limit) {
    $failures.Add("bench '$name' took $([math]::Round($ms, 3)) ms > threshold $limit ms")
  }
}

# --- relative gate: fast path must not be slower than the reference --------
foreach ($pair in $relativePairs) {
  $fast = $pair[0]; $slow = $pair[1]
  if ($measuredMs.ContainsKey($fast) -and $measuredMs.ContainsKey($slow)) {
    if ($measuredMs[$fast] -gt $measuredMs[$slow]) {
      $failures.Add("relative gate violated: '$fast' ($([math]::Round($measuredMs[$fast], 3)) ms) slower than '$slow' ($([math]::Round($measuredMs[$slow], 3)) ms)")
    }
  }
}

# --- summary ---------------------------------------------------------------
Write-Host 'bench-gate: measured mean times (ms)'
foreach ($name in $measuredMs.Keys) {
  Write-Host ("  {0,-26} {1,10:N3}" -f $name, $measuredMs[$name])
}
if ($failures.Count -gt 0) {
  Write-Host 'bench-gate: FAILED'
  foreach ($f in $failures) { Write-Host "  - $f" }
  exit 1
}
Write-Host "bench-gate: PASSED ($($measuredMs.Count) benchmarks within thresholds)"
exit 0
