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

---

## Quick Start  

### Manual Run (any OS)
Clone this repository and run the setup script:

```bash
# Make it executable and run
chmod +x setup_workspace.sh
./setup_workspace.sh
```

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

To run directly in PowerShell without cloning:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.ps1')"
```
or
```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.ps1')"
```

This downloads and executes the latest version of the setup script.

---

## Features Overview

| Feature | Description |
|----------|-------------|
| **Multi-repo cloning** | Clone as many repositories as needed in one step |
| **Smart dependency check** | Verifies and installs Git, Docker, Make automatically |
| **Language auto-detection** | Detects Node, Flutter, Python, Java, and sets up appropriate tools |
| **Interactive prompts** | Guided setup with retry logic and safe defaults |
| **Cross-platform support** | Works on macOS, Linux, WSL, and Windows PowerShell |
| **Environment auto-config** | Adds missing PATH and environment variables automatically |
| **Run helper** | Detects project run command (`make up`, `docker compose`, `npm start`, etc.) |

---

## Example Use Case
When a new developer joins your team:
1. They install Quickup (via Brew, curl, or PowerShell).  
2. Run `quickup`.  
3. Enter a workspace name (e.g. `team-portal`).  
4. Add repo URLs for frontend and backend.  
5. Quickup installs dependencies, configures paths, and runs the selected project.

Done — no more manual setup headaches.

---

## Troubleshooting
- If a tool (like Git or Docker) is not detected after installation, restart your shell or run:
  ```bash
  source ~/.bashrc  # or ~/.zshrc depending on shell
  ```
- On Windows, open a new PowerShell window after installation.

---

## Contributing
Pull requests and issues are welcome!  
Please ensure all contributions are tested on at least **two platforms** (e.g. macOS + Windows or Linux + WSL).

---

## License
MIT © [RookiePlayers](https://github.com/RookiePlayers)
