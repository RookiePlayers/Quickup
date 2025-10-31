# Changelog

## [1.2.0] - 2025-10-31

### Added
- Added support for cloning **any number of repositories** interactively or via config file.
- Added **multi-environment auto-detection** (Node, Flutter, Python, Java) with relevant setup tools (`nvm`, `sdkman`, `fvm`).
- Added **config file support** — Quickup can now load from `.env`, `.json`, or `.yaml` for **non-interactive automation**.
- Added **retry validation** for user inputs to prevent early termination on invalid input.
- Added **PowerShell version** for Windows users, supporting full feature parity with the Bash version.
- Added **automatic dependency checks and installation** for Git, Docker, and Make.
- Added **auto PATH and environment variable configuration** for all supported platforms.
- Added **dry-run mode** and **colorized logging** (`--dry-run`, `--no-color`, etc.).
- Added **configurable flags** like `QUICKUP_ENABLE_RUN`, `QUICKUP_SKIP_TOOLCHAINS`, and `QUICKUP_ASSUME_YES`.

### Improved
- Enhanced **cross-platform compatibility** (macOS, Linux, WSL, and Windows PowerShell).
- Improved error handling — invalid inputs now allow up to 5 retries before skipping.
- Improved logging output for cleaner, color-safe terminal rendering (removed ANSI escape artifacts).
- Consolidated **non-interactive mode** behavior when a config file is loaded (assumes “yes” automatically).
- Auto-detects and runs appropriate project startup commands (`make up`, `docker compose up`, `npm start`, etc.).

### Fixed
- Fixed issues where repeated repo URLs caused duplicate cloning prompts.
- Fixed parsing errors with YAML/JSON configs using process substitution (Bash-safe).
- Fixed PowerShell behavior for `git` and `docker` detection post-installation.
- Fixed fallback logic for macOS/Linux package manager detection.

### Tested
- Tested on **macOS Ventura 14**, **Ubuntu 22.04**, and **Windows 11 (PowerShell 5.1 + 7.4)**.
- Verified correct execution under both **interactive** and **config-driven** setups.


## [Unreleased]

### Added
- This allows you to clone up to n repos, and boot them up.
- This version supports, node environments like npm, yarn projects. 
- Tested on macOs and linux