# Quickup 
one command to spin up a whole dev workspace for new teammates.

## Introduction
one command to spin up a whole dev workspace for new teammates. Here's a pragmatic, cross-OS friendly approach that works on macOS, Linux, and WSL. It's interactive, handles "x" repos, verifies/installs prerequisites (Docker, Make, Git), and then lets the user pick which project to make up.

## Quick start
Clone this repo then run the following:

```bash
# Make it executable and run it:
chmod +x setup_workspace.sh
./setup_workspace.sh
```

## MacOS Setup

We have created a brew installation for this.
### Installation
```bash
brew tap RookiePlayers/quickup
brew install quickup
```
To start just run the following
```bash
quickup
```

## Linux & wsl setup

### Installation
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/RookiePlayers/Quickup/main/install.sh)
```

To start just run the following
```bash
quickup
```

## Windows Powershell
To run this directly in powershell use this command
```bash
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr -UseBasicParsing https://raw.githubusercontent.com/RookiePlayers/Quickup/main/setup_workspace.ps1 | iex"
```