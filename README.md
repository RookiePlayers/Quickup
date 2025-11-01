# Quickup  
> One command to spin up a complete dev workspace for new teammates — cross-platform, interactive, and fast.

---

## Introduction  
**Quickup** automates the setup process for any development workspace — whether it’s for a new teammate joining your project or spinning up your own environment from scratch.  

It runs on **macOS**, **Linux**, **Windows**, and **WSL**, and does the following:
- Creates a local workspace folder interactively  
- Clones multiple repositories in one go  
- Detects each repo type (Node, Flutter, Python, Java, etc.)  
- Verifies or installs dependencies like **Docker**, **Make**, and **Git**  
- Optionally installs ecosystem managers like **nvm**, **sdkman**, or **fvm**  
- Auto-detects how to run each project (Makefile, Docker, npm, etc.)  
- Supports **non-interactive config files** (.env, .json, or .yaml)

---

## Quick Start  

### Manual Run (any OS)
Clone this repository and run the setup script:

```bash
# Make it executable and run
chmod +x setup_workspace.sh
./setup_workspace.sh
```

You’ll be guided through an interactive setup flow.

---

## Config File Support

Quickup now supports loading configuration from **.env**, **.json**, or **.yaml** files for non-interactive automation.

### Example `.env`
```bash
# Workspace setup
QUICKUP_WORKSPACE="my_workspace"
QUICKUP_REPOS="https://github.com/org/repo1.git,https://github.com/org/repo2.git"
QUICKUP_REPO_FOLDERS="repo1_folder,repo2_folder"

# Tool versions
QUICKUP_NODE_VERSION="16"
QUICKUP_JAVA_VERSION="11"
QUICKUP_FLUTTER_VERSION="3.0.0"

# Flags
QUICKUP_DRY_RUN=1
QUICKUP_NO_LOG=1
QUICKUP_SKIP_TOOLCHAINS=0
QUICKUP_LOG_FILE="quickup.log"
QUICKUP_ASSUME_YES=1
QUICKUP_COLOR=always
QUICKUP_DEBUG=0
QUICKUP_VERBOSE=0
QUICKUP_ENABLE_RUN=0
```

### Example `.json`
```json
{
  "QUICKUP_WORKSPACE": "my_workspace",
  "QUICKUP_REPOS": ["https://github.com/org/repo1.git", "https://github.com/org/repo2.git"],
  "QUICKUP_REPO_FOLDERS": ["repo1_folder", "repo2_folder"],
  "QUICKUP_NODE_VERSION": "16",
  "QUICKUP_JAVA_VERSION": "11",
  "QUICKUP_FLUTTER_VERSION": "3.0.0",
  "QUICKUP_ENABLE_RUN": 0
}
```

### Example `.yaml`
```yaml
QUICKUP_WORKSPACE: "my_workspace"
QUICKUP_REPOS:
  - "https://github.com/org/repo1.git"
  - "https://github.com/org/repo2.git"
QUICKUP_REPO_FOLDERS:
  - "repo1_folder"
  - "repo2_folder"
QUICKUP_NODE_VERSION: "16"
QUICKUP_JAVA_VERSION: "11"
QUICKUP_FLUTTER_VERSION: "3.0.0"
QUICKUP_ENABLE_RUN: 0
```

### Usage with Config File
```bash
./setup_workspace.sh --config-file .env.example
```

When a config file is used, Quickup automatically switches to **non-interactive mode**, assuming “yes” to prompts and skipping user input.

---

## macOS Installation (via Homebrew)

Quickup is available as a Homebrew formula for easy installation.

### Installation
```bash
brew tap RookiePlayers/quickup
brew install quickup
```

### Usage
```bash
quickup
```

This will launch the full interactive setup flow.

---

## Linux & WSL Installation

### Installation
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RookiePlayers/Quickup/main/install.sh)
```

### Usage
```bash
quickup
```

Quickup automatically detects whether you’re on native Linux or WSL and adjusts accordingly.

---

## Windows (PowerShell)

Run Quickup directly from PowerShell or CMD without cloning:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.ps1')"
```

### With Config File
```powershell
$u   = 'https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.ps1'
$tmp = Join-Path $env:TEMP 'quickup.ps1'
Invoke-WebRequest $u -OutFile $tmp
powershell -NoProfile -ExecutionPolicy Bypass -File $tmp -ConfigFile .\.config.yml
```
**If you are going to run with yml make sure to install the following**
```powershell
choco install yq -y
# or
winget install --id MikeFarah.yq -e
```

This will load `.env`, `.json`, or `.yaml` configuration automatically and skip all interactive prompts.

---

## Features Overview

| Feature | Description |
|----------|-------------|
| **Multi-repo cloning** | Clone multiple repositories in one step |
| **Smart dependency check** | Verifies and installs Git, Docker, Make automatically |
| **Language auto-detection** | Detects Node, Flutter, Python, Java, and installs required tools |
| **Config file mode** | Use `.env`, `.json`, or `.yaml` files to automate setup |
| **Cross-platform** | Works on macOS, Linux, WSL, and Windows |
| **Environment auto-config** | Adds missing PATH and env vars automatically |
| **Run helper** | Detects and runs your project via `make up`, `docker compose up`, or `npm start` |

---

## Example Use Case
When a new developer joins your team:
1. They install Quickup (via Brew, curl, or PowerShell).  
2. Run `quickup` or the PowerShell command above.  
3. Enter (or pre-define) a workspace name and repositories.  
4. Quickup installs dependencies, configures toolchains, and optionally runs the project.

No more manual setup headaches.

---

## Troubleshooting
- If a tool (like Git or Docker) isn’t detected after install, restart your shell:
  ```bash
  source ~/.bashrc  # or ~/.zshrc depending on shell
  ```
- On Windows, open a new PowerShell window after installation.

---

## Contributing
Pull requests and issues are welcome!  
Please ensure contributions are tested on at least **two platforms** (e.g. macOS + Windows or Linux + WSL).

---

## License
MIT © [octech](https://github.com/RookiePlayers)
