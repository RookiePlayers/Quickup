#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Prompt-YesNo {
  param([Parameter(Mandatory=$true)][string]$Message, [bool]$Default=$true)
  $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
  while ($true) {
    $resp = Read-Host "$Message $suffix"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
    switch ($resp.ToLower()) {
      "y" { return $true }
      "yes" { return $true }
      "n" { return $false }
      "no" { return $false }
      default { Write-Host "Please answer y or n." }
    }
  }
}

# Retry helper: returns $null if validation fails Attempts times.
function Read-InputWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [scriptblock]$Validate = { param($x) return ($null -ne $x -and $x.Trim() -ne "") },
    [int]$Attempts = 5
  )
  for ($i=1; $i -le $Attempts; $i++) {
    $val = Read-Host $Prompt
    try {
      if (& $Validate $val) { return $val }
      else { Write-Warn "Invalid input. Attempt $i/$Attempts" }
    } catch {
      Write-Warn "Validation error. Attempt $i/$Attempts"
    }
  }
  return $null
}

function Refresh-EnvPath {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path','User')
  $global:env:Path = ($machine + ';' + $user).TrimEnd(';')
}
function Try-AddPath { param([string]$Dir)
  if (Test-Path $Dir) {
    $parts = $env:Path -split ';' | ForEach-Object { $_.Trim() }
    if (-not ($parts -contains $Dir)) { $global:env:Path += ';' + $Dir }
  }
}

# (Package installer functions omitted here for brevity — keep your current ones)
# ... Include your Ensure-Winget/Ensure-Choco/Maybe-Install-* functions here (unchanged) ...
# ... Include your ecosystem functions (Node nvm-windows, Java, Flutter/FVM, Python) ...

# ---------- Project detection ----------
function Is-FlutterRepo { return (Test-Path "pubspec.yaml" -PathType Leaf -and (Select-String -Path "pubspec.yaml" -Pattern '^\s*flutter:' -Quiet)) }
function Is-NodeRepo { return (Test-Path "package.json" -PathType Leaf) }
function Is-PythonRepo { return (Test-Path "requirements.txt" -PathType Leaf) -or (Test-Path "pyproject.toml" -PathType Leaf) -or (Test-Path "Pipfile" -PathType Leaf) }
function Is-JavaRepo { return (Test-Path "pom.xml" -PathType Leaf) -or (Test-Path "build.gradle" -PathType Leaf) -or (Test-Path "build.gradle.kts" -PathType Leaf) }

function Read-NodeEngine {
  try {
    if (Test-Path "package.json") { $json = Get-Content "package.json" -Raw | ConvertFrom-Json; return "$($json.engines.node)" }
  } catch {}
  return ""
}

# ---------- Steps (with retries) ----------
function Step-WorkspaceAndClone {
  $workspace = Read-InputWithRetry -Prompt "Enter a workspace name" -Validate { param($x) return (-not [string]::IsNullOrWhiteSpace($x)) }
  if (-not $workspace) { Write-Err "No valid workspace name after 5 attempts. Skipping workspace setup."; return }
  New-Item -ItemType Directory -Force -Path $workspace | Out-Null
  Set-Location $workspace

  $count = Read-InputWithRetry -Prompt "How many repos would you like to clone? (e.g. 2)" -Validate { param($x) return ($x -as [int] -and [int]$x -ge 1) }
  if (-not $count) { Write-Err "Invalid repo count after 5 attempts. Skipping clone step."; return }
  $count = [int]$count

  $script:Cloned = @()
  for ($i=1; $i -le $count; $i++) {
    Write-Host ""
    $repo = Read-InputWithRetry -Prompt "[$i/$count] Repo URL (HTTPS or SSH)" -Validate {
      param($u)
      if ([string]::IsNullOrWhiteSpace($u)) { return $false }
      return ($u -match '^https?://.+|^git@.+:.+')
    }
    if (-not $repo) { Write-Warn "Skipping this repo (invalid URL after retries)."; continue }
    $folder = Read-Host "Optional folder name (Enter for default)"
    if ([string]::IsNullOrWhiteSpace($folder)) {
      git clone $repo 2>$null
      $name = [IO.Path]::GetFileNameWithoutExtension($repo.TrimEnd('/'))
      if ($name.EndsWith(".git")) { $name = $name.Substring(0, $name.Length-4) }
      $script:Cloned += $name
      Write-Ok "Cloned into .\$name"
    } else {
      git clone $repo $folder 2>$null
      $script:Cloned += $folder
      Write-Ok "Cloned into .\$folder"
    }
  }
}

function Step-SelectAndRun {
  if (-not $script:Cloned -or $script:Cloned.Count -eq 0) {
    Write-Warn "No tracked clones. Scanning for git repos in current directory…"
    $dirs = Get-ChildItem . -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") } | Select-Object -ExpandProperty Name
    if (-not $dirs -or $dirs.Count -eq 0) { Write-Err "No repos found."; return }
    $script:Cloned = $dirs
  }

  Write-Host ""
  Write-Info "Select a project directory:"
  for ($i=0; $i -lt $script:Cloned.Count; $i++) { Write-Host "[$($i+1)] $($script:Cloned[$i])" }

  $choice = $null
  for ($i=1; $i -le 5; $i++) {
    $tmp = Read-Host "Enter a number"
    if ($tmp -as [int] -and [int]$tmp -ge 1 -and [int]$tmp -le $script:Cloned.Count) { $choice = [int]$tmp; break }
    else { Write-Warn "Invalid selection. Attempt $i/5" }
  }
  if (-not $choice) { Write-Err "No valid selection after retries."; return }

  $project = $script:Cloned[$choice-1]
  Push-Location $project
  try {
    # (reuse your Detect-RunOption, Maybe-Ensure-Yarn/PNPM, etc. same as earlier version)
    # ...
  } finally {
    Pop-Location
  }

  Write-Ok "Run step completed."
}

# NOTE: Keep the rest of your previously provided functions (dependency installers, toolchain detectors, run logic),
# and simply replace the Step-WorkspaceAndClone and Step-SelectAndRun with these retry-enabled versions.
