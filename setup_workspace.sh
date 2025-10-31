#!/usr/bin/env bash
set -euo pipefail

# ------------- UI helpers -------------
info(){ printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok(){ printf "\033[1;32m[DONE]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err(){ printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

confirm(){ # usage: if confirm "Message?" [default y|n]; default=n
  local msg="$1"
  local default="${2:-n}"  # default is "n"
  local ans ans_lc
  while true; do
    read -r -p "$msg [Y/n] (default: $default) " ans || true
    ans_lc="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    case "$ans_lc" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      "")
        if [ "$default" = "y" ]; then return 0; else return 1; fi ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# Retry helpers (max 5 attempts)
_prompt_attempts_default=5

trim(){ # usage: trim "  text  "
  printf '%s' "$1" | awk '{$1=$1;print}'
}

read_with_retries(){ # usage: read_with_retries "Prompt" varname "validator_func"
  local prompt="$1"; local __outvar="$2"; local validator="${3:-}"; local attempts="${4:-$_prompt_attempts_default}"
  local i=1 input okflag
  while [ "$i" -le "$attempts" ]; do
    read -r -p "$prompt " input || input=""
    input="$(trim "$input")"
    okflag=1
    if [ -n "$validator" ] && ! "$validator" "$input"; then okflag=0; fi
    if [ "$okflag" -eq 1 ]; then
      printf -v "$__outvar" '%s' "$input"
      return 0
    fi
    warn "Invalid input. Attempt $i/$attempts"
    i=$((i+1))
  done
  return 1
}

# Validators
validate_nonempty(){ [ -n "${1:-}" ]; }
validate_pos_int(){ case "$1" in ''|*[!0-9]* ) return 1;; * ) [ "$1" -ge 1 ];; esac }
validate_repo_url(){
  case "$1" in
    https://*|http://*|git@*:*/*.git|git@*:*/*) return 0;;
    *) return 1;;
  esac
}
validate_index_in_range(){ # usage: validate_index_in_range "idx" "max"
  local idx="$1" max="$2"
  case "$idx" in ''|*[!0-9]* ) return 1;; * ) [ "$idx" -ge 1 ] && [ "$idx" -le "$max" ];; esac
}
validate_node_version(){ case "$1" in ''|*[!0-9.]* ) return 1;; * ) return 0;; esac }
validate_java_version(){ case "$1" in 8|11|17|21|temurin-*|*-tem|[0-9][0-9]) return 0;; * ) return 1;; esac }

# ------------- OS detection -------------
OS="$(uname -s)"
is_macos(){ [ "$OS" = "Darwin" ]; }
is_linux(){ [ "$OS" = "Linux" ]; }

# ------------- PATH + profile helpers -------------
SHELL_RC="${HOME}/.$(basename "${SHELL:-bash}")rc"
ensure_line_in_file(){ local line="$1" file="$2"; [ -n "$file" ] || return 0; grep -Fqx "$line" "$file" 2>/dev/null || printf "%s\n" "$line" >> "$file"; }
ensure_path_export(){
  local dir="$1"
  [ -d "$dir" ] || return 0
  case ":$PATH:" in *":$dir:"*) : ;; 
  *)
    export PATH="$dir:$PATH"
    ensure_line_in_file "export PATH=\"$dir:\$PATH\"" "$SHELL_RC"
  ;;
  esac
}

ensure_env_var(){
  local key="$1" val="$2"
  if [ -z "${!key-}" ]; then
    export "${key}=$val"
    ensure_line_in_file "export $key=\"$val\"" "$SHELL_RC"
    ok "Set $key and persisted to $SHELL_RC"
  fi
}

# ------------- Generic deps -------------
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

install_pkg_macos(){
  local pkg="$1"
  if ! has_cmd brew; then
    warn "Homebrew not found."
    if confirm "Install Homebrew?"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      test -x /opt/homebrew/bin/brew && eval "$(/opt/homebrew/bin/brew shellenv)"
      test -x /usr/local/bin/brew && eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  if has_cmd brew; then
    brew list --cask "$pkg" >/dev/null 2>&1 || brew install --cask "$pkg" || brew install "$pkg" || true
  fi
}

install_pkg_linux(){
  local pkg="$1"
  if has_cmd apt-get; then sudo apt-get update -y && sudo apt-get install -y "$pkg" || true
  elif has_cmd dnf; then sudo dnf install -y "$pkg" || true
  elif has_cmd pacman; then sudo pacman -S --noconfirm "$pkg" || true
  else warn "No known package manager to install $pkg"; fi
}

# ------------- Tooling installers by ecosystem -------------

# Node via NVM
install_nvm(){
  if has_cmd nvm; then return 0; fi
  if ! confirm "Install NVM (Node Version Manager)?" "n"; then
    warn "NVM installation skipped."
    return 1
  fi
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
  export NVM_DIR="${HOME}/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  ensure_line_in_file 'export NVM_DIR="$HOME/.nvm"' "$SHELL_RC"
  ensure_line_in_file '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$SHELL_RC"
  ok "NVM installed"
}

install_node_version(){
  local ver="$1"
  export NVM_DIR="${HOME}/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  if ! has_cmd nvm; then warn "nvm not available in this shell (skipping Node install)"; return 0; fi
  nvm install "$ver"
  nvm alias default "$ver"
  ok "Node $ver installed and set as default"
}

# Python via system pip or pyenv optional
install_python_tools(){
  if ! has_cmd python3; then
    if is_macos; then install_pkg_macos python || true
    else install_pkg_linux python3 || true; fi
  fi
  if ! has_cmd pip3; then
    if is_macos; then install_pkg_macos pipx || true; fi
    if has_cmd python3; then python3 -m ensurepip --upgrade || true; fi
  fi
  if has_cmd pipx; then pipx ensurepath || true; fi
  ok "Python & pip checked."
}

# Java via SDKMAN! or package manager
install_sdkman(){
  if [ -d "$HOME/.sdkman" ]; then return 0; fi
  if confirm "Install SDKMAN! to manage JDKs?"; then
    curl -s "https://get.sdkman.io" | bash
    # shellcheck source=/dev/null
    . "$HOME/.sdkman/bin/sdkman-init.sh"
    ensure_line_in_file 'source "$HOME/.sdkman/bin/sdkman-init.sh"' "$SHELL_RC"
    ok "SDKMAN! installed"
  fi
}

install_java_version(){
  local ver="$1"
  if [ -d "$HOME/.sdkman" ]; then
    . "$HOME/.sdkman/bin/sdkman-init.sh"
    sdk install java "$ver" || sdk install java "temurin-$ver" || true
    ok "Attempted Java install for $ver"
  else
    warn "SDKMAN! not present; trying system package manager for OpenJDK $ver"
    if is_macos; then install_pkg_macos "openjdk@${ver%.*}" || true
    else install_pkg_linux "openjdk-$ver-jdk" || install_pkg_linux "openjdk-${ver}-jdk" || true; fi
  fi
  if is_macos && [ -x /usr/libexec/java_home ]; then
    ensure_env_var JAVA_HOME "$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
}

# Flutter & FVM
install_flutter(){
  if has_cmd flutter; then ok "Flutter already installed"; return 0; fi
  if confirm "Install Flutter SDK?"; then
    if is_macos; then
      install_pkg_macos flutter || true
      local brew_flutter_bin
      brew_flutter_bin="$(brew --prefix 2>/dev/null)/Caskroom/flutter/$(ls "$(brew --prefix 2>/dev/null)/Caskroom/flutter" 2>/dev/null | tail -1)/flutter/bin"
      [ -d "$brew_flutter_bin" ] && ensure_path_export "$brew_flutter_bin"
    else
      if has_cmd snap; then sudo snap install flutter --classic || true
      else
        git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
        ensure_path_export "$HOME/flutter/bin"
      fi
    fi
  fi
}

install_fvm(){
  if has_cmd fvm; then ok "FVM already installed"; return 0; fi
  if confirm "Install FVM (Flutter Version Manager)?"; then
    if has_cmd dart; then
      dart pub global activate fvm
      ensure_path_export "$HOME/.pub-cache/bin"
    elif has_cmd flutter; then
      flutter pub global activate fvm || dart pub global activate fvm
      ensure_path_export "$HOME/.pub-cache/bin"
    else
      warn "Flutter/Dart not found; installing Flutter first."
      install_flutter
      if has_cmd flutter; then flutter pub global activate fvm; ensure_path_export "$HOME/.pub-cache/bin"; fi
    fi
  fi
}

# ------------- Project type detection -------------
is_flutter_repo(){ [ -f "pubspec.yaml" ] && grep -q "^flutter:" pubspec.yaml; }
is_node_repo(){ [ -f "package.json" ]; }
is_python_repo(){ [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; }
is_java_repo(){ [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; }

read_package_json_field(){
  node -e 'console.log(JSON.parse(require("fs").readFileSync("package.json","utf8")).engines?.node||"")' 2>/dev/null || true
}

# ------------- Existing logic (workspace + clone + deps + run) -------------

has_make_up(){ [ -f Makefile ] && grep -qE '^\s*up:' Makefile; }
compose_file(){ for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do [ -f "$f" ] && { echo "$f"; return 0; }; done; return 1; }
has_pkg_json_start(){ [ -f package.json ] && grep -q '"start"\s*:' package.json; }

preferred_pkg_manager(){
  [ -f yarn.lock ] && { echo yarn; return; }
  [ -f pnpm-lock.yaml ] && { echo pnpm; return; }
  [ -f package-lock.json ] || [ -f package.json ] && { echo npm; return; }
  echo ""
}

detect_run_option(){
  if has_make_up; then echo "make"; return; fi
  if compose_file >/dev/null; then echo "compose"; return; fi
  if has_pkg_json_start; then echo "$(preferred_pkg_manager)"; return; fi
  echo ""
}

# Step 1: Workspace + clone
step_workspace_and_clone(){
  local WORKSPACE
  if ! read_with_retries "Enter a workspace name:" WORKSPACE validate_nonempty; then
    err "No valid workspace name provided after ${_prompt_attempts_default} attempts. Skipping workspace setup."
    return 1
  fi
  mkdir -p "$WORKSPACE"
  cd "$WORKSPACE"

  local COUNT
  if ! read_with_retries "How many repos would you like to clone?" COUNT validate_pos_int; then
    err "Invalid repo count after ${_prompt_attempts_default} attempts. Skipping clone step."
    return 1
  fi

  CLONED=()
  local i repo folder name
  for ((i=1;i<=COUNT;i++)); do
    echo
    if ! read_with_retries "[$i/$COUNT] Repo URL (HTTPS or SSH):" repo validate_repo_url; then
      warn "Skipping this repo (invalid URL after ${_prompt_attempts_default} attempts)."
      continue
    fi
    read_with_retries "Optional folder name (enter for default):" folder "" 1 || true
    if [ -z "${folder:-}" ]; then
      git clone "$repo" || { warn "Clone failed for $repo"; continue; }
      name="$(basename "${repo%/}")"; name="${name%.git}"
      CLONED+=("$name")
      ok "Cloned into ./$name"
    else
      git clone "$repo" "$folder" || { warn "Clone failed for $repo"; continue; }
      CLONED+=("$folder")
      ok "Cloned into ./$folder"
    fi
  done
}

# Step 2: Core dependencies
ensure_core_deps(){
  if ! has_cmd git; then
    warn "git not found."
    if confirm "Install git now?"; then
      if is_macos; then install_pkg_macos git; else install_pkg_linux git; fi
    fi
  fi
  if ! has_cmd docker; then
    warn "docker not found."
    if confirm "Install Docker now?"; then
      if is_macos; then install_pkg_macos docker; else install_pkg_linux docker.io || install_pkg_linux docker; fi
    fi
  fi
  if ! has_cmd make; then
    warn "make not found."
    if confirm "Install make now?"; then
      if is_macos; then install_pkg_macos make || brew install make || true; else install_pkg_linux make || install_pkg_linux build-essential; fi
    fi
  fi
  ok "Core dependencies checked."
}

# Step 2b: Ecosystem toolchain installers based on repo contents
ensure_toolchains_for_repo(){
  local dir="$1"
  info "Analyzing $dir for ecosystem tooling…"
  pushd "$dir" >/dev/null || return 0

  if is_flutter_repo; then
    info "Flutter project detected."
    if confirm "Install Flutter SDK?"; then install_flutter; fi
    if confirm "Install FVM (Flutter Version Manager)?"; then install_fvm; fi
    ensure_path_export "$HOME/.pub-cache/bin"
    ensure_env_var PUB_CACHE "$HOME/.pub-cache"
  fi

  if is_node_repo; then
    info "Node project detected."
    if install_nvm; then
      local desired=""
      if [ -f .nvmrc ]; then desired="$(tr -d ' 
' < .nvmrc)"; fi
      if [ -z "$desired" ]; then desired="$(read_package_json_field)"; fi
      if [ -z "$desired" ]; then
        read_with_retries "Enter Node version to install (e.g. 20):" desired validate_node_version || true
      fi
      [ -n "$desired" ] && install_node_version "$desired"
    else
      warn "Skipping Node setup (NVM not installed)."
    fi
  fi

  if is_python_repo; then
    info "Python project detected."
    install_python_tools
    if has_cmd python3 && confirm "Create a virtual environment (.venv) and install requirements?"; then
      python3 -m venv .venv || true
      . .venv/bin/activate || true
      if [ -f requirements.txt ]; then pip3 install -r requirements.txt || true; fi
      if [ -f pyproject.toml ]; then warn "Detected pyproject.toml – install tool (pip/poetry/pdm) manually as desired."; fi
    fi
  fi

  if is_java_repo; then
    info "Java project detected."
    install_sdkman
    local jv=""
    if [ -f .java-version ]; then jv="$(tr -d ' \r\n' < .java-version)"; fi
    if [ -z "$jv" ]; then
      read_with_retries "Enter Java version (8/11/17/21 or temurin-17):" jv validate_java_version || true
    fi
    [ -n "$jv" ] && install_java_version "$jv"
  fi

  popd >/dev/null || true
}

# Step 3: Run
human_label(){
  case "$1" in
    make) echo "Make (make up)";;
    compose) echo "Docker Compose (up -d)";;
    yarn) echo "Yarn (yarn start)";;
    pnpm) echo "PNPM (pnpm start)";;
    npm) echo "npm (npm run start)";;
    *) echo "Unknown";;
  esac
}

run_project(){
  local dir="$1"
  pushd "$dir" >/dev/null || return 0
  local detected; detected="$(detect_run_option)"
  local label; label="$(human_label "$detected")"
  echo
  info "Run options for $(pwd):"
  echo "  [1] Auto (recommended: $label)"
  echo "  [2] Make (make up)"
  echo "  [3] Yarn (yarn start)"
  echo "  [4] npm (npm run start)"
  echo "  [5] PNPM (pnpm start)"
  echo "  [6] Docker Compose (up -d)"
  echo "  [7] Quit"

  local sel
  read_with_retries "Choose an option [default 1]:" sel validate_pos_int || sel=1

  case "$sel" in
    1)
      case "$detected" in
        make) has_cmd make && make up || warn "make missing." ;;
        compose) has_cmd docker && docker compose up -d || warn "docker compose unavailable." ;;
        yarn) has_cmd yarn || (has_cmd corepack && corepack prepare yarn@stable --activate); yarn install || true; yarn start ;;
        pnpm) has_cmd pnpm || (has_cmd corepack && corepack prepare pnpm@latest --activate); pnpm install; pnpm start ;;
        npm) has_cmd npm && { [ -f package-lock.json ] && npm ci || npm install; npm run start; } || warn "npm missing." ;;
        *) warn "No run method detected." ;;
      esac
      ;;
    2) has_cmd make && make up || err "make not installed." ;;
    3) has_cmd yarn || (has_cmd corepack && corepack prepare yarn@stable --activate); yarn install || true; yarn start ;;
    4) has_cmd npm && { [ -f package-lock.json ] && npm ci || npm install; npm run start; } || err "npm missing." ;;
    5) has_cmd pnpm || (has_cmd corepack && corepack prepare pnpm@latest --activate); pnpm install; pnpm start ;;
    6) has_cmd docker && docker compose up -d || err "docker compose unavailable." ;;
    7) : ;;
    *) warn "Invalid selection." ;;
  esac
  popd >/dev/null || true
}

# ------------------ Main flow ------------------
info "Step 1/4: Project Workspace & Repository Cloning"
step_workspace_and_clone || warn "Workspace/clone step skipped due to input errors."
echo

info "Step 2/4: Core Dependencies (git, docker, make)"
ensure_core_deps
echo

info "Step 3/4: Ecosystem Toolchains (per repo)"
if [ "${#CLONED[@]-0}" -gt 0 ]; then
  for d in "${CLONED[@]}"; do
    ensure_toolchains_for_repo "$d"
  done
else
  warn "No cloned repositories to analyze."
fi
echo

info "Step 4/4: Run"
if [ "${#CLONED[@]-0}" -gt 0 ]; then
  echo "Select a project to run:"
  local_idx=1
  for d in "${CLONED[@]}"; do echo "  [$local_idx] $d"; local_idx=$((local_idx+1)); done
  choice=""
  if read_with_retries "Enter a number:" choice validate_pos_int; then
    if validate_index_in_range "$choice" "${#CLONED[@]}"; then
      run_project "${CLONED[$((choice-1))]}"
    else
      warn "Selection out of range."
    fi
  else
    warn "No valid selection provided."
  fi
else
  warn "Nothing to run."
fi

ok "All done. Happy hacking! 🚀"