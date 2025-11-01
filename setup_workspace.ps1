#Requires -Version 5.1
param(
  [string]$ConfigFile
)
# Quickup Windows Setup (FULL) — cloning, deps, toolchains, run (optional)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$global:PSNativeCommandUseErrorActionPreference = $false

# ---------- Logging ----------
function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ---------- Global flags (can be overridden by config/env) ----------
$script:Cfg = [ordered]@{}
$script:NonInteractive = $false
$script:AssumeYes      = $false
$script:EnableRun      = $false
$script:SkipToolchains = $false

if ($env:QUICKUP_NONINTERACTIVE -and $env:QUICKUP_NONINTERACTIVE -ne "0") { $script:NonInteractive = $true }
if ($env:QUICKUP_ASSUME_YES     -and $env:QUICKUP_ASSUME_YES     -ne "0") { $script:AssumeYes      = $true }
if ($env:QUICKUP_ENABLE_RUN     -and $env:QUICKUP_ENABLE_RUN     -ne "0") { $script:EnableRun      = $true }
if ($env:QUICKUP_SKIP_TOOLCHAINS-and $env:QUICKUP_SKIP_TOOLCHAINS-ne "0") { $script:SkipToolchains = $true }

# ---------- Prompt helpers ----------
function Prompt-YesNo {
  param([Parameter(Mandatory=$true)][string]$Message, [bool]$Default=$false)
  if ($script:NonInteractive) { return ($script:AssumeYes -or $Default) }
  $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
  while ($true) {
    $resp = Read-Host "$Message $suffix"
    if ([string]::IsNullOrWhiteSpace($resp)) { return $Default }
    switch ($resp.ToLower()) {
      "y"|"yes" { return $true }
      "n"|"no"  { return $false }
      default   { Write-Host "Please answer y or n." }
    }
  }
}

function Read-InputWithRetry {
  param(
    [Parameter(Mandatory=$true)][string]$Prompt,
    [scriptblock]$Validate = { param($x) return ($null -ne $x -and $x.Trim() -ne "") },
    [int]$Attempts = 5,
    [string]$DefaultIfNI = ""
  )
  if ($script:NonInteractive) { return $DefaultIfNI }
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

# ---------- Config loading (.env / .json / .yaml) ----------
if (-not $ConfigFile -and $env:QUICKUP_CONFIG_FILE) { $ConfigFile = $env:QUICKUP_CONFIG_FILE }

function Load-EnvConfig([string]$Path) {
  foreach ($line in Get-Content -Raw -Path $Path -Encoding UTF8 -split "`n") {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith("#")) { continue }
    if ($line -notmatch "=") { continue }
    $idx = $line.IndexOf("="); if ($idx -lt 1) { continue }
    $k = $line.Substring(0,$idx).Trim(); $v = $line.Substring($idx+1).Trim()
    if ($k.StartsWith("export ")) { $k = $k.Substring(7).Trim() }
    if ($k) { $script:Cfg[$k] = $v }
  }
}
function Load-JsonConfig([string]$Path) {
  try { $obj = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
  catch { Write-Err "Invalid JSON config: $($_.Exception.Message)"; return }
  foreach ($prop in $obj.PSObject.Properties) {
    $script:Cfg[$prop.Name] = $prop.Value
  }
}
function Load-YamlConfig([string]$Path) {
  if (Get-Command yq -ErrorAction SilentlyContinue) {
    try {
      $json = & yq -o=json '.' $Path 2>$null
      if ($json) { $obj = $json | ConvertFrom-Json; foreach ($p in $obj.PSObject.Properties) { $script:Cfg[$p.Name]=$p.Value }; return }
    } catch { Write-Warn "yq parse failed: $($_.Exception.Message)" }
  }
  if (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
    try { $obj = Get-Content -Raw -Path $Path -Encoding UTF8 | ConvertFrom-Yaml; foreach ($p in $obj.PSObject.Properties) { $script:Cfg[$p.Name]=$p.Value }; return }
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

  # Export env vars for this process (do not overwrite existing env)
  foreach ($k in $script:Cfg.Keys) {
    $v = $script:Cfg[$k]
    $existing = Get-Item -Path ("Env:{0}" -f $k) -ErrorAction SilentlyContinue
    if (-not $existing) {
      if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
        [Environment]::SetEnvironmentVariable($k, ($v -join ","), "Process")
      } else {
        [Environment]::SetEnvironmentVariable($k, "$v", "Process")
      }
    }
  }

  # Flags from config
  if ($script:Cfg.Contains("QUICKUP_NONINTERACTIVE")) { $script:NonInteractive = ($script:Cfg["QUICKUP_NONINTERACTIVE"].ToString() -ne "0") }
  if ($script:Cfg.Contains("QUICKUP_ASSUME_YES"))     { $script:AssumeYes      = ($script:Cfg["QUICKUP_ASSUME_YES"].ToString()     -ne "0") }
  if ($script:Cfg.Contains("QUICKUP_ENABLE_RUN"))     { $script:EnableRun      = ($script:Cfg["QUICKUP_ENABLE_RUN"].ToString()     -ne "0") }
  if ($script:Cfg.Contains("QUICKUP_SKIP_TOOLCHAINS")){ $script:SkipToolchains = ($script:Cfg["QUICKUP_SKIP_TOOLCHAINS"].ToString()-ne "0") }

  $script:NonInteractive = $true
  $script:AssumeYes = $true
  Write-Info "Non-interactive mode forced via config file."
}

# ---------- Core installers ----------
function Ensure-Winget {
  if (Test-Command winget) { return $true }
  Write-Warn "winget not found."
  if (Prompt-YesNo -Message "Open Microsoft Store to install 'App Installer' (winget)?" -Default $false) {
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" | Out-Null
  }
  return (Test-Command winget)
}
function Ensure-Choco {
  if (Test-Command choco) { return $true }
  Write-Warn "Chocolatey not found."
  if (Prompt-YesNo -Message "Install Chocolatey now?" -Default $false) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
  }
  return (Test-Command choco)
}

function Maybe-Install-Git {
  if (Test-Command git) { Write-Ok "git found: $(git --version)"; return }
  if (-not (Prompt-YesNo -Message "Git not found. Install Git now?" -Default $false)) { Write-Err "Git is required to clone repos."; return }
  if (Ensure-Winget) { winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install git -y }
  Refresh-EnvPath
  @("C:\Program Files\Git\cmd","C:\Program Files\Git\bin","C:\Program Files (x86)\Git\cmd","C:\Program Files\Git\usr\bin") | ForEach-Object { Try-AddPath $_ }
  if (Test-Command git) { Write-Ok "git installed: $(git --version)" } else { Write-Err "git still missing after attempted install." }
}
function Start-DockerDesktopSafe {
  try {
    $candidates = @(
      "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
      "$env:ProgramFiles\Docker\Docker\Docker Desktop\Docker Desktop.exe",
      "$env:LOCALAPPDATA\Docker\Docker\Docker Desktop.exe"
    )
    foreach ($exe in $candidates) {
      if (Test-Path $exe) { Write-Info "Starting Docker Desktop: $exe"; Start-Process -FilePath $exe -ErrorAction SilentlyContinue | Out-Null; return $true }
    }
    Start-Process "Docker Desktop" -ErrorAction Stop | Out-Null; return $true
  } catch { Write-Warn "Could not start Docker Desktop automatically: $($_.Exception.Message)"; return $false }
}
function Maybe-Install-DockerDesktop {
  if (Test-Command docker) { Write-Ok "docker found: $(docker --version)" }
  else {
    if (-not (Prompt-YesNo -Message "Docker Desktop not found. Install Docker Desktop now?" -Default $false)) { Write-Warn "Docker not installed. Docker-based run options may fail."; return }
    $installed = $false
    if (Ensure-Winget) { try { winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements; $installed=$true } catch { Write-Warn $_.Exception.Message } }
    elseif (Ensure-Choco) { try { choco install docker-desktop -y; $installed=$true } catch { Write-Warn $_.Exception.Message } }
    Start-Sleep -Seconds 2
    [void](Start-DockerDesktopSafe)
  }
  $dockerBin = "$env:ProgramFiles\Docker\Docker\resources\bin"
  if (-not (Test-Command docker) -and (Test-Path $dockerBin)) { Try-AddPath $dockerBin }
  if (Test-Command docker) {
    Write-Info "Checking Docker daemon…"
    $ok = $false; 1..20 | ForEach-Object { try { docker info *> $null; $ok=$true; break } catch { Start-Sleep -Seconds 2 } }
    if ($ok) { Write-Ok "Docker daemon reachable." } else { Write-Warn "Docker daemon not ready yet." }
  }
}
function Maybe-Install-Make {
  if (Test-Command make) { Write-Ok "make found."; return }
  if (-not (Prompt-YesNo -Message "Make not found. Attempt to install it now?" -Default $false)) { Write-Warn "Skipping make install."; return }
  if (Ensure-Choco) { choco install make -y }
  elseif (Ensure-Winget) { Write-Warn "winget lacks a great 'make' package; consider MSYS2."; if (Prompt-YesNo -Message "Install MSYS2?" -Default $false) { winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements } }
}

# PATH helpers
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

# ---------- Ecosystem installers ----------
function Maybe-Install-NvmWindows {
  if (Test-Command nvm) { Write-Ok "nvm-windows found: $(nvm version)"; return $true }
  if (-not (Prompt-YesNo -Message "Install nvm-windows (Node Version Manager)?" -Default $false)) { Write-Warn "Skipping nvm-windows install."; return $false }
  if (Ensure-Winget) { winget install --id CoreyButler.NVMforWindows -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install nvm -y }
  Refresh-EnvPath
  if (Test-Command nvm) { Write-Ok "nvm-windows installed."; return $true } else { Write-Warn "nvm-windows not detected after install."; return $false }
}
function Install-Node-Version { param([string]$Ver)
  if (-not (Test-Command nvm)) { Write-Warn "nvm not available. Skipping Node version install."; return }
  nvm install $Ver
  nvm use $Ver
  Write-Ok "Node $Ver installed and selected (nvm-windows)"
  try { corepack enable *> $null } catch {}
}
function Ensure-PythonTools {
  if (-not (Test-Command python)) {
    if (-not (Prompt-YesNo -Message "Python not found. Install latest Python?" -Default $false)) { return }
    if (Ensure-Winget) { winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements }
    elseif (Ensure-Choco) { choco install python -y }
    Refresh-EnvPath
  }
  try { python -m ensurepip --upgrade *> $null } catch {}
  Write-Ok "Python & pip checked."
}
function Install-Java { param([string]$Version)
  $map = @{
    "8"  = "EclipseAdoptium.Temurin.8.JDK"
    "11" = "EclipseAdoptium.Temurin.11.JDK"
    "17" = "EclipseAdoptium.Temurin.17.JDK"
    "21" = "EclipseAdoptium.Temurin.21.JDK"
  }
  $pkg = $map[$Version]; if (-not $pkg) { $pkg = "EclipseAdoptium.Temurin.$Version.JDK" }
  if (Ensure-Winget) { winget install --id $pkg -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install ("temurin" + $Version) -y }
  Refresh-EnvPath
}
function Maybe-Install-Flutter {
  if (Test-Command flutter) { Write-Ok "Flutter found: $(flutter --version | Select-Object -First 1)"; return }
  if (-not (Prompt-YesNo -Message "Install Flutter SDK?" -Default $false)) { return }
  if (Ensure-Winget) { winget install --id Google.Flutter -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install flutter -y }
  Refresh-EnvPath
  Try-AddPath "$env:USERPROFILE\flutter\bin"
}
function Maybe-Install-FVM {
  if (Test-Command fvm) { Write-Ok "FVM found."; return }
  if (-not (Prompt-YesNo -Message "Install FVM (Flutter Version Manager)?" -Default $false)) { return }
  if (-not (Test-Command dart)) {
    if (Test-Command flutter) { try { flutter pub global activate fvm } catch {} }
  } else { try { dart pub global activate fvm } catch {} }
  $pubBin = Join-Path $env:USERPROFILE ".pub-cache\bin"; Try-AddPath $pubBin
  Write-Ok "FVM attempted. If 'fvm' is not found, open a new shell."
}

# ---------- Project detection + run ----------
function Is-FlutterRepo { return (Test-Path "pubspec.yaml" -PathType Leaf -and (Select-String -Path "pubspec.yaml" -Pattern '^\s*flutter:' -Quiet)) }
function Is-NodeRepo    { return (Test-Path "package.json" -PathType Leaf) }
function Is-PythonRepo  { return (Test-Path "requirements.txt" -PathType Leaf) -or (Test-Path "pyproject.toml" -PathType Leaf) -or (Test-Path "Pipfile" -PathType Leaf) }
function Is-JavaRepo    { return (Test-Path "pom.xml" -PathType Leaf) -or (Test-Path "build.gradle" -PathType Leaf) -or (Test-Path "build.gradle.kts" -PathType Leaf) }
function Read-NodeEngine {
  try { if (Test-Path "package.json") { $j = Get-Content "package.json" -Raw | ConvertFrom-Json; return "$($j.engines.node)" } } catch {}
  return ""
}
function Has-MakeUp { if (Test-Path "Makefile") { return [bool](Select-String -Path "Makefile" -Pattern '^\s*up:' -Quiet) } return $false }
function Get-ComposeFile { foreach ($f in @("docker-compose.yml","docker-compose.yaml","compose.yml","compose.yaml")) { if (Test-Path $f) { return $f } } return $null }
function Has-PackageJsonStart {
  if (Test-Path "package.json") {
    try { $json = Get-Content "package.json" -Raw | ConvertFrom-Json ; return [bool]$json.scripts.start } catch { return $false }
  }
  return $false
}
function Preferred-PM {
  if (Test-Path "yarn.lock") { return "yarn" }
  if (Test-Path "pnpm-lock.yaml") { return "pnpm" }
  if (Test-Path "package-lock.json" -or (Test-Path "package.json")) { return "npm" }
  return ""
}
function Detect-RunOption {
  if (Has-MakeUp) { return "make" }
  if (Get-ComposeFile) { return "compose" }
  if (Has-PackageJsonStart) { return (Preferred-PM) }
  return ""
}

# ---------- Smart git clone ----------
function Invoke-GitClone {
  param([Parameter(Mandatory=$true)][string]$Repo, [string]$Folder)
  $target = if ($Folder) { $Folder } else {
    $n = [IO.Path]::GetFileNameWithoutExtension($Repo.TrimEnd('/')); if ($n.EndsWith(".git")) { $n = $n.Substring(0,$n.Length - 4) }; $n
  }
  if (Test-Path $target) {
    Write-Warn "Destination path '$target' already exists."
    if ($script:NonInteractive) { Write-Warn "Non-interactive: skipping clone for $Repo"; return $false }
    $choice = Read-Host "Choose: [S]kip, [O]verwrite, [R]ename (default: S)"
    switch (($choice | ForEach-Object { $_.ToString().ToLower() })) {
      "o" { try { Remove-Item -Recurse -Force -Path $target } catch { Write-Err "Failed to remove '$target': $($_.Exception.Message)"; return $false } }
      "r" { $suffix = (Get-Random -Minimum 100 -Maximum 999); $target = "${target}_$suffix"; Write-Info "Using new folder name: $target" }
      default { Write-Warn "Skipping clone for $Repo."; return $false }
    }
  }
  $oldEAP = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $args = @('clone','--progress', $Repo, $target)
    Write-Info "Running: git $($args -join ' ')"
    $out = & git @args 2>&1
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $oldEAP }
  if ($code -ne 0) {
    Write-Err "git clone failed (exit $code) for: $Repo"
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
    return $false
  }
  if ($out) { $out | ForEach-Object { Write-Host $_ } }
  Write-Ok "Clone succeeded."
  return $true
}

# ---------- Steps ----------
$script:Cloned = @()

function Step-WorkspaceAndClone {
  Maybe-Install-Git

  # Workspace
  $workspace = $null
  if ($script:Cfg.Contains("QUICKUP_WORKSPACE")) { $workspace = "$($script:Cfg["QUICKUP_WORKSPACE"])"; Write-Info "Workspace: $workspace (from config)" }
  else { $workspace = Read-InputWithRetry -Prompt "Enter a workspace name" -Validate { param($x) -not [string]::IsNullOrWhiteSpace($x) } -DefaultIfNI "workspace" }
  if (-not $workspace) { Write-Err "No valid workspace name. Skipping workspace setup."; return }
  New-Item -ItemType Directory -Force -Path $workspace | Out-Null
  Set-Location $workspace

  # Repos
  $repos = @()
  $folders = @()
  if ($script:Cfg.Contains("QUICKUP_REPOS")) {
    $val = $script:Cfg["QUICKUP_REPOS"]
    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) { $repos = @($val) } else { $repos = @("$val".Split(",") | ForEach-Object { $_.Trim() } ) }
  }
  if ($script:Cfg.Contains("QUICKUP_REPO_FOLDERS")) {
    $val = $script:Cfg["QUICKUP_REPO_FOLDERS"]
    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) { $folders = @($val) } else { $folders = @("$val".Split(",") | ForEach-Object { $_.Trim() } ) }
  }

  if ($repos.Count -eq 0 -and -not $script:NonInteractive) {
    $count = Read-InputWithRetry -Prompt "How many repos would you like to clone? (e.g. 2)" -Validate { param($x) ($x -as [int]) -and ([int]$x -ge 1) } -DefaultIfNI "0"
    if ($count) { $count = [int]$count } else { $count = 0 }
    for ($i=1; $i -le $count; $i++) {
      $repo = Read-InputWithRetry -Prompt "[$i/$count] Repo URL (HTTPS or SSH)" -Validate { param($u) ($u -match '^https?://.+|^git@.+:.+') }
      if (-not $repo) { Write-Warn "Skipping this repo."; continue }
      $repos += $repo
      $folder = Read-InputWithRetry -Prompt "Optional folder name (Enter for default)" -Validate { param($x) $true } -Attempts 1
      if ($folder) { $folders += $folder } else { $folders += "" }
    }
  }

  for ($i=0; $i -lt $repos.Count; $i++) {
    $r = $repos[$i]
    $f = if ($i -lt $folders.Count) { $folders[$i] } else { "" }
    $ok = $false
    if ([string]::IsNullOrWhiteSpace($f)) { $ok = Invoke-GitClone -Repo $r } else { $ok = Invoke-GitClone -Repo $r -Folder $f }
    if ($ok) {
      if ([string]::IsNullOrWhiteSpace($f)) {
        $name = [IO.Path]::GetFileNameWithoutExtension($r.TrimEnd('/')); if ($name.EndsWith(".git")) { $name = $name.Substring(0, $name.Length-4) }
        $script:Cloned += $name; Write-Ok "Cloned into .\$name"
      } else { $script:Cloned += $f; Write-Ok "Cloned into .\$f" }
    }
  }
}

function Step-CoreDependencies {
  Maybe-Install-DockerDesktop
  Maybe-Install-Make
}

function Step-ToolchainsPerRepo {
  if ($script:SkipToolchains) { Write-Warn "Skipping toolchain installs (QUICKUP_SKIP_TOOLCHAINS=1)"; return }
  foreach ($dir in $script:Cloned) {
    Write-Info "Analyzing $dir for ecosystem tooling…"
    Push-Location $dir
    try {
      if (Is-FlutterRepo) {
        Write-Info "Flutter project detected."
        if (Prompt-YesNo -Message "Install Flutter SDK?" -Default $false) { Maybe-Install-Flutter }
        if (Prompt-YesNo -Message "Install FVM?" -Default $false) { Maybe-Install-FVM }
      }
      if (Is-NodeRepo) {
        Write-Info "Node project detected."
        $nvmReady = Maybe-Install-NvmWindows
        if ($nvmReady -and (Test-Command nvm)) {
          $desired = ""
          if (Test-Path ".nvmrc") { $desired = (Get-Content ".nvmrc" -Raw).Trim() }
          if (-not $desired) { $desired = (Read-NodeEngine) }
          if (-not $desired -and -not $script:NonInteractive) {
            $tmp = Read-InputWithRetry -Prompt "Enter Node version to install (e.g. 20.11.1 or 20)" -Validate { param($x) $x -match '^[0-9]+(\.[0-9]+)*$' }
            if ($tmp) { $desired = $tmp }
          }
          if (-not $desired -and $script:Cfg.Contains("QUICKUP_NODE_VERSION")) { $desired = "$($script:Cfg["QUICKUP_NODE_VERSION"])" }
          if ($desired) { Install-Node-Version $desired } else { Write-Warn "No Node version selected; skipping." }
        }
      }
      if (Is-PythonRepo) {
        Write-Info "Python project detected."
        Ensure-PythonTools
      }
      if (Is-JavaRepo) {
        Write-Info "Java project detected."
        $jv = ""
        if (Test-Path ".java-version") { $jv = (Get-Content ".java-version" -Raw).Trim() }
        if (-not $jv -and $script:Cfg.Contains("QUICKUP_JAVA_VERSION")) { $jv = "$($script:Cfg["QUICKUP_JAVA_VERSION"])" }
        if (-not $jv -and -not $script:NonInteractive) { $jv = Read-InputWithRetry -Prompt "Enter Java version (8/11/17/21)" -Validate { param($x) $x -match '^(8|11|17|21)$' } }
        if ($jv) { Install-Java $jv }
      }
    } finally {
      Pop-Location
    }
  }
}

function Step-SelectAndRun {
  if (-not $script:EnableRun) { Write-Warn "Run step disabled (QUICKUP_ENABLE_RUN=0). Skipping."; return }
  if (-not $script:Cloned -or $script:Cloned.Count -eq 0) {
    Write-Warn "No tracked clones. Scanning for git repos in current directory…"
    $dirs = Get-ChildItem . -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") } | Select-Object -ExpandProperty Name
    if (-not $dirs -or $dirs.Count -eq 0) { Write-Err "No repos found."; return }
    $script:Cloned = $dirs
  }
  $index = 0
  if ($script:NonInteractive -and $script:Cfg.Contains("QUICKUP_RUN_INDEX")) {
    $index = [int]$script:Cfg["QUICKUP_RUN_INDEX"]
  } elseif (-not $script:NonInteractive) {
    Write-Host ""; Write-Info "Select a project directory:"
    for ($i=0; $i -lt $script:Cloned.Count; $i++) { Write-Host "[$($i+1)] $($script:Cloned[$i])" }
    $choice = $null
    for ($i=1; $i -le 5; $i++) {
      $tmp = Read-Host "Enter a number"
      if ($tmp -as [int] -and [int]$tmp -ge 1 -and [int]$tmp -le $script:Cloned.Count) { $choice = [int]$tmp; break }
      else { Write-Warn "Invalid selection. Attempt $i/5" }
    }
    if (-not $choice) { Write-Err "No valid selection after retries."; return }
    $index = $choice - 1
  } else {
    $index = 0
  }

  $project = $script:Cloned[$index]
  Push-Location $project
  try {
    $detected = Detect-RunOption
    switch ($detected) {
      "make"   { if (Test-Command make) { Write-Info "Auto: make up…"; & make up } else { Write-Warn "make not found." } }
      "compose"{ $compose = if (Test-Command docker) { "docker compose" } else { $null }; if ($compose) { Write-Info "Auto: $compose up -d…"; & $compose up -d } else { Write-Warn "docker/compose not available." } }
      "yarn"   { try { corepack enable *> $null } catch {}; if (Test-Command yarn) { if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }; yarn start } }
      "pnpm"   { try { corepack enable *> $null } catch {}; if (Test-Command pnpm) { pnpm install; pnpm start } }
      "npm"    { if (Test-Command npm) { if (Test-Path "package-lock.json") { npm ci } else { npm install }; npm run start } else { Write-Warn "npm not available." } }
      default  { Write-Warn "No run method detected in '$project'." }
    }
  } finally { Pop-Location }
  Write-Ok "Run step completed."
}

# ---------- Main ----------
try {
  Write-Info "Step 1/4: Project Workspace & Repository Cloning"
  Step-WorkspaceAndClone
  Write-Host ""

  Write-Info "Step 2/4: Core Dependencies (Docker, Make)"
  Step-CoreDependencies
  Write-Host ""

  Write-Info "Step 3/4: Toolchains per repository"
  Step-ToolchainsPerRepo
  Write-Host ""

  Write-Info "Step 4/4: Choose and run a project (optional)"
  Step-SelectAndRun
  Write-Host ""

  Write-Ok "All done. Happy hacking! 🚀"
} catch {
  Write-Err ("Fatal error: " + $_.Exception.Message)
}
