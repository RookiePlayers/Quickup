#!/usr/bin/env bash
set -euo pipefail

# =============== Pretty logs ===============
info() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
error(){ printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }
ok()   { printf "\033[1;32m[DONE]\033[0m %s\n" "$*"; }

# =============== Globals ===============
CLONED_DIRS=()
NEEDS_SHELL_RESTART=0

# =============== OS detection ===============
detect_os() {
  local os="unknown"
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then os="linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then os="mac"
  elif grep -qi microsoft /proc/version 2>/dev/null; then os="wsl"
  fi
  echo "$os"
}

# =============== Command checks ===============
have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_git() {
  if have_cmd git; then ok "git found: $(git --version)"; return; fi
  local os="$1"
  warn "git not found; installing…"
  case "$os" in
    mac)
      if have_cmd brew; then brew install git
      else
        warn "Homebrew not installed. Installing Xcode Command Line Tools (provides git)…"
        xcode-select --install || true
        warn "If the GUI prompt didn't appear, install Homebrew or Git manually."
      fi
      ;;
    linux|wsl)
      if have_cmd apt-get; then sudo apt-get update && sudo apt-get install -y git
      elif have_cmd dnf; then sudo dnf install -y git
      elif have_cmd yum; then sudo yum install -y git
      else error "Unsupported package manager. Please install git manually."; exit 1; fi
      ;;
    *)
      error "Unrecognized OS; install git manually."; exit 1;;
  esac
  ok "git installed."
}

ensure_make() {
  if have_cmd make; then ok "make found: $(make --version | head -n1)"; return; fi
  local os="$1"
  warn "make not found; installing…"
  case "$os" in
    mac)
      if have_cmd brew; then brew install make; else xcode-select --install || true; fi
      ;;
    linux|wsl)
      if have_cmd apt-get; then sudo apt-get update && sudo apt-get install -y make
      elif have_cmd dnf; then sudo dnf install -y make
      elif have_cmd yum; then sudo yum install -y make
      else error "Unsupported package manager; install make manually."; exit 1; fi
      ;;
    *)
      error "Unrecognized OS; install make manually."; exit 1;;
  esac
  ok "make installed."
}

ensure_docker() {
  if have_cmd docker; then ok "docker found: $(docker --version)"; else
    local os="$1"
    warn "docker not found; attempting a friendly install…"
    case "$os" in
      mac)
        if have_cmd brew; then
          brew install --cask docker
          info "Launching Docker.app…"; open -a Docker || true
        else warn "Install Docker Desktop from docker.com."; fi
        ;;
      linux)
        if have_cmd apt-get; then
          sudo apt-get update
          sudo apt-get install -y docker.io docker-compose-plugin
          sudo systemctl enable --now docker
          if getent group docker >/dev/null 2>&1; then
            sudo usermod -aG docker "$USER" || true
            NEEDS_SHELL_RESTART=1
          fi
        elif have_cmd dnf; then
          sudo dnf install -y docker docker-compose-plugin
          sudo systemctl enable --now docker
          sudo usermod -aG docker "$USER" || true
          NEEDS_SHELL_RESTART=1
        else error "Unsupported package manager. Install Docker manually."; exit 1
        fi
        ;;
      wsl)
        warn "WSL detected. Best experience is Docker Desktop for Windows with WSL 2 engine."
        ;;
      *) error "Unrecognized OS; install Docker manually."; exit 1;;
    esac
  fi

  if have_cmd docker; then
    info "Checking Docker daemon..."
    if ! docker info >/dev/null 2>&1; then
      warn "Docker daemon not ready. Open Docker Desktop or start the service, then rerun."
    else ok "Docker daemon reachable."; fi
  fi
}

# =============== Node & Package Managers (on-demand) ===============
ensure_nvm() {
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    . "$HOME/.nvm/nvm.sh"; return
  fi
  warn "NVM not found; installing NVM…"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  . "$HOME/.nvm/nvm.sh"
}

ensure_node_lts() {
  if have_cmd node; then ok "node found: $(node -v)"; else
    ensure_nvm
    info "Installing latest LTS Node via NVM…"
    nvm install --lts
  fi
  if ! have_cmd node; then
    . "$HOME/.nvm/nvm.sh"
    nvm use --lts
  fi
  ok "Node ready: $(node -v)"
}

enable_corepack() { if have_cmd node; then corepack enable >/dev/null 2>&1 || true; fi; }

ensure_yarn_ready() {
  ensure_node_lts; enable_corepack
  if ! have_cmd yarn; then info "Activating Yarn via Corepack…"; corepack prepare yarn@stable --activate; fi
  ok "Yarn ready: $(yarn -v)"
}

ensure_pnpm_ready() {
  ensure_node_lts; enable_corepack
  if ! have_cmd pnpm; then info "Activating PNPM via Corepack…"; corepack prepare pnpm@latest --activate; fi
  ok "PNPM ready: $(pnpm -v)"
}

ensure_npm_ready() { ensure_node_lts; ok "npm ready: $(npm -v)"; }

ensure_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then echo "docker compose"
  elif have_cmd docker-compose; then echo "docker-compose"
  else error "Docker Compose not found. Install Docker Desktop or the compose plugin."; return 1
  fi
}

# =============== Detection helpers ===============
has_make_up() { [[ -f Makefile ]] && grep -Eq '^[[:space:]]*up:' Makefile; }

compose_file() {
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

has_pkg_json_start() { [[ -f package.json ]] && grep -q '"start"' package.json; }

preferred_pkg_manager() {
  if [[ -f yarn.lock ]]; then echo "yarn"
  elif [[ -f pnpm-lock.yaml ]]; then echo "pnpm"
  elif [[ -f package-lock.json ]] || [[ -f package.json ]]; then echo "npm"
  else echo ""
  fi
}

detect_run_option() {
  if has_make_up; then
    echo "make"
    return
  fi
  if compose_file >/dev/null; then
    echo "compose"
    return
  fi
  if has_pkg_json_start; then
    echo "$(preferred_pkg_manager)"
    return
  fi
  echo ""
}

human_run_label() {
  case "$1" in
    make) echo "Make (make up)";;
    compose) echo "Docker Compose (up -d)";;
    yarn) echo "Yarn (yarn start)";;
    pnpm) echo "PNPM (pnpm start)";;
    npm) echo "npm (npm run start)";;
    *) echo "Unknown";;
  esac
}

# =============== Step 1: Workspace & cloning ===============
step_workspace_and_clone() {
  read -rp "Enter a workspace name: " WORKSPACE
  [[ -z "${WORKSPACE// }" ]] && { error "Workspace name cannot be empty."; exit 1; }

  mkdir -p "$WORKSPACE"
  cd "$WORKSPACE"

  info "How many repos would you like to clone?"
  read -rp "Enter a number (e.g. 2): " REPO_COUNT
  if ! [[ "$REPO_COUNT" =~ ^[0-9]+$ ]] || [[ "$REPO_COUNT" -lt 1 ]]; then
    error "Please enter a valid positive integer."; exit 1
  fi

  for ((i=1; i<=REPO_COUNT; i++)); do
    echo
    read -rp "[$i/$REPO_COUNT] Repo URL (HTTPS or SSH): " REPO_URL
    [[ -z "${REPO_URL// }" ]] && { error "Repo URL cannot be empty."; exit 1; }

    read -rp "Optional folder name (leave empty for default): " FOLDER
    if [[ -z "${FOLDER// }" ]]; then
      git clone "$REPO_URL"
      DIRNAME=$(basename "${REPO_URL%.git}")
    else
      git clone "$REPO_URL" "$FOLDER"
      DIRNAME="$FOLDER"
    fi

    CLONED_DIRS+=("$DIRNAME")
    ok "Cloned into ./$DIRNAME"
  done
}

# =============== Step 2: Dependencies ===============
step_dependencies() {
  local os; os=$(detect_os)
  info "Detected OS: $os"

  ensure_git "$os"
  ensure_make "$os"
  ensure_docker "$os"

  if [[ "$NEEDS_SHELL_RESTART" -eq 1 ]]; then
    warn "You were added to the 'docker' group. Run 'newgrp docker' or log out/in for it to take effect."
  fi
}

# =============== Step 3: Run (auto-detect + manual override) ===============
select_and_run_project() {
  if [[ "${#CLONED_DIRS[@]}" -eq 0 ]]; then
    warn "No cloned directories tracked. Scanning for git repos…"
    mapfile -t CLONED_DIRS < <(find . -maxdepth 1 -type d ! -path . -exec test -d "{}/.git" \; -print | sed 's|^\./||')
    [[ "${#CLONED_DIRS[@]}" -eq 0 ]] && { error "No repos found."; exit 1; }
  fi

  echo
  info "Select a project directory:"
  select dir in "${CLONED_DIRS[@]}" "Quit"; do
    case "$REPLY" in
      ''|*[!0-9]*) echo "Enter a number from the list."; continue;;
      *)
        [[ "$dir" == "Quit" ]] && exit 0
        if [[ -n "$dir" && -d "$dir" ]]; then PROJECT_DIR="$dir"; break
        else echo "Invalid selection."; fi
        ;;
    esac
  done

  (
    cd "$PROJECT_DIR"

    DETECTED=$(detect_run_option)
    RECOMMENDED_LABEL=$(human_run_label "$DETECTED")

    echo
    info "Run options for $(pwd):"
    OPTIONS=("Auto (recommended: ${RECOMMENDED_LABEL})"              "Make (make up)"              "Yarn (yarn start)"              "npm (npm run start)"              "PNPM (pnpm start)"              "Docker Compose (up -d)"              "Quit")

    PS3="Choose an option [default 1]: "
    select choice in "${OPTIONS[@]}"; do
      [[ -z "$REPLY" ]] && choice="${OPTIONS[0]}"

      case "$choice" in
        "Auto (recommended:"*)
          case "$DETECTED" in
            make)
              info "Auto: make up…"; make up || error "'make up' failed."
              ;;
            compose)
              info "Auto: docker compose up -d…"
              ensure_docker "$(detect_os)"
              COMPOSE_CMD=$(ensure_compose_cmd) || exit 1
              $COMPOSE_CMD up -d || error "'$COMPOSE_CMD up -d' failed."
              ;;
            yarn)
              info "Auto: yarn start…"
              ensure_yarn_ready
              (yarn install --frozen-lockfile || yarn install)
              yarn start || error "'yarn start' failed."
              ;;
            pnpm)
              info "Auto: pnpm start…"
              ensure_pnpm_ready
              pnpm install
              pnpm start || error "'pnpm start' failed."
              ;;
            npm)
              info "Auto: npm run start…"
              ensure_npm_ready
              (test -f package-lock.json && npm ci || npm install)
              npm run start || error "'npm run start' failed."
              ;;
            "")
              warn "No run method detected. Pick one manually."
              continue
              ;;
          esac
          break
          ;;
        "Make (make up)")
          info "Running: make up…"
          make up || error "'make up' failed."
          break
          ;;
        "Yarn (yarn start)")
          ensure_yarn_ready
          (yarn install --frozen-lockfile || yarn install)
          yarn start || error "'yarn start' failed."
          break
          ;;
        "npm (npm run start)")
          ensure_npm_ready
          (test -f package-lock.json && npm ci || npm install)
          npm run start || error "'npm run start' failed."
          break
          ;;
        "PNPM (pnpm start)")
          ensure_pnpm_ready
          pnpm install
          pnpm start || error "'pnpm start' failed."
          break
          ;;
        "Docker Compose (up -d)")
          ensure_docker "$(detect_os)"
          COMPOSE_CMD=$(ensure_compose_cmd) || exit 1
          $COMPOSE_CMD up -d || error "'$COMPOSE_CMD up -d' failed."
          break
          ;;
        "Quit") exit 0 ;;
        *) echo "Pick a valid option (1-6).";;
      esac
    done
  )

  ok "Run step completed."
}

# =============== Main ===============
main() {
  info "Step 1/3: Project Workspace & Repository Cloning"
  step_workspace_and_clone
  echo

  info "Step 2/3: Dependencies Check (Docker, Make, Git)"
  step_dependencies
  echo

  info "Step 3/3: Run (Auto-detect with manual override)"
  select_and_run_project

  ok "All done. Happy hacking! 🚀"
}

main "$@"
