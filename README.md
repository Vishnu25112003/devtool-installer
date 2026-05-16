# devtool-installer

> One-shot dev environment bootstrapper for Arch Linux and Debian-based distributions.

Run one command on a fresh OS, pick what you want from interactive checkbox menus, walk away. Come back to a ready-to-code machine.

## Quick Start

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/devtool-installer/main/install.sh)
```

## Supported Operating Systems

| Family | Distributions |
|--------|--------------|
| Arch   | Arch Linux, Manjaro, EndeavourOS |
| Debian | Ubuntu 22.04/24.04, Debian 12, Linux Mint, Pop!_OS |

## Features

- Interactive checkbox UI (whiptail/libnewt)
- 40 curated packages across 4 categories
- Save & load profiles for repeatable setups
- Dry-run mode (`--dry-run`) — preview without changes
- Automatic dependency resolution
- Post-install hooks (Docker group, shell config, PATH setup)
- Per-tool custom installers (NodeSource, rustup, oh-my-zsh, etc.)

## Package Categories

| Category | Count | Examples |
|----------|-------|---------|
| System Essentials | 8 | git, curl, build tools, openssh |
| Dev Tools | 15 | Node.js, Python, Go, Rust, Docker, Neovim |
| AI Tools | 8 | Ollama, Claude Code, Gemini CLI, Copilot CLI |
| Other Tools | 9 | VS Code, Postman, Brave, Obsidian |

## CLI Flags

```
--dry-run           Preview all actions without executing them
--profile <path>    Load a profile file (non-interactive)
--quiet             Suppress non-essential output
--verbose           Show extra debug output
--help              Show usage information
--version           Show script version
```

## Profiles

Profiles are plain text files with one package ID per line:

```
# minimal.profile
git
curl
wget
neovim
tmux
```

### Bundled Profiles

| Profile | Description |
|---------|-------------|
| `profiles/minimal.profile` | Essentials only — git, curl, neovim, tmux |
| `profiles/fullstack.profile` | Web dev stack — node, python, docker, vscode, gh |
| `profiles/ai-developer.profile` | AI dev setup — ollama, claude-code, gemini-cli, aider |

Load a bundled profile:

```bash
bash install.sh --profile profiles/fullstack.profile
```

Load a profile from a URL (e.g., a GitHub Gist):

```bash
bash install.sh --profile https://gist.githubusercontent.com/YOU/HASH/raw/my.profile
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
