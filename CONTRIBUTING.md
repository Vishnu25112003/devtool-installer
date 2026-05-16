# Contributing to devtool-installer

## Code style

- Pure Bash only. No Python, Node, or compiled helpers.
- `set -uo pipefail` at the top. Never `set -e`.
- Quote every variable expansion: `"${var}"`.
- Use `[[ ]]` not `[ ]`. Use `$()` not backticks.
- All user-visible output goes through `log` / `success` / `warn` / `err` — no raw `echo`.
- Every function needs a one-line comment explaining what it does.
- Functions above main code. Constants at the top. `main()` at the bottom.
- Pass `shellcheck` with zero errors before opening a PR.

## Adding a package

1. Add a `_define_pkg` call in Section 5 with all 9 fields.
2. If the package needs a custom installer, add an `install_<id>()` function in Section 10.
3. If the package needs post-install configuration, add a `hook_<id>()` function in Section 11 and call it from `run_post_install_hooks()`.
4. Update the package count in the README table.

## Adding a custom installer

```bash
# One-line description of what this installer does
install_mypackage() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "mypackage"
    else
        log "Installing mypackage..."
        _run_cmd "curl -fsSL https://example.com/install.sh | sh"
    fi
}
```

Rules:
- Use `_run_cmd` / `_run_sudo` for all commands so `--dry-run` mode works.
- Never `source` external files.
- Always quote URLs.

## Testing

Before opening a PR:

```bash
# Lint
shellcheck install.sh

# Dry-run on your machine
./install.sh --dry-run

# Full Docker test suite
bash test/run-tests.sh
```

## PR rules

- One logical change per PR.
- Title: `feat: add <package>` / `fix: <description>` / `chore: <description>`.
- Describe what you tested and on which OS.
