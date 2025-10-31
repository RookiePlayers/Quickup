#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok   { param([string]$m) Write-Host "[DONE] $m" -ForegroundColor Green }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param([string]$m) Write-Host "[ERR ] $m" -ForegroundColor Red }

function Test-Command { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# ---- OS / Env detection ----
function Is-WSL {
  try {
    if (Test-Path -Path "/proc/version") {
      $txt = Get-Content "/proc/version" -ErrorAction SilentlyContinue
      return ($txt -match "microsoft")
    }
  } catch {}
  return $false
}

# ---- Install helpers (best-effort via winget) ----
function Ensure-Git {
  if (Test-Command git) { Write-Ok "git found: $(git --version)"; return }
  Write-Warn "git not found; attempting install via winget…"
  if (Test-Command winget) {
    winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
  } else {
    Write-Err "winget not available. Install Git from https://git-scm.com/download/win"
  }
  if (Test-Command git) { Write-Ok "git installed." } else { Write-Err "git still missing." }
}

function Ensure-DockerDesktop {
  if (Test-Command docker) {
    Write-Ok "docker found: $(docker --version)"
  } else {
    Write-Warn "docker not found; attempting Docker Desktop install via winget…"
    if (Test-Command winget) {
      winget install --id Docker.DockerDesktop -e --accept-source-agreements --accept-package-agreements
      Start-Process "Docker Desktop" -ErrorAction SilentlyContinue | Out-Null
    } else {
      Write-Err "winget not available. Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
    }
  }

  if (Test-Command docker) {
    Write-Info "Checking Docker daemon (this can take ~seconds after first launch)…"
    $ok = $false
    1..15 | ForEach-Object {
      if (docker info *> $null) { $ok = $true; break }
      Start-Sleep -Seconds 2
    }
    if ($ok) { Write-Ok "Docker daemon reachable." } else { Write-Warn "Docker daemon not ready. Ensure Docker Desktop is running." }
  }
}

function Ensure-NodeLTS {
  if (Test-Command node) { Write-Ok "node found: $(node -v)"; return }
  Write-Warn "Node.js not found; installing Node LTS via winget…"
  if (Test-Command winget) {
    winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements
  } else {
    Write-Err "winget not available. Install Node LTS from https://nodejs.org/"
  }
  if (Test-Command node) { Write-Ok "Node ready: $(node -v)" } else { Write-Err "Node still missing." }
}

function Enable-Corepack {
  if (Test-Command node) {
    try { & node -e "require('child_process').spawnSync('corepack',['enable'],{stdio:'inherit'})" } catch {}
    try { corepack enable *> $null } catch {}
  }
}

function Ensure-Yarn {
  Ensure-NodeLTS
  Enable-Corepack
  if (-not (Test-Command yarn)) {
    Write-Info "Activating Yarn via Corepack…"
    try { corepack prepare yarn@stable --activate } catch {}
  }
  if (Test-Command yarn) { Write-Ok "Yarn ready: $(yarn -v)" } else { Write-Warn "Yarn unavailable." }
}

function Ensure-Pnpm {
  Ensure-NodeLTS
  Enable-Corepack
  if (-not (Test-Command pnpm)) {
    Write-Info "Activating PNPM via Corepack…"
    try { corepack prepare pnpm@latest --activate } catch {}
  }
  if (Test-Command pnpm) { Write-Ok "PNPM ready: $(pnpm -v)" } else { Write-Warn "PNPM unavailable." }
}

function Ensure-Npm {
  Ensure-NodeLTS
  if (Test-Command npm) { Write-Ok "npm ready: $(npm -v)" } else { Write-Warn "npm unavailable." }
}

function Get-ComposeCmd {
  if (Test-Command docker) {
    # docker compose is the v2 subcommand
    return "docker compose"
  }
  return $null
}

# ---- Detection helpers ----
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
    $json = Get-Content "package.json" -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    return [bool]($json.scripts.start)
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

# ---- Step 2: Dependencies ----
function Step-Dependencies {
  if (Is-WSL) {
    Write-Info "Detected WSL. Docker usually comes from Docker Desktop for Windows with 'WSL 2 integration' enabled."
  }
  Ensure-Git
  Ensure-DockerDesktop
  # 'make' is uncommon on Windows; if someone needs it, they can install via MSYS2/Chocolatey.
  if (Test-Command make) {
    Write-Ok "make found: $(make --version | Select-Object -First 1)"
  } else {
    Write-Warn "make not found. If your repo relies on Make, install via MSYS2/Chocolatey or use another run option."
  }
}

# ---- Step 3: Run (auto-detect + manual override) ----
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
            else { Write-Warn "make not found; falling back to manual choices."; break }
          }
          "compose" {
            $compose = Get-ComposeCmd
            if ($compose) { Write-Info "Auto: $compose up -d…"; & $compose up -d }
            else { Write-Warn "docker/compose not available."; break }
          }
          "yarn" {
            Ensure-Yarn
            Write-Info "Installing deps with yarn…"
            if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }
            Write-Info "Starting with yarn start…"
            yarn start
          }
          "pnpm" {
            Ensure-Pnpm
            Write-Info "Installing deps with pnpm…"
            pnpm install
            Write-Info "Starting with pnpm start…"
            pnpm start
          }
          "npm" {
            Ensure-Npm
            Write-Info "Installing deps with npm…"
            if (Test-Path "package-lock.json") { npm ci } else { npm install }
            Write-Info "Starting with npm run start…"
            npm run start
          }
          default {
            Write-Warn "No run method detected. Pick a manual option."
          }
        }
      }
      2 {
        if (Test-Command make) { Write-Info "Running: make up…"; & make up }
        else { Write-Err "make is not installed on Windows by default. Install via MSYS2/Chocolatey." }
      }
      3 {
        Ensure-Yarn
        Write-Info "Installing deps with yarn…"
        if (Test-Path "yarn.lock") { yarn install --frozen-lockfile } else { yarn install }
        Write-Info "Starting with yarn start…"
        yarn start
      }
      4 {
        Ensure-Npm
        Write-Info "Installing deps with npm…"
        if (Test-Path "package-lock.json") { npm ci } else { npm install }
        Write-Info "Starting with npm run start…"
        npm run start
      }
      5 {
        Ensure-Pnpm
        Write-Info "Installing deps with pnpm…"
        pnpm install
        Write-Info "Starting with pnpm start…"
        pnpm start
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
Step-WorkspaceAndClone
Write-Host ""

Write-Info "Step 2/3: Dependencies Check (Docker, Git, Make)"
Step-Dependencies
Write-Host ""

Write-Info "Step 3/3: Run (Auto-detect with manual override)"
Step-SelectAndRun

Write-Ok "All done. Happy hacking! 🚀"