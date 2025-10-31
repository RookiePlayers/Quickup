#!/usr/bin/env bash
# Quickup Bash Setup (enhanced: non-interactive, logging, dry-run, help, run-step gated)
set -euo pipefail

# ======================== Config & Flags ========================
QUICKUP_NONINTERACTIVE="${QUICKUP_NONINTERACTIVE:-0}"
QUICKUP_ASSUME_YES="${QUICKUP_ASSUME_YES:-0}"
QUICKUP_REPOS_RAW="${QUICKUP_REPOS:-}"
QUICKUP_WORKSPACE="${QUICKUP_WORKSPACE:-}"
QUICKUP_AUTO_RUN="${QUICKUP_AUTO_RUN:-0}"
QUICKUP_ENABLE_RUN="${QUICKUP_ENABLE_RUN:-0}"   # NEW: interactive run step enabled
QUICKUP_SKIP_TOOLCHAINS="${QUICKUP_SKIP_TOOLCHAINS:-0}"
QUICKUP_LOG_FILE="${QUICKUP_LOG_FILE:-quickup.log}"
QUICKUP_NO_LOG="${QUICKUP_NO_LOG:-0}"
QUICKUP_DRY_RUN="${QUICKUP_DRY_RUN:-0}"
QUICKUP_NODE_VERSION="${QUICKUP_NODE_VERSION:-}"
QUICKUP_JAVA_VERSION="${QUICKUP_JAVA_VERSION:-}"
QUICKUP_CONFIG_FILE="${QUICKUP_CONFIG_FILE:-}"
SHOW_HELP=0

# Parse CLI flags (override envs)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --non-interactive) QUICKUP_NONINTERACTIVE=1 ;;
    -y|--yes) QUICKUP_ASSUME_YES=1 ;;
    --dry-run) QUICKUP_DRY_RUN=1 ;;
    --no-log) QUICKUP_NO_LOG=1 ;;
    --workspace) shift; QUICKUP_WORKSPACE="${1:-}";;
    --repos) shift; QUICKUP_REPOS_RAW="${1:-}";;
    --auto-run) QUICKUP_AUTO_RUN=1 ;;     # automatic run (no menu)
    --run) QUICKUP_ENABLE_RUN=1 ;;        # enable interactive run menu
    --skip-toolchains) QUICKUP_SKIP_TOOLCHAINS=1 ;;
    --node) shift; QUICKUP_NODE_VERSION="${1:-}";;
    --java) shift; QUICKUP_JAVA_VERSION="${1:-}";;
    --config-file) shift; QUICKUP_CONFIG_FILE="${1:-}";;
    -c) shift; QUICKUP_CONFIG_FILE="${1:-}";;
    -h|--help) SHOW_HELP=1 ;;
    *) echo "Unknown flag: $1" >&2 ;;
  esac
  shift || true
done

# ======================== Config file loading ========================
# Support .env/.conf (KEY=VALUE), .json, and .yaml/.yml. Arrays remain arrays in config;
# we store them internally and also normalize known arrays (like QUICKUP_REPOS) into comma-separated strings.
load_env_config(){
  local file="$1"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" != *"="* ]] && continue
    # Strip leading/trailing whitespace
    local key="${line%%=*}"; local value="${line#*=}"
    key="$(printf '%s' "$key" | awk '{$1=$1;print}')"
    value="$(printf '%s' "$value" | sed -e 's/^ *//' -e 's/ *$//')"
    [[ -z "$key" ]] && continue
    [[ "$key" =~ ^# ]] && continue
    key="${key#export }"
    # Only set if not already in environment (CLI flags win)
    if [[ -z "${!key-}" ]]; then
      export "${key}=${value}"
    fi
  done < "$file"
}

# Flatten JSON/YAML into lines; arrays emit multiple __ARR__KEY=value lines.
# For JSON we use python3 (standard). For YAML we try yq -> JSON, else python3 with PyYAML, else error.
load_json_config(){
  local file="$1"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" == __ARR__* ]]; then
      local kv="${line#__ARR__}"
      local key="${kv%%=*}"
      local value="${kv#*=}"
      eval "ARR_${key}+=(\"$value\")"
    else
      local key="${line%%=*}"
      local value="${line#*=}"
      if [[ -z "${!key-}" ]]; then
        export "${key}=${value}"
      fi
    fi
  done < <(python3 - "$file" <<'PY'
import sys, json, os

def flatten(prefix, obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            key = f"{prefix}_{k}" if prefix else str(k)
            yield from flatten(key, v)
    elif isinstance(obj, list):
        for v in obj:
            print(f"__ARR__{prefix}={v}")
    else:
        print(f"{prefix}={obj}")

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
for line in flatten("", data):
    print(line)
PY
  )
}


load_yaml_config(){
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    local tmpjson
    tmpjson="$(mktemp)"
    yq -o=json '.' "$file" > "$tmpjson"
    load_json_config "$tmpjson"
    rm -f "$tmpjson"
  else
    while IFS= read -r line; do
      if [[ "$line" == "__ERROR__:NoYAML" ]]; then
        echo "[ERR ] YAML config requires either 'yq' or Python 'yaml' module." >&2
        break
      fi
      [[ -z "$line" ]] && continue
      if [[ "$line" == __ARR__* ]]; then
        local kv="${line#__ARR__}"
        local key="${kv%%=*}"
        local value="${kv#*=}"
        eval "ARR_${key}+=(\"$value\")"
      else
        local key="${line%%=*}"
        local value="${line#*=}"
        if [[ -z "${!key-}" ]]; then
          export "${key}=${value}"
        fi
      fi
    done < <(python3 - "$file" <<'PY'
import sys, os
try:
    import yaml
except Exception as e:
    print("__ERROR__:NoYAML", flush=True)
    sys.exit(0)

def flatten(prefix, obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            key = f"{prefix}_{k}" if prefix else str(k)
            yield from flatten(key, v)
    elif isinstance(obj, list):
        for v in obj:
            print(f"__ARR__{prefix}={v}")
    else:
        print(f"{prefix}={obj}")

path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f) or {}
for line in flatten("", data):
    print(line)
PY
    )
  fi
}


# Master loader
if [[ -n "${QUICKUP_CONFIG_FILE:-}" ]]; then
  if [[ ! -r "${QUICKUP_CONFIG_FILE}" ]]; then
    echo "[ERR ] Config file not readable: ${QUICKUP_CONFIG_FILE}" >&2
  else
    case "${QUICKUP_CONFIG_FILE}" in
      *.json) load_json_config "${QUICKUP_CONFIG_FILE}" ;;
      *.yaml|*.yml) load_yaml_config "${QUICKUP_CONFIG_FILE}" ;;
      *) load_env_config "${QUICKUP_CONFIG_FILE}" ;;
    esac
    # Known array normalization: QUICKUP_REPOS, QUICKUP_REPO_FOLDERS (if provided as arrays in config)
    if [[ "$(declare -p ARR_QUICKUP_REPOS 2>/dev/null)" =~ "declare -a" ]]; then
      # Export comma-joined fallback for existing logic
      IFS=',' read -r -a __tmp <<< "$(printf "%s," "${ARR_QUICKUP_REPOS[@]}")"
      QUICKUP_REPOS_RAW="$(IFS=,; echo "${ARR_QUICKUP_REPOS[*]}")"
      export QUICKUP_REPOS="$QUICKUP_REPOS_RAW"
    fi
    if [[ "$(declare -p ARR_QUICKUP_REPO_FOLDERS 2>/dev/null)" =~ "declare -a" ]]; then
      export QUICKUP_REPO_FOLDERS="$(IFS=,; echo "${ARR_QUICKUP_REPO_FOLDERS[*]}")"
    fi
  fi
  # Force non-interactive when using a config file
  QUICKUP_NONINTERACTIVE=1
  QUICKUP_ASSUME_YES=1
  echo "[INFO] Non-interactive mode forced via config file: ${QUICKUP_CONFIG_FILE}"
fi

# ======================== Logging (tee) ========================
if [[ "${QUICKUP_NO_LOG}" != "1" ]]; then
  # shellcheck disable=SC2069
  exec > >(tee -a "${QUICKUP_LOG_FILE}") 2>&1
fi

# ======================== UI helpers ========================
INFO="[INFO]"
DONE="[DONE]"
WARN="[WARN]"
ERR="[ERR ]"

log_info(){ printf "%s %s\n" "$INFO" "$*"; }
log_done(){ printf "%s %s\n" "$DONE" "$*"; }
log_warn(){ printf "%s %s\n" "$WARN" "$*"; }
log_err(){ printf "%s %s\n" "$ERR" "$*" >&2; }

# If a config file was loaded, force non-interactive mode (ignore config overrides)
if [[ -n "${QUICKUP_CONFIG_FILE}" ]]; then
  QUICKUP_NONINTERACTIVE=1
  QUICKUP_ASSUME_YES=1
  echo "[INFO] Non-interactive mode forced via config file: ${QUICKUP_CONFIG_FILE}"
fi



print_help(){
  cat <<'USAGE'
Quickup - one command to spin up a dev workspace

Usage:
  setup_workspace.sh [options]

Options:
  --non-interactive          Run without prompts (use env vars).
  -y, --yes                  Assume "yes" for all confirmations.
  --dry-run                  Print commands without executing them.
  --no-log                   Disable log writing.
  --workspace <name>         Workspace folder name.
  --repos "<url1,url2>"      Comma-separated repository URLs.
  --auto-run                 Auto-run detected start command after setup.
  --run                      Enable the Run step (interactive menu). Default: disabled.
  --skip-toolchains          Skip language/toolchain setup.
  --node <version>           Node.js version (with NVM).
  --java <version>           Java version (SDKMAN or system).
  -c, --config-file <path>   Load KEY=VALUE envs from file (does not override existing).
  -h, --help                 Show this help and exit.

Environment variables (same effect as flags):
  QUICKUP_NONINTERACTIVE=1   non-interactive mode
  QUICKUP_ASSUME_YES=1       assume yes
  QUICKUP_DRY_RUN=1          dry-run mode
  QUICKUP_NO_LOG=1           disable logging
  QUICKUP_WORKSPACE=...      workspace name
  QUICKUP_REPOS=...          repos list
  QUICKUP_AUTO_RUN=1         auto-run
  QUICKUP_ENABLE_RUN=1       enable Run step (interactive)
  QUICKUP_SKIP_TOOLCHAINS=1  skip toolchains
  QUICKUP_NODE_VERSION=...   node version
  QUICKUP_JAVA_VERSION=...   java version
  QUICKUP_CONFIG_FILE=path     path to config file to load
USAGE
}

# If help was requested via CLI parsing, print now and exit.
if [[ "$SHOW_HELP" == "1" ]]; then
  print_help
  exit 0
fi

# Dry-run wrapper
run_cmd(){
  if [[ "${QUICKUP_DRY_RUN}" == "1" ]]; then
    printf "%s [DRY] %s\n" "$INFO" "$*"
    return 0
  else
    eval "$@"
  fi
}

# ======================== Input helpers ========================
trim(){ printf '%s' "$1" | awk '{$1=$1;print}'; }

confirm(){ # confirm "Message?" [default y|n]; default=n
  local msg="$1"; local default="${2:-n}"
  if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
    if [[ "${QUICKUP_ASSUME_YES}" == "1" ]]; then return 0; fi
    [[ "$default" == "y" ]] && return 0 || return 1
  fi
  local ans ans_lc
  while true; do
    local prompt="[Y/n] (default: $default)"
    read -r -p "$msg $prompt " ans || true
    ans_lc="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
    case "$ans_lc" in
      y|yes) return 0;;
      n|no)  return 1;;
      "")    [[ "$default" == "y" ]] && return 0 || return 1 ;;
      *)     log_warn "Please answer y or n." ;;
    esac
  done
}

_prompt_attempts_default=5

# read_with_retries "Prompt" outvar validator attempts
read_with_retries(){
  local prompt="$1"; local __out="$2"; local validator="${3:-}"; local attempts="${4:-$_prompt_attempts_default}"
  local i=1 input okflag
  if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
    local cur="${!__out-}"
    if [[ -n "${cur:-}" ]]; then return 0; fi
    return 1
  fi
  while [[ "$i" -le "$attempts" ]]; do
    read -r -p "$prompt " input || input=""
    input="$(trim "$input")"
    okflag=1
    if [[ -n "$validator" ]] && ! "$validator" "$input"; then okflag=0; fi
    if [[ "$okflag" -eq 1 ]]; then
      printf -v "$__out" '%s' "$input"
      return 0
    fi
    log_warn "Invalid input. Attempt $i/$attempts"
    i=$((i+1))
  done
  return 1
}

# Validators
validate_nonempty(){ [[ -n "${1:-}" ]]; }
validate_pos_int(){ case "$1" in ''|*[!0-9]* ) return 1;; * ) [[ "$1" -ge 1 ]] ;; esac }
validate_repo_url(){ case "$1" in https://*|http://*|git@*:*/*.git|git@*:*/*) return 0;; *) return 1;; esac }
validate_index_in_range(){ local idx="$1" max="$2"; case "$idx" in ''|*[!0-9]* ) return 1;; * ) [[ "$idx" -ge 1 && "$idx" -le "$max" ]] ;; esac }
validate_node_version(){ case "$1" in ''|*[!0-9.]* ) return 1;; * ) return 0;; esac }
validate_java_version(){ case "$1" in 8|11|17|21|temurin-*|*-tem|[0-9][0-9]) return 0;; * ) return 1;; esac }

# ======================== OS detection & PATH ========================
OS="$(uname -s)"
is_macos(){ [[ "$OS" == "Darwin" ]]; }
is_linux(){ [[ "$OS" == "Linux" ]]; }

SHELL_RC="${HOME}/.$(basename "${SHELL:-bash}")rc"

ensure_line_in_file(){ local line="$1" file="$2"; [[ -z "$file" ]] && return 0; grep -Fqx "$line" "$file" 2>/dev/null || printf "%s\n" "$line" >> "$file"; }
ensure_path_export(){
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  case ":$PATH:" in *":$dir:"*) : ;; 
  *) export PATH="$dir:$PATH"; ensure_line_in_file "export PATH=\"$dir:\$PATH\"" "$SHELL_RC" ;;
  esac
}
ensure_env_var(){
  local key="$1" val="$2"
  if [[ -z "${!key-}" ]]; then
    export "${key}=$val"
    ensure_line_in_file "export $key=\"$val\"" "$SHELL_RC"
    log_done "Set $key and persisted to $SHELL_RC"
  fi
}

# ======================== Pkg managers & installers ========================
has_cmd(){ command -v "$1" >/dev/null 2>&1; }

detect_pkg_mgr(){
  if has_cmd brew; then echo brew
  elif has_cmd apt-get; then echo apt
  elif has_cmd dnf; then echo dnf
  elif has_cmd yum; then echo yum
  elif has_cmd pacman; then echo pacman
  else echo none
  fi
}

ensure_homebrew(){
  if has_cmd brew; then return 0; fi
  log_warn "Homebrew not found."
  if confirm "Install Homebrew?" "n"; then
    run_cmd '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    if has_cmd /opt/homebrew/bin/brew; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
    if has_cmd /usr/local/bin/brew; then eval "$(/usr/local/bin/brew shellenv)"; fi
  fi
}

install_pkg_macos(){
  local pkg="$1"
  ensure_homebrew
  if has_cmd brew; then
    run_cmd "brew list --cask '$pkg' >/dev/null 2>&1 || brew install --cask '$pkg' || brew install '$pkg' || true"
  fi
}
install_pkg_linux(){
  local pkg="$1" pm; pm="$(detect_pkg_mgr)"
  case "$pm" in
    apt) run_cmd "sudo apt-get update -y && sudo apt-get install -y '$pkg' || true" ;;
    dnf|yum) run_cmd "sudo $pm install -y '$pkg' || true" ;;
    pacman) run_cmd "sudo pacman -S --noconfirm '$pkg' || true" ;;
    *) log_warn "No known package manager to install $pkg" ;;
  esac
}

install_git(){
  if has_cmd git; then log_done "git found: $(git --version)"; return; fi
  if ! confirm "Git not found. Install it?" "y"; then log_warn "Skipping Git."; return; fi
  if is_macos; then install_pkg_macos git; else install_pkg_linux git; fi
}
install_docker(){
  if has_cmd docker; then log_done "docker found: $(docker --version)"; return; fi
  if ! confirm "Docker not found. Install it?" "n"; then log_warn "Skipping Docker."; return; fi
  if is_macos; then install_pkg_macos docker; else install_pkg_linux docker.io || install_pkg_linux docker ; fi
  run_cmd "sudo systemctl enable --now docker" || true
}
install_make(){
  if has_cmd make; then log_done "make found."; return; fi
  if ! confirm "Make not found. Install it?" "n"; then return; fi
  if is_macos; then install_pkg_macos make || run_cmd "brew install make || true"
  else install_pkg_linux make || install_pkg_linux build-essential ; fi
}

install_nvm(){
  if has_cmd nvm; then return 0; fi
  if ! confirm "Install NVM (Node Version Manager)?" "n"; then log_warn "NVM installation skipped."; return 1; fi
  run_cmd "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
  export NVM_DIR="${HOME}/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  ensure_line_in_file 'export NVM_DIR="$HOME/.nvm"' "$SHELL_RC"
  ensure_line_in_file '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' "$SHELL_RC"
  log_done "NVM installed"
}
install_node_version(){
  local ver="$1"
  export NVM_DIR="${HOME}/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  if ! has_cmd nvm; then log_warn "nvm not available in this shell (skipping Node install)"; return 0; fi
  run_cmd "nvm install '$ver'"
  run_cmd "nvm alias default '$ver'"
  log_done "Node $ver installed and set as default"
}
install_python_tools(){
  if ! has_cmd python3; then
    if is_macos; then install_pkg_macos python || true
    else install_pkg_linux python3 || true; fi
  fi
  if ! has_cmd pip3 && has_cmd python3; then run_cmd "python3 -m ensurepip --upgrade || true"; fi
  log_done "Python & pip checked."
}
install_sdkman(){
  if [[ -d "$HOME/.sdkman" ]]; then return 0; fi
  if confirm "Install SDKMAN! to manage JDKs?" "n"; then
    run_cmd "curl -s 'https://get.sdkman.io' | bash"
    [[ -s \"$HOME/.sdkman/bin/sdkman-init.sh\" ]] && . "$HOME/.sdkman/bin/sdkman-init.sh"
    ensure_line_in_file 'source "$HOME/.sdkman/bin/sdkman-init.sh"' "$SHELL_RC"
    log_done "SDKMAN! installed"
  fi
}
install_java_version(){
  local ver="$1"
  if [[ -d "$HOME/.sdkman" ]]; then
    . "$HOME/.sdkman/bin/sdkman-init.sh"
    run_cmd "sdk install java '$ver' || sdk install java 'temurin-$ver' || true"
    log_done "Attempted Java install for $ver"
  else
    log_warn "SDKMAN! not present; trying system package manager for OpenJDK $ver"
    if is_macos; then install_pkg_macos "openjdk@${ver%.*}" || true
    else install_pkg_linux "openjdk-$ver-jdk" || install_pkg_linux "openjdk-${ver}-jdk" || true; fi
  fi
  if is_macos && [[ -x /usr/libexec/java_home ]]; then
    ensure_env_var JAVA_HOME "$(/usr/libexec/java_home 2>/dev/null || true)"
  fi
}
install_flutter(){
  if has_cmd flutter; then log_done "Flutter already installed"; return 0; fi
  if confirm "Install Flutter SDK?" "n"; then
    if is_macos; then
      install_pkg_macos flutter || true
      local brew_flutter_bin
      brew_flutter_bin="$(brew --prefix 2>/dev/null)/Caskroom/flutter/$(ls "$(brew --prefix 2>/dev/null)/Caskroom/flutter" 2>/dev/null | tail -1)/flutter/bin"
      [[ -d "$brew_flutter_bin" ]] && ensure_path_export "$brew_flutter_bin"
    else
      if has_cmd snap; then run_cmd "sudo snap install flutter --classic || true"
      else
        run_cmd "git clone https://github.com/flutter/flutter.git -b stable '$HOME/flutter'"
        ensure_path_export "$HOME/flutter/bin"
      fi
    fi
  fi
}
install_fvm(){
  if has_cmd fvm; then log_done "FVM already installed"; return 0; fi
  if confirm "Install FVM (Flutter Version Manager)?" "n"; then
    if has_cmd dart; then
      run_cmd "dart pub global activate fvm"
      ensure_path_export "$HOME/.pub-cache/bin"
    elif has_cmd flutter; then
      run_cmd "flutter pub global activate fvm || dart pub global activate fvm"
      ensure_path_export "$HOME/.pub-cache/bin"
    else
      log_warn "Flutter/Dart not found; installing Flutter first."
      install_flutter
      if has_cmd flutter; then run_cmd "flutter pub global activate fvm"; ensure_path_export "$HOME/.pub-cache/bin"; fi
    fi
  fi
}

# ======================== Project detection ========================
is_flutter_repo(){ [[ -f "pubspec.yaml" ]] && grep -q "^flutter:" pubspec.yaml; }
is_node_repo(){ [[ -f "package.json" ]]; }
is_python_repo(){ [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "Pipfile" ]]; }
is_java_repo(){ [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; }

read_package_json_field(){
  node -e 'console.log(JSON.parse(require("fs").readFileSync("package.json","utf8")).engines?.node||"")' 2>/dev/null || true
}

# ======================== Clone logic ========================
normalize_url(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/\.git$//; s:/*$::'; }

git_clone_safe(){
  local repo="$1" folder="${2:-}" target choice i=1
  if [[ -z "$folder" ]]; then target="$(basename "${repo%/}")"; target="${target%.git}"; else target="$folder"; fi

  log_info "Target folder: $target"

  if [[ -d "$target" ]]; then
    if [[ -d "$target/.git" ]]; then
      local existing_url; existing_url="$(git -C "$target" config --get remote.origin.url 2>/dev/null || true)"
      if [[ -n "$existing_url" ]] && [[ "$(normalize_url "$existing_url")" == "$(normalize_url "$repo")" ]]; then
        log_warn "Repo already cloned at '$target' (same remote). Skipping."
        return 1
      fi
    fi
    log_warn "Destination '$target' already exists."
    if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
      target="${target}_$((RANDOM % 900 + 100))"
      log_info "Non-interactive mode: using new folder name: $target"
    else
      while [[ "$i" -le 5 ]]; do
        printf "Choose: [S] Skip, [O] Overwrite, [R] Rename (default: S)\n"
        read -r -p "> " choice; choice="${choice:-S}"
        case "$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')" in
          o) run_cmd "rm -rf '$target'"; log_info "Removed existing folder '$target'."; break ;;
          r) target="${target}_$((RANDOM % 900 + 100))"; log_info "Using new folder name: $target"; break ;;
          s) log_warn "Skipping clone for $repo."; return 1 ;;
          *) log_warn "Invalid option. Attempt $i/5"; i=$((i+1)) ;;
        esac
        if [[ "$i" -gt 5 ]]; then log_warn "Too many invalid attempts. Skipping $repo."; return 1; fi
      done
    fi
  fi

  if ! run_cmd "git clone --progress '$repo' '$target'"; then
    log_err "git clone failed for $repo"
    return 1
  fi
  log_done "Cloned $repo -> $target"
  printf '%s\n' "$target"
}

# ======================== Run detection ========================
has_make_up(){ [[ -f Makefile ]] && grep -qE '^\s*up:' Makefile; }
compose_file(){ for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do [[ -f "$f" ]] && { echo "$f"; return 0; }; done; return 1; }
has_pkg_json_start(){ [[ -f package.json ]] && grep -q '"start"\s*:' package.json; }

preferred_pkg_manager(){
  [[ -f yarn.lock ]] && { echo yarn; return; }
  [[ -f pnpm-lock.yaml ]] && { echo pnpm; return; }
  [[ -f package-lock.json || -f package.json ]] && { echo npm; return; }
  echo ""
}
detect_run_option(){
  if has_make_up; then echo "make"; return; fi
  if compose_file >/dev/null; then echo "compose"; return; fi
  if has_pkg_json_start; then echo "$(preferred_pkg_manager)"; return; fi
  echo ""
}
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

# ======================== Steps ========================
CLONED=()
CLONE_SUCCESSES=0

step_workspace_and_clone(){
  local COUNT repo folder name

  if [[ -z "$QUICKUP_WORKSPACE" ]]; then
    if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
      QUICKUP_WORKSPACE="quickup-workspace-$(date +%Y%m%d-%H%M%S)"
      log_info "Non-interactive: using workspace '$QUICKUP_WORKSPACE'"
    else
      read_with_retries "Enter a workspace name:" QUICKUP_WORKSPACE validate_nonempty || {
        log_err "No valid workspace name provided after ${_prompt_attempts_default} attempts. Skipping workspace setup."
        return 1
      }
    fi
  fi
  run_cmd "mkdir -p '$QUICKUP_WORKSPACE'"
  cd "$QUICKUP_WORKSPACE"

  local repos_list=()
  if [[ -n "$QUICKUP_REPOS_RAW" ]]; then
    IFS=', ' read -r -a repos_list <<< "$QUICKUP_REPOS_RAW"
  else
    if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
      log_warn "Non-interactive and no QUICKUP_REPOS provided; skipping clone step."
      return 0
    fi
    if ! read_with_retries "How many repos would you like to clone?" COUNT validate_pos_int; then
      log_err "Invalid repo count after ${_prompt_attempts_default} attempts. Skipping clone step."
      return 1
    fi
    for ((i=1;i<=COUNT;i++)); do
      local repo_in=""
      if read_with_retries "[$i/$COUNT] Repo URL (HTTPS or SSH):" repo_in validate_repo_url; then
        repos_list+=("$repo_in")
      else
        log_warn "Skipping this repo (invalid URL after ${_prompt_attempts_default} attempts)."
      fi
    done
  fi

  for repo in "${repos_list[@]}"; do
    folder=""
    if [[ "${QUICKUP_NONINTERACTIVE}" != "1" ]]; then
      read_with_retries "Optional folder name (enter for default):" folder "" 1 || true
    fi
    local res; res="$(git_clone_safe "$repo" "$folder" || true)"
    if [[ -n "$res" ]]; then
      CLONED+=("$res")
      CLONE_SUCCESSES=$((CLONE_SUCCESSES+1))
    fi
  done
}

ensure_core_deps(){
  install_git
  install_docker
  install_make
  log_done "Core dependencies checked."
}

ensure_toolchains_for_repo(){
  local dir="$1"
  log_info "Analyzing $dir for ecosystem tooling…"
  pushd "$dir" >/dev/null || return 0

  if is_flutter_repo; then
    log_info "Flutter project detected."
    install_flutter
    install_fvm
    ensure_path_export "$HOME/.pub-cache/bin"
    ensure_env_var PUB_CACHE "$HOME/.pub-cache"
  fi

  if is_node_repo; then
    log_info "Node project detected."
    if install_nvm; then
      local desired=""
      if [[ -f .nvmrc ]]; then desired="$(tr -d ' \r\n' < .nvmrc)"; fi
      if [[ -z "$desired" ]]; then desired="$(read_package_json_field)"; fi
      if [[ -z "$desired" ]]; then desired="$QUICKUP_NODE_VERSION"; fi
      if [[ -z "$desired" ]] && [[ "${QUICKUP_NONINTERACTIVE}" != "1" ]]; then
        read_with_retries "Enter Node version to install (e.g. 20):" desired validate_node_version || true
      fi
      [[ -n "$desired" ]] && install_node_version "$desired"
    else
      log_warn "Skipping Node setup (NVM not installed)."
    fi
  fi

  if is_python_repo; then
    log_info "Python project detected."
    install_python_tools
    if has_cmd python3; then
      if [[ "${QUICKUP_NONINTERACTIVE}" == "1" ]]; then
        log_info "Non-interactive: creating venv and installing requirements if present."
        run_cmd "python3 -m venv .venv || true"
        [[ -f .venv/bin/activate ]] && . .venv/bin/activate || true
        [[ -f requirements.txt ]] && run_cmd "pip3 install -r requirements.txt || true"
      else
        if confirm "Create a virtual environment (.venv) and install requirements?" "n"; then
          run_cmd "python3 -m venv .venv || true"
          [[ -f .venv/bin/activate ]] && . .venv/bin/activate || true
          [[ -f requirements.txt ]] && run_cmd "pip3 install -r requirements.txt || true"
        fi
      fi
    fi
  fi

  if is_java_repo; then
    log_info "Java project detected."
    install_sdkman
    local jv="${QUICKUP_JAVA_VERSION}"
    if [[ -z "$jv" ]] && [[ -f .java-version ]]; then jv="$(tr -d ' \r\n' < .java-version)"; fi
    if [[ -z "$jv" ]] && [[ "${QUICKUP_NONINTERACTIVE}" != "1" ]]; then
      read_with_retries "Enter Java version (8/11/17/21 or temurin-17):" jv validate_java_version || true
    fi
    [[ -n "$jv" ]] && install_java_version "$jv"
  fi

  popd >/dev/null || true
}

run_project_auto(){
  local detected; detected="$(detect_run_option)"
  case "$detected" in
    make) has_cmd make && run_cmd "make up" || log_warn "make missing." ;;
    compose) has_cmd docker && run_cmd "docker compose up -d" || log_warn "docker compose unavailable." ;;
    yarn) (has_cmd yarn || (has_cmd corepack && run_cmd "corepack prepare yarn@stable --activate")); run_cmd "yarn install || true"; run_cmd "yarn start" ;;
    pnpm) (has_cmd pnpm || (has_cmd corepack && run_cmd "corepack prepare pnpm@latest --activate")); run_cmd "pnpm install"; run_cmd "pnpm start" ;;
    npm) has_cmd npm && { [[ -f package-lock.json ]] && run_cmd "npm ci" || run_cmd "npm install" ; run_cmd "npm run start"; } || log_warn "npm missing." ;;
    *) log_warn "No run method detected." ;;
  esac
}

run_project_interactive(){
  local detected label sel
  detected="$(detect_run_option)"
  label="$(human_label "$detected")"
  echo
  log_info "Run options for $(pwd):"
  echo "  [1] Auto (recommended: $label)"
  echo "  [2] Make (make up)"
  echo "  [3] Yarn (yarn start)"
  echo "  [4] npm (npm run start)"
  echo "  [5] PNPM (pnpm start)"
  echo "  [6] Docker Compose (up -d)"
  echo "  [7] Quit"
  read_with_retries "Choose an option [default 1]:" sel validate_pos_int || sel=1
  case "$sel" in
    1) run_project_auto ;;
    2) has_cmd make && run_cmd "make up" || log_err "make not installed." ;;
    3) (has_cmd yarn || (has_cmd corepack && run_cmd "corepack prepare yarn@stable --activate")); run_cmd "yarn install || true"; run_cmd "yarn start" ;;
    4) has_cmd npm && { [[ -f package-lock.json ]] && run_cmd "npm ci" || run_cmd "npm install" ; run_cmd "npm run start"; } || log_err "npm missing." ;;
    5) (has_cmd pnpm || (has_cmd corepack && run_cmd "corepack prepare pnpm@latest --activate")); run_cmd "pnpm install"; run_cmd "pnpm start" ;;
    6) has_cmd docker && run_cmd "docker compose up -d" || log_err "docker compose unavailable." ;;
    7) : ;;
    *) log_warn "Invalid selection." ;;
  esac
}

run_project(){
  local dir="$1"
  pushd "$dir" >/dev/null || return 0
  if [[ "${QUICKUP_AUTO_RUN}" == "1" ]]; then
    run_project_auto
  else
    run_project_interactive
  fi
  popd >/dev/null || true
}

# ======================== Main ========================
MAIN_EXIT=0

log_info "Step 1/4: Project Workspace & Repository Cloning"
step_workspace_and_clone || log_warn "Workspace/clone step had issues."
echo

log_info "Step 2/4: Core Dependencies (git, docker, make)"
ensure_core_deps
echo

if [[ "${QUICKUP_SKIP_TOOLCHAINS}" != "1" ]]; then
  log_info "Step 3/4: Ecosystem Toolchains (per repo)"
  if [[ "${#CLONED[@]}" -gt 0 ]]; then
    for d in "${CLONED[@]}"; do
      ensure_toolchains_for_repo "$d"
    done
  else
    log_warn "No cloned repositories to analyze."
  fi
  echo
else
  log_warn "Skipping toolchain step per flag."
fi

log_info "Step 4/4: Run"
if [[ "${QUICKUP_ENABLE_RUN}" != "1" && "${QUICKUP_AUTO_RUN}" != "1" ]]; then
  log_warn "Run step disabled. Use --run for menu or --auto-run to run automatically."
elif [[ "${#CLONED[@]}" -gt 0 ]]; then
  if [[ "${QUICKUP_AUTO_RUN}" == "1" ]]; then
    run_project "${CLONED[0]}"
  else
    echo "Select a project to run:"
    local_idx=1
    for d in "${CLONED[@]}"; do echo "  [$local_idx] $d"; local_idx=$((local_idx+1)); done
    choice=""
    if read_with_retries "Enter a number:" choice validate_pos_int && validate_index_in_range "$choice" "${#CLONED[@]}"; then
      run_project "${CLONED[$((choice-1))]}"
    else
      log_warn "No valid selection provided."
    fi
  fi
else
  log_warn "Nothing to run."
fi

if [[ "${CLONE_SUCCESSES}" -eq 0 && -n "${QUICKUP_REPOS_RAW}" ]]; then
  log_err "All clones failed."
  MAIN_EXIT=2
fi

log_done "All done. Happy hacking!"
exit "${MAIN_EXIT}"
