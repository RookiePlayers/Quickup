#Requires -Version 5.1
# Quickup Windows Setup
# Self-contained, robust, default-no prompts, retry logic, and no missing functions.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Prompt-YesNo {
  param([Parameter(Mandatory=$true)][string]$Message, [bool]$Default=$false) # default = No
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

# ---- Package managers ----
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

# ---- Core installers ----
function Maybe-Install-Git {
  if (Test-Command git) { Write-Ok "git found: $(git --version)"; return }
  if (-not (Prompt-YesNo -Message "Git not found. Install Git now?" -Default $false)) { Write-Err "Git is required to clone repos."; return }
  if (Ensure-Winget) {
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
  } elseif (Ensure-Choco) {
    choco install git -y
  } else {
    Write-Warn "No package manager available."
    if (Prompt-YesNo -Message "Open Git download page?" -Default $true) { Start-Process "https://git-scm.com/download/win" | Out-Null }
  }
  Refresh-EnvPath
  @("C:\Program Files\Git\cmd","C:\Program Files\Git\bin","C:\Program Files (x86)\Git\cmd","C:\Program Files\Git\usr\bin") | ForEach-Object { Try-AddPath $_ }
  if (Test-Command git) { Write-Ok "git installed: $(git --version)" } else { Write-Err "git still missing after attempted install." }
}

function Maybe-Install-DockerDesktop {
  if (Test-Command docker) { Write-Ok "docker found: $(docker --version)" }
  else {
    if (-not (Prompt-YesNo -Message "Docker Desktop not found. Install Docker Desktop now?" -Default $false)) { Write-Warn "Docker not installed. Docker-based run options may fail."; return }
    if (Ensure-Winget) { winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements; Start-Sleep -Seconds 2; Start-Process "Docker Desktop" -ErrorAction SilentlyContinue | Out-Null }
    elseif (Ensure-Choco) { choco install docker-desktop -y; Start-Process "Docker Desktop" -ErrorAction SilentlyContinue | Out-Null }
    else { Write-Warn "No package manager available."; if (Prompt-YesNo -Message "Open Docker Desktop download page?" -Default $true) { Start-Process "https://www.docker.com/products/docker-desktop/" | Out-Null } }
  }
  if (Test-Command docker) {
    Write-Info "Checking Docker daemon…"
    $ok = $false; 1..20 | ForEach-Object { if (docker info *> $null) { $ok = $true; break } ; Start-Sleep -Seconds 2 }
    if ($ok) { Write-Ok "Docker daemon reachable." } else { Write-Warn "Docker daemon not ready. Ensure Docker Desktop is running." }
  }
}

function Maybe-Install-Make {
  if (Test-Command make) { Write-Ok "make found."; return }
  if (-not (Prompt-YesNo -Message "Make not found. Attempt to install it now?" -Default $false)) { Write-Warn "Skipping make install."; return }
  if (Ensure-Choco) { choco install make -y }
  elseif (Ensure-Winget) { Write-Warn "winget lacks a great 'make' package; consider MSYS2."; if (Prompt-YesNo -Message "Install MSYS2?" -Default $false) { winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements; Write-Info "Open MSYS2 and run: pacman -S --needed base-devel make" } }
  Refresh-EnvPath
}

# ---- Ecosystem installers ----
# Node via nvm-windows
function Maybe-Install-NvmWindows {
  if (Test-Command nvm) { Write-Ok "nvm-windows found: $(nvm version)"; return $true }
  if (-not (Prompt-YesNo -Message "Install nvm-windows (Node Version Manager)?" -Default $false)) { Write-Warn "Skipping nvm-windows install."; return $false }
  if (Ensure-Winget) { winget install --id CoreyButler.NVMforWindows -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install nvm -y }
  else { Write-Warn "No package manager available. Download: https://github.com/coreybutler/nvm-windows/releases"; return $false }
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

# Python
function Ensure-PythonTools {
  if (-not (Test-Command python)) {
    if (-not (Prompt-YesNo -Message "Python not found. Install latest Python?" -Default $false)) { return }
    if (Ensure-Winget) { winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements }
    elseif (Ensure-Choco) { choco install python -y }
    else { Write-Warn "No package manager available. Visit https://www.python.org/downloads/windows/" }
    Refresh-EnvPath
  }
  try { python -m ensurepip --upgrade *> $null } catch {}
  Write-Ok "Python & pip checked."
}

# Java via Temurin
function Install-Java { param([string]$Version)
  $map = @{
    "8"  = "EclipseAdoptium.Temurin.8.JDK"
    "11" = "EclipseAdoptium.Temurin.11.JDK"
    "17" = "EclipseAdoptium.Temurin.17.JDK"
    "21" = "EclipseAdoptium.Temurin.21.JDK"
  }
  $pkg = $map[$Version]
  if (-not $pkg) { Write-Warn "Unknown Java version '$Version'. Trying generic Temurin $Version…"; $pkg = "EclipseAdoptium.Temurin.$Version.JDK" }
  if (Ensure-Winget) { winget install --id $pkg -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install temurin$Version -y }
  else { Write-Warn "No package manager. See https://adoptium.net/." }
  Refresh-EnvPath
}

# Flutter & FVM
function Maybe-Install-Flutter {
  if (Test-Command flutter) { Write-Ok "Flutter found: $(flutter --version | Select-Object -First 1)"; return }
  if (-not (Prompt-YesNo -Message "Install Flutter SDK?" -Default $false)) { return }
  if (Ensure-Winget) { winget install --id Google.Flutter -e --accept-source-agreements --accept-package-agreements }
  elseif (Ensure-Choco) { choco install flutter -y }
  else { Write-Warn "No package manager available. See https://docs.flutter.dev/get-started/install"; return }
  Refresh-EnvPath
  Try-AddPath "$env:USERPROFILE\flutter\bin"
}
function Maybe-Install-FVM {
  if (Test-Command fvm) { Write-Ok "FVM found."; return }
  if (-not (Prompt-YesNo -Message "Install FVM (Flutter Version Manager)?" -Default $false)) { return }
  if (-not (Test-Command dart)) {
    if (Test-Command flutter) {
      try { flutter pub global activate fvm } catch { Write-Warn "Failed via flutter; trying dart if available." }
    }
  } else {
    try { dart pub global activate fvm } catch {}
  }
  $pubBin = Join-Path $env:USERPROFILE ".pub-cache\bin"
  Try-AddPath $pubBin
  Write-Ok "FVM attempted. If 'fvm' is not found, open a new shell."
}

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

# ---------- Run detection ----------
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


function Invoke-GitClone {
  param(
    [Parameter(Mandatory=$true)][string]$Repo,
    [Parameter(Mandatory=$false)][string]$Folder
  )

  # Optional debug logs for HTTPS authentication or network issues
  # $env:GIT_TRACE = "1"
  # $env:GIT_CURL_VERBOSE = "1"

  # Determine target dir if not provided
  $target = if ($Folder) { $Folder } else {
    $n = [IO.Path]::GetFileNameWithoutExtension($Repo.TrimEnd('/'))
    if ($n.EndsWith(".git")) { $n = $n.Substring(0, $n.Length - 4) }
    $n
  }

  # Handle existing folder
  if (Test-Path $target) {
    Write-Warn "Destination path '$target' already exists."
    $choice = Read-Host "Choose: [S]kip, [O]verwrite, [R]ename (default: S)"
    switch (($choice | ForEach-Object { $_.ToString().ToLower() })) {
      "o" {
        try {
          Write-Info "Deleting existing '$target'..."
          Remove-Item -Recurse -Force -Path $target
        } catch {
          Write-Err "Failed to remove existing folder '$target': $($_.Exception.Message)"
          return $false
        }
      }
      "r" {
        $suffix = (Get-Random -Minimum 100 -Maximum 999)
        $target = "${target}_$suffix"
        Write-Info "Using new folder name: $target"
      }
      default {
        Write-Warn "Skipping clone for $Repo."
        return $false
      }
    }
  }

  $args = @('clone', '--progress', $Repo, $target)
  Write-Info "Running: git $($args -join ' ')"
  $out = & git @args 2>&1
  $code = $LASTEXITCODE

  if ($code -ne 0) {
    Write-Err "git clone failed (exit $code) for: $Repo"
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
    Write-Warn "Common causes:
    - Auth required (private repo): use HTTPS with a Personal Access Token (PAT) or set up SSH keys.
    - Wrong URL: verify the exact repo URL.
    - Proxy/corporate network issues: set git proxy or try another network.
    - Existing folder conflicts or permissions.
    - Long filenames on older Windows setups: git config --system core.longpaths true."
    return $false
  }

  if ($out) { $out | ForEach-Object { Write-Host $_ } }
  Write-Ok "Clone succeeded."
  return $true
}
else { $args += @($Repo) }

  Write-Info "Running: git $($args -join ' ')"
  $out = & git @args 2>&1
  $code = $LASTEXITCODE

  if ($code -ne 0) {
    Write-Err "git clone failed (exit $code) for: $Repo"
    if ($out) { $out | ForEach-Object { Write-Host $_ } }
    Write-Warn "Common causes:
    - Auth required (private repo): use HTTPS with a Personal Access Token (PAT) or set up SSH keys.
    - Wrong URL: verify the exact repo URL.
    - Proxy/corporate network issues: set git proxy or try another network.
    - Existing folder conflicts or permissions.
    - Long filenames on older Windows setups: git config --system core.longpaths true."
    return $false
  }

  if ($out) { $out | ForEach-Object { Write-Host $_ } }
  Write-Ok "Clone succeeded."
  return $true
}
# ---------- Steps ----------
function Step-WorkspaceAndClone {
  Maybe-Install-Git

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
      Invoke-GitClone -Repo $repo
      $name = [IO.Path]::GetFileNameWithoutExtension($repo.TrimEnd('/'))
      if ($name.EndsWith(".git")) { $name = $name.Substring(0, $name.Length-4) }
      $script:Cloned += $name
      Write-Ok "Cloned into .\$name"
    } else {
      Invoke-GitClone -Repo $repo -Folder $folder
      $script:Cloned += $folder
      Write-Ok "Cloned into .\$folder"
    }
  }
}

function Step-CoreDependencies {
  Maybe-Install-DockerDesktop
  Maybe-Install-Make
}

function Step-ToolchainsPerRepo {
  foreach ($dir in $script:Cloned) {
    Write-Info "Analyzing $dir for ecosystem tooling…"
    Push-Location $dir
    try {
      if (Is-FlutterRepo) {
        Write-Info "Flutter project detected."
        if (Prompt-YesNo -Message "Install Flutter SDK?" -Default $false) { Maybe-Install-Flutter }
        if (Prompt-YesNo -Message "Install FVM?" -Default $false) { Maybe-Install-FVM }
        $pubBin = Join-Path $env:USERPROFILE ".pub-cache\bin"; Try-AddPath $pubBin
      }
      if (Is-NodeRepo) {
        Write-Info "Node project detected."
        $nvmReady = Maybe-Install-NvmWindows
        if ($nvmReady -and (Test-Command nvm)) {
          $desired = ""
          if (Test-Path ".nvmrc") { $desired = (Get-Content ".nvmrc" -Raw).Trim() }
          if (-not $desired) { $desired = (Read-NodeEngine) }
          if (-not $desired) {
            $tmp = Read-InputWithRetry -Prompt "Enter Node version to install (e.g. 20.11.1 or 20)" -Validate { param($x) return ($x -match '^[0-9]+(\.[0-9]+)*$') } -Attempts 5
            if ($tmp) { $desired = $tmp }
          }
          if ($desired) { Install-Node-Version $desired } else { Write-Warn "No Node version selected; skipping." }
        } else {
          Write-Warn "Skipping Node setup (nvm-windows not installed)."
        }
      }
      if (Is-PythonRepo) {
        Write-Info "Python project detected."
        Ensure-PythonTools
        if (Test-Command python) {
          if (Prompt-YesNo -Message "Create a virtual environment (.venv) and install requirements?" -Default $false) {
            try { python -m venv .venv } catch {}
            $venvActivate = Join-Path (Get-Location) ".venv\Scripts\Activate.ps1"
            if (Test-Path $venvActivate) { & $venvActivate }
            if (Test-Path "requirements.txt") { python -m pip install -r requirements.txt }
          }
        }
      }
      if (Is-JavaRepo) {
        Write-Info "Java project detected."
        $jv = ""
        if (Test-Path ".java-version") { $jv = (Get-Content ".java-version" -Raw).Trim() }
        if (-not $jv) { $jv = Read-InputWithRetry -Prompt "Enter Java version (8/11/17/21)" -Validate { param($x) return ($x -match '^(8|11|17|21)$') } -Attempts 5 }
        if ($jv) { Install-Java $jv }
      }
    } finally {
      Pop-Location
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
    $detected = Detect-RunOption
    $label = switch ($detected) {
      "make"   { "Make (make up)" }
      "compose"{ "Docker Compose (up -d)" }
      "yarn"   { "Yarn (yarn start)" }
      "pnpm"   { "PNPM (pnpm start)" }
      "npm"    { "npm (npm run start)" }
      default  { "Unknown" }
    }
    Write-Host ""
    Write-Info "Run options for $(Get-Location):"
    $menu = @("Auto (recommended: $label)", "Make (make up)", "Yarn (yarn start)", "npm (npm run start)", "PNPM (pnpm start)", "Docker Compose (up -d)", "Quit")
    for ($i=0; $i -lt $menu.Count; $i++) { Write-Host "[$($i+1)] $($menu[$i])" }
    $sel = Read-Host "Choose an option [default 1]"
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = 1 } else { $sel = [int]$sel }

    switch ($sel) {
      1 {
        switch ($detected) {
          "make"   { if (Test-Command make) { Write-Info "Auto: make up…"; & make up } else { Write-Warn "make not found; pick another option." } }
          "compose"{ $compose = if (Test-Command docker) { "docker compose" } else { $null }; if ($compose) { Write-Info "Auto: $compose up -d…"; & $compose up -d } else { Write-Warn "docker/compose not available." } }
          "yarn"   { try { yarn --version *> $null } catch { try { corepack enable *> $null } catch {}; try { corepack prepare yarn@stable --activate *> $null } catch {} }; if (Test-Command yarn) { if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }; yarn start } }
          "pnpm"   { try { pnpm -v *> $null } catch { try { corepack enable *> $null } catch {}; try { corepack prepare pnpm@latest --activate *> $null } catch {} }; if (Test-Command pnpm) { pnpm install; pnpm start } }
          "npm"    { if (Test-Command npm) { if (Test-Path "package-lock.json") { npm ci } else { npm install }; npm run start } else { Write-Warn "npm not available." } }
          default  { Write-Warn "No run method detected. Pick a manual option." }
        }
      }
      2 { if (Test-Command make) { & make up } else { Write-Err "make is not installed." } }
      3 { try { corepack enable *> $null } catch {}; if (Test-Command yarn) { if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }; yarn start } }
      4 { if (Test-Command npm) { if (Test-Path "package-lock.json") { npm ci } else { npm install }; npm run start } else { Write-Err "npm missing." } }
      5 { try { corepack enable *> $null } catch {}; if (Test-Command pnpm) { pnpm install; pnpm start } }
      6 { $compose = if (Test-Command docker) { "docker compose" } else { $null }; if ($compose) { & $compose up -d } else { Write-Err "docker compose not available." } }
      7 { return }
      default { Write-Err "Invalid selection." }
    }
  } finally {
    Pop-Location
  }

  Write-Ok "Run step completed."
}

# ---- Main ----
try {
  Write-Info "Step 1/4: Project Workspace & Repository Cloning"
  Step-WorkspaceAndClone
  Write-Host ""

  Write-Info "Step 2/4: Core Dependencies (Docker, Make)"
  Step-CoreDependencies
  Write-Host ""

  Write-Info "Step 3/4: Toolchains per repository (Flutter/Java/Node/Python)"
  Step-ToolchainsPerRepo
  Write-Host ""

  Write-Info "Step 4/4: Choose and run a project"
  Step-SelectAndRun
  Write-Host ""

  Write-Ok "All done. Happy hacking! 🚀"
} catch {
  Write-Err ("Fatal error: " + $_.Exception.Message)
}
