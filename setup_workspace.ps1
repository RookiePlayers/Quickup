#Requires -Version 5.1
# Quickup Windows Setup (with config support fix)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:PSNativeCommandUseErrorActionPreference = $false

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

# Placeholder for config file loading (JSON, YAML, ENV)
function Load-ConfigFile {
  param([string]$ConfigFile)

  if (-not (Test-Path $ConfigFile)) {
    Write-Err "Config file not found: $ConfigFile"
    exit 1
  }

  Write-Info "Loading config: $ConfigFile"

  $ext = [IO.Path]::GetExtension($ConfigFile).ToLower()
  switch ($ext) {
    ".json" { $script:Cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json }
    ".yaml" { $script:Cfg = @{}; Write-Warn "YAML parsing not yet implemented in this snippet." }
    ".yml"  { $script:Cfg = @{}; Write-Warn "YAML parsing not yet implemented in this snippet." }
    default {
      $script:Cfg = @{}
      foreach ($line in Get-Content $ConfigFile) {
        if ($line -match '^\s*#') { continue }
        if ($line -match '^\s*$') { continue }
        $pair = $line -split '=', 2
        if ($pair.Count -eq 2) {
          $k = $pair[0].Trim()
          $v = $pair[1].Trim()
          $script:Cfg[$k] = $v
        }
      }
    }
  }

  # Export env vars safely
  foreach ($k in $script:Cfg.Keys) {
    $v = $script:Cfg[$k]
    $existing = Get-Item -Path ("Env:{0}" -f $k) -ErrorAction SilentlyContinue

    if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
      $joined = ($v -join ",")
      if (-not $existing) {
        [Environment]::SetEnvironmentVariable($k, $joined, "Process")
      }
    } else {
      if (-not $existing) {
        [Environment]::SetEnvironmentVariable($k, "$v", "Process")
      }
    }
  }

  Write-Info "Non-interactive mode forced via config file."
}

# Example usage entrypoint
param(
  [string]$ConfigFile
)

if ($ConfigFile) {
  Load-ConfigFile -ConfigFile $ConfigFile
} else {
  Write-Info "No config file specified; running interactively."
}

Write-Ok "Script executed successfully."
