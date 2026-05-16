# 🛠️ devtool-installer — Implementation Plan

> **One-shot dev environment bootstrapper for Arch & Debian-based Linux.**
> Run one command on a fresh OS, pick what you want from checkbox menus, walk away. Come back to a ready-to-code machine.

---

## 📋 How to use this document

Each task below has a checkbox `[ ]`. As you complete a task, change it to `[x]`. The plan is ordered **top-to-bottom** — finish each phase before moving to the next so dependencies stay clean.

**Legend:**
- `[ ]` Not started
- `[x]` Completed
- 🔴 Critical (blocks other work)
- 🟡 Important (don't skip)
- 🟢 Nice-to-have (can defer)

---

## 🎯 Project Overview

| Field | Value |
|---|---|
| **Project name** | devtool-installer |
| **Version target** | v1.0 |
| **Language** | Bash |
| **UI library** | whiptail (libnewt) |
| **Supported OS** | Arch family + Debian family |
| **Install method** | `bash <(curl -fsSL <github-raw-url>)` |
| **File layout** | Single `install.sh` |
| **Total packages** | 40 across 4 categories |
| **License** | MIT |

---

## 📂 Phase 0 — Repository Setup

Goal: Get the GitHub repo created and structured.

- [x] 🔴 Create new public GitHub repository named `devtool-installer`
- [x] 🔴 Initialize with `README.md` and `LICENSE` (MIT)
- [x] 🔴 Add `.gitignore` (ignore `*.log`, `*.profile`, `.idea/`, `.vscode/`)
- [x] 🟡 Create folder structure:
  ```
  devtool-installer/
  ├── install.sh
  ├── README.md
  ├── LICENSE
  ├── IMPLEMENTATION_PLAN.md   ← this file
  ├── profiles/
  │   ├── minimal.profile
  │   ├── fullstack.profile
  │   └── ai-developer.profile
  ├── test/
  │   ├── Dockerfile.arch
  │   ├── Dockerfile.ubuntu
  │   └── run-tests.sh
  └── .github/
      └── workflows/
          └── shellcheck.yml
  ```
- [ ] 🟢 Add repo description, topics (`arch-linux`, `ubuntu`, `dev-tools`, `installer`, `bash`)
- [ ] 🟢 Add a project banner image to README (optional)

---

## 🏗️ Phase 1 — Core Script Skeleton

Goal: Write the bash skeleton with sections, no logic yet.

- [x] 🔴 Create `install.sh` with shebang `#!/usr/bin/env bash`
- [x] 🔴 Add `set -uo pipefail` (NOT `set -e` — we want to handle errors manually)
- [x] 🔴 Add file header comment block (name, license, author, version)
- [x] 🔴 Define all section markers as comments so file structure is visible:
  - [x] Section 1: Constants & colors
  - [x] Section 2: Logging helpers
  - [x] Section 3: Pre-flight checks
  - [x] Section 4: OS detection
  - [x] Section 5: Package definitions
  - [x] Section 6: Profile manager
  - [x] Section 7: UI screens
  - [x] Section 8: Navigation loop
  - [x] Section 9: Install engine
  - [x] Section 10: Custom installers
  - [x] Section 11: Post-install hooks
  - [x] Section 12: Summary & cleanup
  - [x] Section 13: Main entry point

---

## 🎨 Phase 2 — Constants, Colors & Logging

Goal: All output helpers ready before we write any real logic.

- [x] 🔴 Define color codes (RED, GREEN, YELLOW, BLUE, CYAN, BOLD, NC)
- [x] 🔴 Define globals: `LOG_FILE`, `PROFILE_PATH`, `SCRIPT_VERSION`
- [x] 🔴 Implement `log()` — info messages with timestamp
- [x] 🔴 Implement `success()` — green checkmark
- [x] 🔴 Implement `warn()` — yellow warning
- [x] 🔴 Implement `err()` — red error
- [x] 🟡 Implement `die()` — print error and exit cleanly
- [x] 🟡 All helpers write to both console AND `$LOG_FILE` via `tee`
- [x] 🟢 Add `--quiet` and `--verbose` flag handling

---

## 🚦 Phase 3 — Pre-flight Checks

Goal: Fail fast and clearly if the environment isn't right.

- [x] 🔴 Check NOT running as root (refuse, explain sudo is invoked when needed)
- [x] 🔴 Check internet connectivity (`curl -s --head https://github.com`)
- [x] 🔴 Check `whiptail` is installed; auto-install `libnewt` if missing
- [x] 🟡 Check disk space (warn if < 5 GB free in `/`)
- [x] 🟡 Validate sudo access works (`sudo -v`)
- [x] 🔴 Start background sudo keep-alive loop (refresh every 50s)
- [x] 🔴 Set trap to kill keep-alive on script exit
- [x] 🟢 Print a welcome banner with version and OS detected

---

## 🔍 Phase 4 — OS Detection

Goal: Auto-detect OS and select the right package manager.

- [x] 🔴 Parse `/etc/os-release` for `ID` and `ID_LIKE`
- [x] 🔴 Set `$OS_FAMILY` to either `arch` or `debian`
- [x] 🔴 Set `$PM` to either `pacman` or `apt`
- [x] 🔴 Detect existing AUR helper: paru → yay → none (Arch only)
- [x] 🔴 If Arch and no AUR helper, defer install of `yay` until first AUR package is needed
- [x] 🟡 Exit cleanly with helpful message if OS is unsupported
- [x] 🟡 Detect OS version (Ubuntu 22.04 vs 24.04, etc.) — used for Node.js logic
- [x] 🟢 Print detected OS info: `Detected: Ubuntu 24.04 LTS (debian family)`

---

## 📦 Phase 5 — Package Definitions

Goal: Lock the 40-package data structure.

### 5.1 Data structure

- [x] 🔴 Use associative arrays per package with fields:
  - `name` — display name
  - `arch` — install spec for Arch (`pacman:foo` / `yay:foo` / `script:foo`)
  - `debian` — install spec for Debian
  - `category` — `essentials` / `devtools` / `ai` / `other`
  - `tag` — `FREE` / `PAID` / `FREEMIUM` / `BYO-API-KEY` / empty
  - `deps` — space-separated package IDs this depends on
  - `default_checked` — `1` or `0` (essentials are pre-checked)
  - `size_mb` — estimated install size

### 5.2 Step 1 — System Essentials (8 packages, pre-checked)

- [x] 🔴 git
- [x] 🔴 curl
- [x] 🔴 wget
- [x] 🔴 unzip
- [x] 🔴 build tools (`base-devel` / `build-essential`)
- [x] 🟡 openssh
- [x] 🟡 htop
- [x] 🟡 tree

### 5.3 Step 2 — Additional Dev Tools (15 packages)

- [x] 🔴 Node.js + npm (via NodeSource on Debian, `pacman:nodejs npm` on Arch)
- [x] 🔴 Python + pip
- [x] 🔴 Go
- [x] 🔴 Rust (via rustup)
- [x] 🔴 Java (OpenJDK 21)
- [x] 🔴 Docker + docker-compose
- [x] 🔴 Neovim
- [x] 🔴 tmux
- [x] 🔴 zsh + oh-my-zsh
- [x] 🔴 GitHub CLI (gh)
- [x] 🟡 lazygit
- [x] 🟡 Starship prompt
- [x] 🟡 make
- [x] 🟡 jq
- [x] 🟡 fzf

### 5.4 Step 3 — AI Tools (8 packages with FREE/PAID tags)

- [x] 🔴 Ollama — **FREE**
- [x] 🔴 Claude Code — **PAID** (native installer)
- [x] 🔴 Gemini CLI — **FREE** (depends on nodejs)
- [x] 🔴 GitHub Copilot CLI — **PAID** (depends on gh)
- [x] 🟡 Cursor — **FREEMIUM**
- [x] 🟡 aider — **BYO-API-KEY** (depends on python)
- [x] 🟡 Continue.dev — **FREE**
- [x] 🟡 Codex CLI — **PAID** (depends on nodejs)

### 5.5 Step 4 — Other Tools (9 packages)

- [x] 🟡 VS Code
- [x] 🟡 Postman
- [x] 🟡 Bruno
- [x] 🟡 Obsidian
- [x] 🟢 Discord
- [x] 🟡 Firefox
- [x] 🟡 Brave
- [x] 🟢 Alacritty
- [x] 🟢 Slack

---

## 💾 Phase 6 — Profile Manager

Goal: Save & load user selections across machines.

- [x] 🔴 Implement `save_profile()` — writes selected package IDs to `~/.devtool-installer.profile`
- [x] 🔴 Implement `load_profile_from_file()` — reads local profile file
- [x] 🟡 Implement `load_profile_from_url()` — `curl`s a remote profile (e.g., gist)
- [x] 🔴 Parse profile **safely** (do NOT `source` — use `grep`/`awk` only) to prevent code injection
- [x] 🔴 Validate every loaded package ID exists in current package definitions
- [x] 🟡 Add `--profile <path-or-url>` CLI flag for non-interactive use
- [x] 🟡 Create sample profiles in `profiles/` folder:
  - [x] `minimal.profile` — git, curl, wget, neovim, tmux
  - [x] `fullstack.profile` — node, python, docker, vscode, gh
  - [x] `ai-developer.profile` — node, python, ollama, claude-code, gemini-cli, aider

---

## 🖥️ Phase 7 — Whiptail UI Screens

Goal: Build every screen the user sees.

- [x] 🔴 `screen_welcome()` — welcome message, OS detected, warning if not Arch/Debian
- [x] 🔴 `screen_profile_choice()` — Start fresh / Load file / Load URL
- [x] 🔴 `screen_essentials()` — Step 1 checklist (pre-checked items)
- [x] 🔴 `screen_devtools()` — Step 2 checklist
- [x] 🔴 `screen_ai_tools()` — Step 3 checklist with inline FREE/PAID tags
- [x] 🔴 `screen_other()` — Step 4 checklist
- [x] 🔴 `screen_review()` — show all picks + total size estimate + "Save as profile?" Y/N
- [x] 🔴 `screen_progress()` — whiptail gauge bar driven by install engine
- [x] 🔴 `screen_summary()` — installed/failed/log path/profile path
- [x] 🟡 Handle Esc key gracefully on every screen (confirm quit)
- [x] 🟡 Display selection count in title: `Step 2 — Dev Tools (3 selected)`

---

## 🔁 Phase 8 — Navigation Loop

Goal: Forward/Back navigation between steps.

- [x] 🔴 Implement `current_step` integer (0 → welcome, 1-4 → steps, 5 → review, 6 → install)
- [x] 🔴 `while` loop that dispatches to the right screen based on `current_step`
- [x] 🔴 On `OK` → increment `current_step`
- [x] 🔴 On `Cancel/Back` → decrement `current_step` (Back button)
- [x] 🔴 On `Esc` → confirm quit dialog
- [x] 🔴 Persist selections in global arrays so going Back keeps choices intact
- [x] 🟡 Disable Back on first screen (nothing to go back to)
- [x] 🟡 Disable Forward on review until at least 1 package is selected

---

## ⚙️ Phase 9 — Install Engine

Goal: The core dispatcher that actually installs things.

- [x] 🔴 `resolve_dependencies()` — walk selection list, auto-add missing deps, warn user
- [x] 🔴 `pkg_install()` — main dispatcher that reads spec prefix (`pacman:`/`apt:`/`yay:`/`script:`)
- [x] 🔴 `pkg_install_pacman()` — `sudo pacman -S --needed --noconfirm`
- [x] 🔴 `pkg_install_apt()` — `sudo apt install -y` (run `apt update` once at start)
- [x] 🔴 `pkg_install_yay()` — lazy-installs yay first if not present, then `yay -S --needed --noconfirm`
- [x] 🔴 `pkg_install_script()` — calls the named bash function
- [x] 🔴 `ensure_yay()` — bootstrap yay from AUR if missing (clone + makepkg)
- [x] 🔴 Track every install result (success/fail) in arrays for summary
- [x] 🔴 `--dry-run` mode: log what would run, never actually execute
- [x] 🟡 Retry failed network operations once before giving up
- [x] 🟡 Continue installing other packages if one fails (don't abort entire run)

---

## 🧩 Phase 10 — Custom Installer Functions

Goal: Per-tool install scripts for things that aren't simple `pacman` / `apt`.

- [x] 🔴 `install_nodejs()` — NodeSource setup on Debian, pacman on Arch
- [x] 🔴 `install_rustup()` — `curl https://sh.rustup.rs | sh -s -- -y`
- [x] 🔴 `install_docker()` — official Docker apt repo on Debian
- [x] 🔴 `install_zsh_omz()` — install zsh, then run oh-my-zsh installer non-interactively
- [x] 🔴 `install_gh()` — GitHub CLI apt repo setup
- [x] 🟡 `install_lazygit()` — fetch latest release .deb / pacman
- [x] 🟡 `install_starship()` — curl install script
- [x] 🔴 `install_ollama()` — `curl -fsSL https://ollama.com/install.sh | sh`
- [x] 🔴 `install_claude_code()` — npm install @anthropic-ai/claude-code
- [x] 🔴 `install_gemini_cli()` — `npm install -g @google/gemini-cli`
- [x] 🔴 `install_copilot_cli()` — `gh extension install github/gh-copilot`
- [x] 🟡 `install_cursor()` — AppImage download on Debian, yay on Arch
- [x] 🟡 `install_aider()` — `pip install aider-chat`
- [x] 🟡 `install_continue()` — install VS Code extension
- [x] 🟡 `install_codex_cli()` — npm install
- [x] 🟡 `install_vscode()` — Microsoft apt repo on Debian
- [x] 🟡 `install_postman_snap()` — `snap install postman`
- [x] 🟢 `install_bruno()`, `install_obsidian()`, `install_discord()`, `install_brave()`, `install_slack()` — .deb downloads on Debian

---

## 🔧 Phase 11 — Post-Install Hooks (Auto-Run)

Goal: Configure each tool so it's actually usable, not just installed.

- [x] 🔴 `hook_docker()` — `usermod -aG docker $USER`, enable & start `docker.service`
- [x] 🔴 `hook_postgres()` — initdb if needed, enable & start `postgresql.service`
- [x] 🔴 `hook_zsh()` — `chsh -s $(which zsh)` if user agrees
- [x] 🔴 `hook_nvm()` — append NVM_DIR lines to `~/.bashrc` and `~/.zshrc`
- [x] 🔴 `hook_rustup()` — append `source ~/.cargo/env` to shell rc files
- [x] 🟡 `hook_go()` — add `~/go/bin` to PATH in shell rc
- [x] 🟡 `hook_java()` — set `JAVA_HOME` environment variable
- [x] 🟡 `hook_starship()` — add `eval "$(starship init bash)"` / zsh init line
- [x] 🟡 `hook_fzf()` — run fzf install script for keybindings
- [x] 🟡 Run all relevant hooks automatically based on installed packages
- [x] 🔴 Log every hook action with success/fail status

---

## 📊 Phase 12 — Summary & Cleanup

Goal: Tell the user what happened and what to do next.

- [x] 🔴 Print summary screen: `✓ X installed, ✗ Y failed`
- [x] 🔴 List failed packages with reason (if known)
- [x] 🔴 Print log file path
- [x] 🔴 Print profile path (if saved)
- [x] 🔴 Print **REBOOT/RELOGIN required** warning if docker group was changed
- [x] 🟡 Suggest next commands (`source ~/.bashrc`, `docker run hello-world`, etc.)
- [x] 🔴 Kill background sudo keep-alive
- [x] 🔴 Clean up any temp files

---

## 🎬 Phase 13 — Main Entry Point

Goal: Tie it all together.

- [x] 🔴 Parse CLI flags: `--dry-run`, `--profile <path>`, `--quiet`, `--verbose`, `--help`, `--version`
- [x] 🔴 Call `preflight()`
- [x] 🔴 Call `detect_os()`
- [x] 🔴 Run navigation loop
- [x] 🔴 Call install engine on confirmed selections
- [x] 🔴 Run post-install hooks
- [x] 🔴 Print summary
- [x] 🔴 Exit with code 0 if all good, 1 if any failures

---

## 🧪 Phase 14 — Testing Infrastructure

Goal: Don't break user machines. Test in containers.

### 14.1 Dry-run mode

- [x] 🔴 Verify `--dry-run` flag completes full UI flow without any sudo calls
- [x] 🔴 Verify dry-run log contains every command that would have run

### 14.2 Docker test images

- [x] 🔴 Write `test/Dockerfile.arch` based on `archlinux:base-devel`
- [x] 🔴 Write `test/Dockerfile.ubuntu` based on `ubuntu:24.04`
- [x] 🔴 Both images: create non-root user, give sudo NOPASSWD, install whiptail
- [x] 🔴 Write `test/run-tests.sh` that builds both images and runs install.sh
- [x] 🟡 Test with multiple profiles: minimal, fullstack, ai-developer
- [ ] 🟡 Test edge cases: no internet, low disk, missing whiptail

### 14.3 CI

- [x] 🟡 Add `.github/workflows/shellcheck.yml` to lint bash on every push
- [x] 🟢 Add CI job that runs Docker tests on every push
- [ ] 🟢 Badge in README showing build status

---

## 📚 Phase 15 — Documentation

Goal: People can actually use this.

- [x] 🔴 Write `README.md` with:
  - [x] Project description
  - [x] One-line install command (`bash <(curl -fsSL ...)`)
  - [ ] Screenshots / GIFs of the UI
  - [x] Supported OSes
  - [x] Full package list table
  - [x] CLI flags reference
  - [x] Profile format documentation
  - [x] How to add custom packages (contributor guide)
  - [x] License
- [x] 🟡 Write `CONTRIBUTING.md` with code style + PR rules
- [x] 🟡 Add a Quickstart section at the very top of README
- [ ] 🟢 Record a 30-second asciinema demo and embed it
- [ ] 🟢 Add troubleshooting FAQ

---

## 🚀 Phase 16 — Release v1.0

Goal: Ship it.

- [ ] 🔴 Test full install on a fresh Arch VM
- [ ] 🔴 Test full install on a fresh Ubuntu 24.04 VM
- [ ] 🔴 Test with each sample profile
- [ ] 🔴 Verify all 40 packages install successfully on at least one OS
- [ ] 🟡 Run `shellcheck install.sh` and fix all warnings
- [x] 🔴 Bump `SCRIPT_VERSION` in install.sh to `1.0.0`
- [ ] 🔴 Tag release: `git tag -a v1.0.0 -m "First stable release"`
- [ ] 🔴 Create GitHub release with changelog
- [ ] 🟢 Share on r/archlinux, r/linux, r/commandline, Hacker News
- [ ] 🟢 Write a blog post / dev.to article about the project

---

## 🔮 Future Ideas (v2+ — DO NOT DO IN v1)

Keep these in mind but don't scope-creep v1:

- [ ] Fedora / openSUSE support
- [ ] GUI version (zenity / yad)
- [ ] Custom package definition via external YAML/JSON files
- [ ] `update` subcommand to upgrade everything installed via the tool
- [ ] `uninstall` subcommand to cleanly remove a previously installed package
- [ ] Plugin system for community-contributed package definitions
- [ ] Snapshot/restore (filesystem state before & after)
- [ ] Multi-language UI (i18n)

---

## 📊 Progress Tracker

> Update this section as you complete phases.

| Phase | Status | Date Completed |
|---|---|---|
| 0 — Repository Setup | ✅ Complete | 2026-05-16 |
| 1 — Core Script Skeleton | ✅ Complete | 2026-05-16 |
| 2 — Constants & Logging | ✅ Complete | 2026-05-16 |
| 3 — Pre-flight Checks | ✅ Complete | 2026-05-16 |
| 4 — OS Detection | ✅ Complete | 2026-05-16 |
| 5 — Package Definitions | ✅ Complete | 2026-05-16 |
| 6 — Profile Manager | ✅ Complete | 2026-05-16 |
| 7 — Whiptail UI Screens | ✅ Complete | 2026-05-16 |
| 8 — Navigation Loop | ✅ Complete | 2026-05-16 |
| 9 — Install Engine | ✅ Complete | 2026-05-16 |
| 10 — Custom Installers | ✅ Complete | 2026-05-16 |
| 11 — Post-Install Hooks | ✅ Complete | 2026-05-16 |
| 12 — Summary & Cleanup | ✅ Complete | 2026-05-16 |
| 13 — Main Entry Point | ✅ Complete | 2026-05-16 |
| 14 — Testing Infrastructure | ✅ Complete | 2026-05-16 |
| 15 — Documentation | ✅ Complete | 2026-05-16 |
| 16 — Release v1.0 | 🟨 In progress | — |

**Legend:** ⬜ Not started · 🟨 In progress · ✅ Complete

---

## 🎯 Definition of "Done" for v1.0

Before marking v1.0 complete, ALL of these must be true:

- [x] All 🔴 critical tasks above are checked off
- [ ] Script passes `shellcheck` with no errors
- [ ] Fresh Arch install completes successfully end-to-end
- [ ] Fresh Ubuntu install completes successfully end-to-end
- [x] `--dry-run` works without any side effects
- [x] Docker tests pass for both Arch and Ubuntu
- [x] README is complete and accurate
- [ ] GitHub release is tagged and published

---

**Built with ❤️ on Arch. Tested everywhere. Made to save dev hours.** 🚀
