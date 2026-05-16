# Claude Code Prompt — devtool-installer Implementation

> **How to use this file:**
> 1. Open Claude Code in an empty folder (your future repo).
> 2. Make sure `IMPLEMENTATION_PLAN.md` is in that folder.
> 3. Copy everything below the `--- PROMPT START ---` line and paste it into Claude Code as your first message.
> 4. Let it work end-to-end. Review checkpoints. Test in Docker before running on a real machine.

---

--- PROMPT START ---

# 🎯 Task: Build `devtool-installer` end-to-end

You are implementing a complete bash tool called **devtool-installer** — a one-shot dev environment bootstrapper for Arch Linux and Debian-based distributions. The full specification is in `IMPLEMENTATION_PLAN.md` in this directory. **Read that file first and follow it as the source of truth.** Do not deviate from the locked decisions in that document.

## 📋 Constraints (non-negotiable)

- **Language:** Pure Bash only. No Python, no Node, no compiled binaries.
- **UI:** `whiptail` (from `libnewt`). No other TUI library.
- **OS Support:** Arch family (Arch, Manjaro, EndeavourOS) + Debian family (Ubuntu, Debian, Mint, Pop!_OS) only.
- **File layout:** Single `install.sh` file. Everything in one file so users can `bash <(curl -fsSL ...)` it.
- **No external dependencies** beyond what's listed in pre-flight checks. The script must be self-bootstrapping.
- **Do not write code I did not ask for.** Stick to the plan.

## 📐 Process (follow this order strictly)

1. **Read `IMPLEMENTATION_PLAN.md` completely before writing anything.** Confirm you understand the 17 phases.
2. **Start with Phase 0** (repo setup) and proceed through Phase 16 in order. Do not jump ahead.
3. After completing each phase, **update the checkboxes in `IMPLEMENTATION_PLAN.md`** from `[ ]` to `[x]` for every task you finished. Also update the **Progress Tracker** table at the bottom of that file.
4. **Commit logically.** At the end of each phase, suggest a git commit message I can use. Do not run git commands yourself unless I explicitly tell you to.
5. After each phase, **briefly summarize what you built and what's next.** Do not dump full file contents in the summary — I'll review the files directly.

## 🚦 Quality bar

- Every bash function must have a one-line comment explaining what it does.
- Use `set -uo pipefail` at the top. **Do NOT use `set -e`** — we handle errors manually so the install loop can continue after individual package failures.
- All user-facing output goes through the logging helpers (`log`, `success`, `warn`, `err`) — not raw `echo`.
- All commands that touch the filesystem or run sudo must respect `--dry-run` mode.
- Pass `shellcheck` with zero errors. Run it after each phase if shellcheck is available; otherwise note where you'd expect issues.
- Quote all variable expansions. Use `[[ ]]` not `[ ]`. Use `$()` not backticks.
- Functions go above main code. Constants at the top. Main entry point at the bottom.

## 🧪 Testing rules

- After Phase 14 (testing infrastructure), build both Docker images and run the script in `--dry-run` mode inside each container.
- Do NOT run the actual installer on the host machine — only inside containers or with `--dry-run`.
- If a test fails, stop, report the failure clearly, and ask me how to proceed before fixing.

## 🛡️ Safety rules

- Never run `sudo` commands during planning or skeleton phases. Sudo is only invoked from within the install engine and post-install hooks.
- Never `rm -rf` anything outside `/tmp` or the script's own temp directories.
- Profile files must be parsed safely (never `source`d) to prevent code injection from malicious profiles.
- The script must refuse to run as root and explain why.

## 🗣️ Communication rules

- If you hit a decision that's NOT covered in `IMPLEMENTATION_PLAN.md`, **stop and ask me** instead of guessing. Examples of things you should ask about:
  - Edge cases in OS detection (e.g., a weird Arch derivative)
  - Behavior when both `paru` and `yay` are installed
  - What to do if a package's upstream install method has changed since the plan was written
  - Anything that contradicts the plan
- If you find a bug or oversight in the plan itself, point it out before implementing a workaround.
- Keep summaries short. I want to see progress, not novels.

## 📦 What "done" looks like

When you finish, this directory should contain:

- `install.sh` — the complete, working tool (single file)
- `IMPLEMENTATION_PLAN.md` — all checkboxes marked `[x]` for completed work
- `README.md` — user-facing docs as specified in Phase 15
- `LICENSE` — MIT
- `.gitignore`
- `profiles/minimal.profile`, `profiles/fullstack.profile`, `profiles/ai-developer.profile`
- `test/Dockerfile.arch`, `test/Dockerfile.ubuntu`, `test/run-tests.sh`
- `.github/workflows/shellcheck.yml`

The Definition of Done in `IMPLEMENTATION_PLAN.md` (the final section) must be fully satisfied.

## 🚀 Start

Begin now with:

1. Confirm you've read `IMPLEMENTATION_PLAN.md`.
2. List the 17 phases briefly so I know we're aligned.
3. Then start Phase 0.

After each phase, pause and wait for me to say **"continue"** before moving to the next phase. This gives me checkpoints to review your work.

--- PROMPT END ---

---

## 💡 Tips for running this with Claude Code

### Setup
1. Create an empty folder: `mkdir devtool-installer && cd devtool-installer`
2. Drop `IMPLEMENTATION_PLAN.md` in that folder
3. Run `claude` to start Claude Code in that directory
4. Paste the prompt above as your first message

### During the build
- Claude Code will pause after each phase — **review the code before saying "continue"**
- If something looks off, push back: "That's not what the plan says — re-read Phase X"
- If you want to skip a phase temporarily, tell it: "Skip Phase 15 for now, mark it pending"

### After the build
- Run `shellcheck install.sh` yourself to verify quality
- Test with `./install.sh --dry-run` inside a Docker container first
- Only run for real on a fresh VM or test machine — never your daily driver

### If Claude Code goes off-track
Common save phrases:
- **"Stop. Re-read the plan."**
- **"That's not in the spec — remove it."**
- **"Ask me before making that decision."**
- **"Roll back the last change."**

---

## 🔑 Why this prompt works

- **References the plan file** instead of duplicating it — single source of truth
- **Phase-by-phase pacing** with explicit pause points so you stay in control
- **Quality bar baked in** so you don't get sloppy code
- **Safety rules** prevent it from nuking your system
- **Communication rules** force it to ask instead of hallucinate
- **No code examples** as you requested — the plan is the contract, Claude Code fills it in
