#Requires -Version 5.1
param(
  [string]$ConfigFile
)
# Quickup Windows Setup (with config handling fix)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:PSNativeCommandUseErrorActionPreference = $false

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

# If -ConfigFile not passed, fall back to env
if (-not $ConfigFile -and $env:QUICKUP_CONFIG_FILE) { $ConfigFile = $env:QUICKUP_CONFIG_FILE }

# -------------------- Config loading (.env / .json / .yaml) --------------------
$script:Cfg = [ordered]@{}
$script:NonInteractive = $false
$script:AssumeYes = $false

if ($env:QUICKUP_NONINTERACTIVE -and $env:QUICKUP_NONINTERACTIVE -ne "0") { $script:NonInteractive = $true }
if ($env:QUICKUP_ASSUME_YES -and $env:QUICKUP_ASSUME_YES -ne "0") { $script:AssumeYes = $true }

function Load-EnvConfig([string]$Path) {
  foreach ($line in Get-Content -Raw -Path $Path -ErrorAction Stop -Encoding UTF8 -split "`n") {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    if ($line -notmatch "=") { continue }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { continue }
    $k = $line.Substring(0,$idx).Trim()
    $v = $line.Substring($idx+1).Trim()
    if ($k.StartsWith("export ")) { $k = $k.Substring(7).Trim() }
    if ($k) { $script:Cfg[$k] = $v }
  }
}
function Load-JsonConfig([string]$Path) {
  try { $obj = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
  catch { Write-Err "Invalid JSON config: $($_.Exception.Message)"; return }
  function Flatten($prefix,$value) {
    if ($null -eq $value) { return @() }
    if ($value -is [Collections.IDictionary]) {
      $pairs=@(); foreach ($k in $value.Keys) { $pairs += Flatten ($(if ($prefix) { "$prefix`_$k" } else { "$k" })), $value[$k] }; return $pairs
    } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
      return @([pscustomobject]@{ __arr__=$true; key=$prefix; values=@($value) })
    } else { return @([pscustomobject]@{ key=$prefix; value="$value" }) }
  }
  foreach ($p in (Flatten "" $obj)) {
    if ($p.__arr__) { $script:Cfg[$p.key] = @($p.values) }
    elseif ($p.key) { $script:Cfg[$p.key] = $p.value }
  }
}
function Load-YamlConfig([string]$Path) {
  if (Get-Command yq -ErrorAction SilentlyContinue) {
    try {
      $json = & yq -o=json '.' $Path 2>$null
      if ($json) { $obj = $json | ConvertFrom-Json; $tmp = New-TemporaryFile; $obj | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp; Load-JsonConfig $tmp; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return }
    } catch { Write-Warn "yq parse failed: $($_.Exception.Message)" }
  }
  if (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
    try { $obj = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Yaml; $tmp = New-TemporaryFile; $obj | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp; Load-JsonConfig $tmp; Remove-Item $tmp -Force -ErrorAction SilentlyContinue; return }
    catch { Write-Err "ConvertFrom-Yaml failed: $($_.Exception.Message)"; return }
  }
  Write-Err "YAML config requires 'yq' or PowerShell 7's ConvertFrom-Yaml."
}

if ($ConfigFile) {
  if (-not (Test-Path $ConfigFile)) { Write-Err "Config file not found: $ConfigFile"; exit 1 }
  Write-Info "Loading config: $ConfigFile"
  switch -regex ($ConfigFile.ToLower()) {
    '\.json$'        { Load-JsonConfig  $ConfigFile }
    '\.(yaml|yml)$'  { Load-YamlConfig  $ConfigFile }
    default          { Load-EnvConfig   $ConfigFile }
  }

  # Export env vars for this process only (don't overwrite if already set)
  foreach ($k in $script:Cfg.Keys) {
    $v = $script:Cfg[$k]
    $existing = Get-Item -Path ("Env:{0}" -f $k) -ErrorAction SilentlyContinue
    if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
      $joined = ($v -join ",")
      if (-not $existing) { [Environment]::SetEnvironmentVariable($k, $joined, "Process") }
    } else {
      if (-not $existing) { [Environment]::SetEnvironmentVariable($k, "$v", "Process") }
    }
  }

  # Force non-interactive + assume-yes
  $script:NonInteractive = $true
  $script:AssumeYes = $true
  Write-Info "Non-interactive mode forced via config file."
}

# -------------------- Minimal demo flow (replace with your full steps) --------------------
function Demo-Step {
  Write-Info "NonInteractive: $script:NonInteractive  AssumeYes: $script:AssumeYes"
  if ($script:Cfg.Contains("QUICKUP_WORKSPACE")) {
    Write-Info ("Workspace from config: " + $script:Cfg["QUICKUP_WORKSPACE"])
  } else {
    if ($script:NonInteractive) {
      Write-Warn "No workspace in config and non-interactive mode enabled."
    } else {
      $ws = Read-Host "Enter workspace name"
      Write-Info "Got: $ws"
    }
  }
}

try {
  Demo-Step
  Write-Ok "Script executed successfully."
} catch {
  Write-Err ("Fatal error: " + $_.Exception.Message)
}
