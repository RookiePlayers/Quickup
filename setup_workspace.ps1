
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Prompt-YesNo {
  param(
    [Parameter(Mandatory=$true)][string]$Message,
    [bool]$Default=$true
  )
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

function Is-WSL {
  try {
    if (Test-Path -Path "/proc/version") {
      $txt = Get-Content "/proc/version" -ErrorAction SilentlyContinue
      return ($txt -match "microsoft")
    }
  } catch {}
  return $false
}

# --- PATH helpers (reload current session) ---
function Refresh-EnvPath {
  $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path','User')
  $global:env:Path = ($machine + ';' + $user).TrimEnd(';')
}

function Try-AddPath {
  param([string]$Dir)
  if (Test-Path $Dir) {
    $parts = $env:Path -split ';' | ForEach-Object { $_.Trim() }
    if (-not ($parts -contains $Dir)) {
      $global:env:Path += ';' + $Dir
    }
  }
}

# --- Package managers ---
function Ensure-Winget {
  if (Test-Command winget) { return $true }
  Write-Warn "winget not found."
  if (Prompt-YesNo -Message "Open Microsoft Store to install 'App Installer' (winget)?" -Default $true) {
    Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" | Out-Null
    Write-Info "After installing App Installer, reopen PowerShell and re-run this script if winget is still missing."
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

# --- Consent-first installers ---
function Maybe-Install-Git {
  if (Test-Command git) { Write-Ok "git found: $(git --version)"; return }
  if (-not (Prompt-YesNo -Message "Git not found. Install Git now?" -Default $true)) {
    Write-Err "Git is required to clone repos."; return
  }

  if (Ensure-Winget) {
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
  } elseif (Ensure-Choco) {
    choco install git -y
  } else {
    Write-Warn "No package manager available."
    if (Prompt-YesNo -Message "Open Git download page?" -Default $true) {
      Start-Process "https://git-scm.com/download/win" | Out-Null
    }
  }

  # Refresh PATH for this session and add typical Git dirs
  Refresh-EnvPath
  @(
    "C:\Program Files\Git\cmd",
    "C:\Program Files\Git\bin",
    "C:\Program Files (x86)\Git\cmd",
    "C:\Program Files\Git\usr\bin"
  ) | ForEach-Object { Try-AddPath $_ }

  if (Test-Command git) { Write-Ok "git installed: $(git --version)" }
  else { Write-Err "git still missing after attempted install. Open a NEW PowerShell window and try again." }
}

function Maybe-Install-DockerDesktop {
  if (Test-Command docker) {
    Write-Ok "docker found: $(docker --version)"
  } else {
    if (-not (Prompt-YesNo -Message "Docker Desktop not found. Install Docker Desktop now?" -Default $true)) {
      Write-Warn "Docker not installed. Docker-based run options may fail."
      return
    }
    if (Ensure-Winget) {
      winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
      Start-Sleep -Seconds 2
      Start-Process "Docker Desktop" -ErrorAction SilentlyContinue | Out-Null
    } elseif (Ensure-Choco) {
      choco install docker-desktop -y
      Start-Process "Docker Desktop" -ErrorAction SilentlyContinue | Out-Null
    } else {
      Write-Warn "No package manager available."
      if (Prompt-YesNo -Message "Open Docker Desktop download page?" -Default $true) {
        Start-Process "https://www.docker.com/products/docker-desktop/" | Out-Null
      }
    }
  }

  if (Test-Command docker) {
    Write-Info "Checking Docker daemon… (this can take a little while after first launch)"
    $ok = $false
    1..20 | ForEach-Object {
      if (docker info *> $null) { $ok = $true; break }
      Start-Sleep -Seconds 2
    }
    if ($ok) { Write-Ok "Docker daemon reachable." } else { Write-Warn "Docker daemon not ready. Ensure Docker Desktop is running." }
  }
}

function Maybe-Install-NodeLTS {
  if (Test-Command node) { Write-Ok "node found: $(node -v)"; return }
  if (-not (Prompt-YesNo -Message "Node.js LTS not found. Install Node LTS now?" -Default $true)) {
    Write-Warn "Node not installed. Yarn/PNPM/npm run options may fail."
    return
  }
  if (Ensure-Winget) {
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
  } elseif (Ensure-Choco) {
    choco install nodejs-lts -y
  } else {
    Write-Warn "No package manager available."
    if (Prompt-YesNo -Message "Open Node.js download page?" -Default $true) {
      Start-Process "https://nodejs.org/" | Out-Null
    }
  }
  # Refresh PATH in case Node just installed
  Refresh-EnvPath
  if (Test-Command node) { Write-Ok "Node ready: $(node -v)" } else { Write-Err "Node still missing after attempted install." }
}

function Maybe-Enable-Corepack {
  if (-not (Test-Command node)) { return }
  if (Prompt-YesNo -Message "Enable Corepack (Yarn/PNPM shims)?" -Default $true) {
    try { corepack enable *> $null } catch {}
  }
}

function Maybe-Ensure-Yarn {
  if (-not (Test-Command node)) { Maybe-Install-NodeLTS }
  if (-not (Test-Command node)) { return }
  Maybe-Enable-Corepack
  if (Test-Command yarn) { Write-Ok "Yarn ready: $(yarn -v)"; return }
  if (Prompt-YesNo -Message "Yarn not found. Activate Yarn via Corepack?" -Default $true) {
    try { corepack prepare yarn@stable --activate } catch {}
  }
  Refresh-EnvPath
  if (Test-Command yarn) { Write-Ok "Yarn ready: $(yarn -v)" } else { Write-Warn "Yarn still unavailable." }
}

function Maybe-Ensure-Pnpm {
  if (-not (Test-Command node)) { Maybe-Install-NodeLTS }
  if (-not (Test-Command node)) { return }
  Maybe-Enable-Corepack
  if (Test-Command pnpm) { Write-Ok "PNPM ready: $(pnpm -v)"; return }
  if (Prompt-YesNo -Message "PNPM not found. Activate PNPM via Corepack?" -Default $true) {
    try { corepack prepare pnpm@latest --activate } catch {}
  }
  Refresh-EnvPath
  if (Test-Command pnpm) { Write-Ok "PNPM ready: $(pnpm -v)" } else { Write-Warn "PNPM still unavailable." }
}

function Maybe-Install-Make {
  if (Test-Command make) { Write-Ok "make found: $(make --version | Select-Object -First 1)"; return }
  if (-not (Prompt-YesNo -Message "Make not found. Attempt to install it now?" -Default $false)) {
    Write-Warn "Skipping make install. You can still use Docker/Yarn/npm/PNPM run options."
    return
  }

  if (Ensure-Choco) {
    choco install make -y
  } elseif (Ensure-Winget) {
    Write-Warn "winget does not have a great 'make' package. Consider MSYS2."
    if (Prompt-YesNo -Message "Install MSYS2 to get make (you'll run pacman inside MSYS2)?" -Default $false) {
      winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements
      Write-Info "Open MSYS2 shell and run: pacman -S --needed base-devel make"
    }
  } else {
    Write-Warn "No package manager available. You can install MSYS2 or use Chocolatey later."
  }

  Refresh-EnvPath
  if (Test-Command make) { Write-Ok "make installed." } else { Write-Warn "make still not detected; continuing." }
}

# ---- Detection helpers for Run step ----
function Has-MakeUp {
  if (Test-Path -Path "Makefile") {
    $content = Get-Content "Makefile" -ErrorAction SilentlyContinue
    return ($content -match '^\s*up:')
  }
  return $false
}

function Get-ComposeFile {
  foreach ($f in @("docker-compose.yml","docker-compose.yaml","compose.yml","compose.yaml")) {
    if (Test-Path $f) { return $f }
  }
  return $null
}

function Has-PackageJsonStart {
  if (Test-Path "package.json") {
    try {
      $json = Get-Content "package.json" -Raw | ConvertFrom-Json -ErrorAction Stop
      return [bool]($json.scripts.start)
    } catch {
      return $false
    }
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

function Human-RunLabel {
  param([string]$opt)
  switch ($opt) {
    "make"   { "Make (make up)" }
    "compose"{ "Docker Compose (up -d)" }
    "yarn"   { "Yarn (yarn start)" }
    "pnpm"   { "PNPM (pnpm start)" }
    "npm"    { "npm (npm run start)" }
    default  { "Unknown" }
  }
}

# ---- Step 1: Workspace & clone ----
function Step-WorkspaceAndClone {
  $workspace = Read-Host "Enter a workspace name"
  if ([string]::IsNullOrWhiteSpace($workspace)) { throw "Workspace name cannot be empty." }

  New-Item -ItemType Directory -Force -Path $workspace | Out-Null
  Set-Location $workspace

  $count = Read-Host "How many repos would you like to clone? (e.g. 2)"
  if (-not ($count -as [int]) -or [int]$count -lt 1) { throw "Please enter a valid positive integer." }
  $count = [int]$count

  $script:Cloned = @()
  for ($i=1; $i -le $count; $i++) {
    Write-Host ""
    $repo = Read-Host "[$i/$count] Repo URL (HTTPS or SSH)"
    if ([string]::IsNullOrWhiteSpace($repo)) { throw "Repo URL cannot be empty." }
    $folder = Read-Host "Optional folder name (Enter for default)"

    if ([string]::IsNullOrWhiteSpace($folder)) {
      git clone $repo
      $name = [IO.Path]::GetFileNameWithoutExtension($repo.TrimEnd('/'))
      if ($name.EndsWith(".git")) { $name = $name.Substring(0, $name.Length-4) }
      $script:Cloned += $name
      Write-Ok "Cloned into .\$name"
    } else {
      git clone $repo $folder
      $script:Cloned += $folder
      Write-Ok "Cloned into .\$folder"
    }
  }
}

# ---- Step 2: Dependencies (consent-first) ----
function Step-Dependencies {
  if (Is-WSL) {
    Write-Info "Detected WSL. Docker usually comes from Docker Desktop for Windows with 'WSL 2 integration' enabled."
  }

  Maybe-Install-Git
  Maybe-Install-DockerDesktop
  Maybe-Install-NodeLTS
  Maybe-Install-Make
}

# ---- Run helpers ----
function Get-ComposeCmd {
  if (Test-Command docker) { return "docker compose" }
  return $null
}

# ---- Step 3: Run (auto-detect + manual override; consent for PM setup) ----
function Step-SelectAndRun {
  if (-not $script:Cloned -or $script:Cloned.Count -eq 0) {
    Write-Warn "No tracked clones. Scanning for git repos in current directory…"
    $dirs = Get-ChildItem . -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") } | Select-Object -ExpandProperty Name
    if (-not $dirs -or $dirs.Count -eq 0) { throw "No repos found." }
    $script:Cloned = $dirs
  }

  Write-Host ""
  Write-Info "Select a project directory:"
  for ($i=0; $i -lt $script:Cloned.Count; $i++) {
    Write-Host "[$($i+1)] $($script:Cloned[$i])"
  }
  $choice = Read-Host "Enter a number"
  if (-not ($choice -as [int]) -or [int]$choice -lt 1 -or [int]$choice -gt $script:Cloned.Count) { throw "Invalid selection." }
  $project = $script:Cloned[[int]$choice-1]

  Push-Location $project
  try {
    $detected = Detect-RunOption
    $label = Human-RunLabel $detected
    Write-Host ""
    Write-Info "Run options for $(Get-Location):"
    $menu = @("Auto (recommended: $label)", "Make (make up)", "Yarn (yarn start)", "npm (npm run start)", "PNPM (pnpm start)", "Docker Compose (up -d)", "Quit")
    for ($i=0; $i -lt $menu.Count; $i++) { Write-Host "[$($i+1)] $($menu[$i])" }
    $sel = Read-Host "Choose an option [default 1]"
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = 1 } else { $sel = [int]$sel }

    switch ($sel) {
      1 {
        switch ($detected) {
          "make" {
            if (Test-Command make) { Write-Info "Auto: make up…"; & make up }
            else { Write-Warn "make not found; pick another run option."; break }
          }
          "compose" {
            $compose = Get-ComposeCmd
            if ($compose) { Write-Info "Auto: $compose up -d…"; & $compose up -d }
            else { Write-Warn "docker/compose not available."; break }
          }
          "yarn" {
            Maybe-Ensure-Yarn
            if (Test-Command yarn) {
              Write-Info "Installing deps with yarn…"
              if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }
              Write-Info "Starting with yarn start…"
              yarn start
            }
          }
          "pnpm" {
            Maybe-Ensure-Pnpm
            if (Test-Command pnpm) {
              Write-Info "Installing deps with pnpm…"
              pnpm install
              Write-Info "Starting with pnpm start…"
              pnpm start
            }
          }
          "npm" {
            Maybe-Install-NodeLTS
            if (Test-Command npm) {
              Write-Info "Installing deps with npm…"
              if (Test-Path "package-lock.json") { npm ci } else { npm install }
              Write-Info "Starting with npm run start…"
              npm run start
            }
          }
          default {
            Write-Warn "No run method detected. Pick a manual option."
          }
        }
      }
      2 {
        if (Test-Command make) { Write-Info "Running: make up…"; & make up }
        else { Write-Err "make is not installed. Choose another option or install make." }
      }
      3 {
        Maybe-Ensure-Yarn
        if (Test-Command yarn) {
          Write-Info "Installing deps with yarn…"
          if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }
          Write-Info "Starting with yarn start…"
          yarn start
        }
      }
      4 {
        Maybe-Install-NodeLTS
        if (Test-Command npm) {
          Write-Info "Installing deps with npm…"
          if (Test-Path "package-lock.json") { npm ci } else { npm install }
          Write-Info "Starting with npm run start…"
          npm run start
        }
      }
      5 {
        Maybe-Ensure-Pnpm
        if (Test-Command pnpm) {
          Write-Info "Installing deps with pnpm…"
          pnpm install
          Write-Info "Starting with pnpm start…"
          pnpm start
        }
      }
      6 {
        $compose = Get-ComposeCmd
        if ($compose) { Write-Info "Running: $compose up -d…"; & $compose up -d }
        else { Write-Err "docker compose not available. Ensure Docker Desktop is installed & running." }
      }
      7 { return }
      default { Write-Err "Invalid selection." }
    }
  } finally {
    Pop-Location
  }

  Write-Ok "Run step completed."
}

# ---- Main ----
Write-Info "Step 1/3: Project Workspace & Repository Cloning"
Maybe-Install-Git
Step-WorkspaceAndClone
Write-Host ""

Write-Info "Step 2/3: Dependencies Check (consent-first installers)"
Step-Dependencies
Write-Host ""

Write-Info "Step 3/3: Run (Auto-detect with manual override)"
Step-SelectAndRun

Write-Ok "All done. Happy hacking! 🚀"
