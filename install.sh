#!/usr/bin/env bash
# =============================================================================
# devtool-installer — One-shot dev environment bootstrapper
# License : MIT
# Version : 1.0.0
# Supports: Arch family (Arch, Manjaro, EndeavourOS)
#           Debian family (Ubuntu, Debian, Mint, Pop!_OS)
# Usage   : bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/devtool-installer/main/install.sh)
# =============================================================================

set -uo pipefail

# =============================================================================
# Section 1: Constants & Colors
# =============================================================================

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="devtool-installer"
LOG_FILE="/tmp/devtool-installer-$(date +%Y%m%d-%H%M%S).log"
PROFILE_PATH="${HOME}/.devtool-installer.profile"
SUDO_KEEPALIVE_PID=""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Runtime flags (set by CLI arg parser in main)
DRY_RUN=0
QUIET=0
VERBOSE=0
PROFILE_LOAD_PATH=""

# OS detection globals (populated by detect_os)
OS_FAMILY=""
OS_NAME=""
OS_VERSION=""
PM=""
AUR_HELPER=""

# Navigation state
CURRENT_STEP=0

# Selection arrays (populated by UI screens)
declare -a SELECTED_PKGS=()
PROFILE_SAVED=0

# Install result tracking
declare -a INSTALLED_PKGS=()
declare -a FAILED_PKGS=()
APT_UPDATED=0

# =============================================================================
# Section 2: Logging Helpers
# =============================================================================

# Write a timestamped info line to console and log file
log() {
    local msg="$1"
    if [[ "${QUIET}" -eq 0 ]]; then
        printf "${BLUE}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "${msg}" | tee -a "${LOG_FILE}"
    else
        printf "[%s] %s\n" "$(date +%H:%M:%S)" "${msg}" >> "${LOG_FILE}"
    fi
}

# Print a green success message
success() {
    local msg="$1"
    if [[ "${QUIET}" -eq 0 ]]; then
        printf "${GREEN}[✓]${NC} %s\n" "${msg}" | tee -a "${LOG_FILE}"
    else
        printf "[OK] %s\n" "${msg}" >> "${LOG_FILE}"
    fi
}

# Print a yellow warning message
warn() {
    local msg="$1"
    printf "${YELLOW}[!]${NC} %s\n" "${msg}" | tee -a "${LOG_FILE}"
}

# Print a red error message
err() {
    local msg="$1"
    printf "${RED}[✗]${NC} %s\n" "${msg}" | tee -a "${LOG_FILE}" >&2
}

# Print error message and exit with code 1
die() {
    local msg="$1"
    err "${msg}"
    exit 1
}

# Print debug output only in verbose mode
debug() {
    local msg="$1"
    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf "${CYAN}[DEBUG]${NC} %s\n" "${msg}" | tee -a "${LOG_FILE}"
    else
        printf "[DEBUG] %s\n" "${msg}" >> "${LOG_FILE}"
    fi
}

# =============================================================================
# Section 3: Pre-flight Checks
# =============================================================================

# Refuse to run as root; explain that sudo is invoked internally when needed
check_not_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        die "Do not run ${SCRIPT_NAME} as root. Run as a regular user — the script will invoke sudo when needed."
    fi
}

# Verify internet connectivity by probing GitHub
check_internet() {
    log "Checking internet connectivity..."
    if ! curl -s --head --max-time 10 https://github.com > /dev/null 2>&1; then
        die "No internet connection detected. Please connect to the internet and try again."
    fi
    success "Internet connectivity OK"
}

# Ensure whiptail is available; auto-install libnewt if missing
check_whiptail() {
    if ! command -v whiptail > /dev/null 2>&1; then
        warn "whiptail not found — attempting to install libnewt..."
        if [[ "${OS_FAMILY}" == "debian" ]]; then
            sudo apt-get install -y libnewt >> "${LOG_FILE}" 2>&1 || die "Failed to install whiptail (libnewt). Install it manually: sudo apt install libnewt"
        elif [[ "${OS_FAMILY}" == "arch" ]]; then
            sudo pacman -S --needed --noconfirm libnewt >> "${LOG_FILE}" 2>&1 || die "Failed to install whiptail (libnewt). Install it manually: sudo pacman -S libnewt"
        else
            die "whiptail is required but not installed. Install libnewt for your distribution."
        fi
    fi
    success "whiptail is available"
}

# Warn if free disk space in / is below 5 GB
check_disk_space() {
    local free_kb
    free_kb=$(df / | awk 'NR==2 {print $4}')
    local free_gb=$(( free_kb / 1024 / 1024 ))
    if [[ "${free_gb}" -lt 5 ]]; then
        warn "Low disk space: only ~${free_gb} GB free in /. Some installations may fail."
    else
        success "Disk space OK (${free_gb} GB free)"
    fi
}

# Validate that sudo is available and the user has access
check_sudo() {
    if ! sudo -v > /dev/null 2>&1; then
        die "sudo access required. Ensure your user is in the sudoers file."
    fi
    success "sudo access confirmed"
}

# Start a background loop that refreshes sudo every 50 seconds to prevent timeout
start_sudo_keepalive() {
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return
    fi
    (
        while true; do
            sudo -v
            sleep 50
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    debug "sudo keep-alive started (PID ${SUDO_KEEPALIVE_PID})"
}

# Kill the background sudo keep-alive process
stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" > /dev/null 2>&1 || true
        debug "sudo keep-alive stopped"
    fi
}

# Register cleanup trap to kill keep-alive and remove temp files on exit
setup_trap() {
    trap 'stop_sudo_keepalive; cleanup_temp' EXIT INT TERM
}

# Remove any temp files created by the script
cleanup_temp() {
    : # placeholder — extend if temp files are created during install
}

# Print a welcome banner with version and detected OS
print_banner() {
    if [[ "${QUIET}" -eq 1 ]]; then
        return
    fi
    printf "\n${BOLD}${CYAN}"
    printf "╔══════════════════════════════════════════╗\n"
    printf "║        devtool-installer  v%-13s║\n" "${SCRIPT_VERSION}"
    printf "║  One-shot dev environment bootstrapper  ║\n"
    printf "╚══════════════════════════════════════════╝\n"
    printf "${NC}\n"
    if [[ -n "${OS_NAME}" ]]; then
        log "Detected: ${OS_NAME} ${OS_VERSION} (${OS_FAMILY} family)"
    fi
}

# Run all pre-flight checks in order
preflight() {
    check_not_root
    check_internet
    check_disk_space
    check_sudo
    check_whiptail
    start_sudo_keepalive
}

# =============================================================================
# Section 4: OS Detection
# =============================================================================

# Parse /etc/os-release and set OS_FAMILY, OS_NAME, OS_VERSION, PM, AUR_HELPER
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        die "/etc/os-release not found. Cannot detect OS. Supported: Arch family, Debian family."
    fi

    local os_id=""
    local os_id_like=""
    local os_pretty=""
    local os_ver=""

    os_id=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    os_id_like=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    os_pretty=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    os_ver=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

    OS_NAME="${os_pretty:-${os_id}}"
    OS_VERSION="${os_ver:-}"

    # Determine OS family from ID or ID_LIKE
    if [[ "${os_id}" == "arch" ]] || echo "${os_id_like}" | grep -q "arch"; then
        OS_FAMILY="arch"
        PM="pacman"
        _detect_aur_helper
    elif [[ "${os_id}" == "debian" || "${os_id}" == "ubuntu" || "${os_id}" == "linuxmint" \
         || "${os_id}" == "pop" || "${os_id}" == "raspbian" ]] \
         || echo "${os_id_like}" | grep -qE "debian|ubuntu"; then
        OS_FAMILY="debian"
        PM="apt"
    else
        die "Unsupported OS: ${os_pretty}. ${SCRIPT_NAME} supports Arch family and Debian family only."
    fi

    debug "OS_FAMILY=${OS_FAMILY} PM=${PM} OS_VERSION=${OS_VERSION}"
}

# Detect which AUR helper is available (paru preferred over yay)
_detect_aur_helper() {
    if command -v paru > /dev/null 2>&1; then
        AUR_HELPER="paru"
    elif command -v yay > /dev/null 2>&1; then
        AUR_HELPER="yay"
    else
        AUR_HELPER=""
        debug "No AUR helper found — yay will be bootstrapped when first needed"
    fi
}

# =============================================================================
# Section 5: Package Definitions
# =============================================================================

# Package registry — each entry: "name|arch_spec|debian_spec|category|tag|deps|default_checked|size_mb"
# spec prefix: pacman: / yay: / apt: / script: / npm: / pip:
declare -A PKG_REGISTRY

# Register a package entry into PKG_REGISTRY with all metadata fields
_define_pkg() {
    local id="$1" name="$2" arch_spec="$3" debian_spec="$4"
    local category="$5" tag="$6" deps="$7" default_checked="$8" size_mb="$9"
    PKG_REGISTRY["${id}"]="${name}|${arch_spec}|${debian_spec}|${category}|${tag}|${deps}|${default_checked}|${size_mb}"
}

# ── System Essentials (pre-checked) ──────────────────────────────────────────
_define_pkg "git"         "Git"                  "pacman:git"              "apt:git"                  "essentials" ""  ""          1  50
_define_pkg "curl"        "cURL"                 "pacman:curl"             "apt:curl"                 "essentials" ""  ""          1  5
_define_pkg "wget"        "wget"                 "pacman:wget"             "apt:wget"                 "essentials" ""  ""          1  3
_define_pkg "unzip"       "unzip"                "pacman:unzip"            "apt:unzip"                "essentials" ""  ""          1  1
_define_pkg "build-tools" "Build Tools"          "pacman:base-devel"       "apt:build-essential"      "essentials" ""  ""          1  200
_define_pkg "openssh"     "OpenSSH"              "pacman:openssh"          "apt:openssh-client"       "essentials" ""  ""          1  10
_define_pkg "htop"        "htop"                 "pacman:htop"             "apt:htop"                 "essentials" ""  ""          1  2
_define_pkg "tree"        "tree"                 "pacman:tree"             "apt:tree"                 "essentials" ""  ""          1  1

# ── Dev Tools ────────────────────────────────────────────────────────────────
_define_pkg "nodejs"      "Node.js + npm"        "pacman:nodejs npm"       "script:install_nodejs"    "devtools"   ""  ""          0  120
_define_pkg "python"      "Python + pip"         "pacman:python python-pip" "apt:python3 python3-pip" "devtools"   ""  ""          0  80
_define_pkg "go"          "Go"                   "pacman:go"               "apt:golang-go"            "devtools"   ""  ""          0  500
_define_pkg "rust"        "Rust (rustup)"        "script:install_rustup"   "script:install_rustup"    "devtools"   ""  ""          0  700
_define_pkg "java"        "Java (OpenJDK 21)"    "pacman:jdk21-openjdk"    "apt:openjdk-21-jdk"       "devtools"   ""  ""          0  300
_define_pkg "docker"      "Docker + Compose"     "script:install_docker"   "script:install_docker"    "devtools"   ""  ""          0  400
_define_pkg "neovim"      "Neovim"               "pacman:neovim"           "apt:neovim"               "devtools"   ""  ""          0  20
_define_pkg "tmux"        "tmux"                 "pacman:tmux"             "apt:tmux"                 "devtools"   ""  ""          0  5
_define_pkg "zsh-omz"     "Zsh + Oh My Zsh"      "script:install_zsh_omz"  "script:install_zsh_omz"   "devtools"   ""  ""          0  30
_define_pkg "gh"          "GitHub CLI"           "pacman:github-cli"       "script:install_gh"        "devtools"   ""  ""          0  30
_define_pkg "lazygit"     "lazygit"              "pacman:lazygit"          "script:install_lazygit"   "devtools"   ""  ""          0  20
_define_pkg "starship"    "Starship Prompt"      "script:install_starship" "script:install_starship"  "devtools"   ""  ""          0  10
_define_pkg "make"        "make"                 "pacman:make"             "apt:make"                 "devtools"   ""  "build-tools" 0  2
_define_pkg "jq"          "jq"                   "pacman:jq"               "apt:jq"                   "devtools"   ""  ""          0  5
_define_pkg "fzf"         "fzf"                  "pacman:fzf"              "apt:fzf"                  "devtools"   ""  ""          0  5

# ── AI Tools ─────────────────────────────────────────────────────────────────
_define_pkg "ollama"        "Ollama"              "script:install_ollama"        "script:install_ollama"        "ai" "FREE"          ""       0  200
_define_pkg "claude-code"   "Claude Code"         "script:install_claude_code"   "script:install_claude_code"   "ai" "PAID"          "nodejs" 0  100
_define_pkg "gemini-cli"    "Gemini CLI"          "script:install_gemini_cli"    "script:install_gemini_cli"    "ai" "FREE"          "nodejs" 0  50
_define_pkg "copilot-cli"   "GitHub Copilot CLI"  "script:install_copilot_cli"   "script:install_copilot_cli"   "ai" "PAID"          "gh"     0  10
_define_pkg "cursor"        "Cursor"              "script:install_cursor"        "script:install_cursor"        "ai" "FREEMIUM"      ""       0  300
_define_pkg "aider"         "aider"               "script:install_aider"         "script:install_aider"         "ai" "BYO-API-KEY"   "python" 0  50
_define_pkg "continue-dev"  "Continue.dev"        "script:install_continue"      "script:install_continue"      "ai" "FREE"          "vscode" 0  20
_define_pkg "codex-cli"     "Codex CLI"           "script:install_codex_cli"     "script:install_codex_cli"     "ai" "PAID"          "nodejs" 0  30

# ── Other Tools ───────────────────────────────────────────────────────────────
_define_pkg "vscode"    "VS Code"     "yay:visual-studio-code-bin"  "script:install_vscode"           "other" ""  ""  0  300
_define_pkg "postman"   "Postman"     "yay:postman-bin"             "script:install_postman_snap"     "other" ""  ""  0  200
_define_pkg "bruno"     "Bruno"       "yay:bruno-bin"               "script:install_bruno"            "other" ""  ""  0  150
_define_pkg "obsidian"  "Obsidian"    "yay:obsidian"                "script:install_obsidian"         "other" ""  ""  0  200
_define_pkg "discord"   "Discord"     "pacman:discord"              "script:install_discord"          "other" ""  ""  0  300
_define_pkg "firefox"   "Firefox"     "pacman:firefox"              "apt:firefox"                     "other" ""  ""  0  250
_define_pkg "brave"     "Brave"       "yay:brave-bin"               "script:install_brave"            "other" ""  ""  0  250
_define_pkg "alacritty" "Alacritty"   "pacman:alacritty"            "apt:alacritty"                   "other" ""  ""  0  30
_define_pkg "slack"     "Slack"       "yay:slack-desktop"           "script:install_slack"            "other" ""  ""  0  300

# Return display name for a package ID
pkg_name() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f1
}

# Return arch spec for a package ID
pkg_arch_spec() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f2
}

# Return debian spec for a package ID
pkg_debian_spec() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f3
}

# Return category for a package ID
pkg_category() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f4
}

# Return pricing tag for a package ID
pkg_tag() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f5
}

# Return space-separated deps for a package ID
pkg_deps() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f6
}

# Return default_checked flag (1 or 0) for a package ID
pkg_default_checked() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f7
}

# Return estimated size in MB for a package ID
pkg_size_mb() {
    local id="$1"
    echo "${PKG_REGISTRY[${id}]}" | cut -d'|' -f8
}

# Return all package IDs in a given category
pkgs_in_category() {
    local cat="$1"
    for id in "${!PKG_REGISTRY[@]}"; do
        if [[ "$(pkg_category "${id}")" == "${cat}" ]]; then
            echo "${id}"
        fi
    done | sort
}

# =============================================================================
# Section 6: Profile Manager
# =============================================================================

# Write currently selected package IDs to ~/.devtool-installer.profile
save_profile() {
    local dest="${1:-${PROFILE_PATH}}"
    {
        echo "# devtool-installer profile — saved $(date)"
        for id in "${SELECTED_PKGS[@]}"; do
            echo "${id}"
        done
    } > "${dest}"
    success "Profile saved to ${dest}"
    PROFILE_SAVED=1
}

# Load package selections from a local profile file (never source — grep only)
load_profile_from_file() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        err "Profile file not found: ${path}"
        return 1
    fi
    SELECTED_PKGS=()
    while IFS= read -r line; do
        # Skip blank lines and comment lines
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        local id
        id=$(echo "${line}" | tr -d '[:space:]')
        if [[ -v "PKG_REGISTRY[${id}]" ]]; then
            SELECTED_PKGS+=("${id}")
        else
            warn "Unknown package ID '${id}' in profile — skipping"
        fi
    done < "${path}"
    success "Loaded ${#SELECTED_PKGS[@]} packages from profile: ${path}"
}

# Download a remote profile URL and load it (curl only — never eval/source)
load_profile_from_url() {
    local url="$1"
    local tmp_file
    tmp_file=$(mktemp /tmp/devtool-profile-XXXXXX.profile)
    log "Fetching profile from ${url}..."
    if ! curl -fsSL --max-time 15 "${url}" -o "${tmp_file}" 2>> "${LOG_FILE}"; then
        rm -f "${tmp_file}"
        err "Failed to download profile from ${url}"
        return 1
    fi
    load_profile_from_file "${tmp_file}"
    rm -f "${tmp_file}"
}

# Check if a package ID is in the current selection
is_selected() {
    local id="$1"
    for sel in "${SELECTED_PKGS[@]}"; do
        [[ "${sel}" == "${id}" ]] && return 0
    done
    return 1
}

# Add a package ID to selection (idempotent)
select_pkg() {
    local id="$1"
    is_selected "${id}" || SELECTED_PKGS+=("${id}")
}

# Remove a package ID from selection
deselect_pkg() {
    local id="$1"
    local new=()
    for sel in "${SELECTED_PKGS[@]}"; do
        [[ "${sel}" != "${id}" ]] && new+=("${sel}")
    done
    SELECTED_PKGS=("${new[@]+"${new[@]}"}")
}

# =============================================================================
# Section 7: Whiptail UI Screens
# =============================================================================

# Terminal dimensions
_TERM_H=0
_TERM_W=0

# Refresh terminal dimensions before each whiptail call
_refresh_term_size() {
    _TERM_H=$(tput lines 2>/dev/null || echo 24)
    _TERM_W=$(tput cols  2>/dev/null || echo 80)
}

# Show welcome screen; returns 0=OK 1=Cancel/Esc
screen_welcome() {
    _refresh_term_size
    local h=$(( _TERM_H - 4 ))
    local w=$(( _TERM_W - 10 ))
    [[ "${h}" -lt 15 ]] && h=15
    [[ "${w}" -lt 60 ]] && w=60

    whiptail --title " ${SCRIPT_NAME} v${SCRIPT_VERSION} " \
        --msgbox "\nWelcome to devtool-installer!\n\nDetected: ${OS_NAME} ${OS_VERSION} (${OS_FAMILY} family)\n\nThis tool will guide you through installing your\npreferred development tools in 4 easy steps:\n\n  Step 1 — System Essentials\n  Step 2 — Dev Tools\n  Step 3 — AI Tools\n  Step 4 — Other Tools\n\nPress OK to begin." \
        "${h}" "${w}" 3>&1 1>&2 2>&3
    return $?
}

# Ask the user how to start: fresh / load local file / load URL
# Sets PROFILE_LOAD_PATH="" / local path / "URL:..."
# Returns 0=fresh 1=load file 2=load url 255=esc
screen_profile_choice() {
    _refresh_term_size
    local h=$(( _TERM_H - 4 ))
    local w=$(( _TERM_W - 10 ))
    [[ "${h}" -lt 12 ]] && h=12
    [[ "${w}" -lt 60 ]] && w=60

    local choice
    choice=$(whiptail --title " Profile " \
        --menu "How would you like to start?" \
        "${h}" "${w}" 3 \
        "fresh"    "Start fresh (manual selection)" \
        "file"     "Load a local .profile file" \
        "url"      "Load a profile from a URL" \
        3>&1 1>&2 2>&3)
    local ret=$?
    [[ "${ret}" -ne 0 ]] && return 255

    case "${choice}" in
        file)
            local path
            path=$(whiptail --title " Load Profile " --inputbox \
                "Enter path to .profile file:" 10 60 "${HOME}/.devtool-installer.profile" \
                3>&1 1>&2 2>&3) || return 255
            PROFILE_LOAD_PATH="${path}"
            load_profile_from_file "${path}" || true
            return 1
            ;;
        url)
            local url
            url=$(whiptail --title " Load Profile URL " --inputbox \
                "Enter profile URL (e.g., https://gist.github.com/...):" 10 70 \
                3>&1 1>&2 2>&3) || return 255
            PROFILE_LOAD_PATH="URL:${url}"
            load_profile_from_url "${url}" || true
            return 2
            ;;
        *)
            return 0
            ;;
    esac
}

# Build a whiptail checklist for a given category; preserves existing selections
# $1=category $2=step_title; returns 0=OK 1=Back 255=Esc
_screen_checklist() {
    local category="$1"
    local step_title="$2"
    _refresh_term_size
    local h=$(( _TERM_H - 4 ))
    local w=$(( _TERM_W - 6 ))
    [[ "${h}" -lt 16 ]] && h=16
    [[ "${w}" -lt 72 ]] && w=72
    local list_h=$(( h - 8 ))

    # Count already selected in this category
    local selected_count=0
    for id in $(pkgs_in_category "${category}"); do
        is_selected "${id}" && (( selected_count++ )) || true
    done

    local title="${step_title} (${selected_count} selected)"

    # Build whiptail item list
    local items=()
    for id in $(pkgs_in_category "${category}"); do
        local name tag label state
        name=$(pkg_name "${id}")
        tag=$(pkg_tag "${id}")
        [[ -n "${tag}" ]] && label="${name}  [${tag}]" || label="${name}"
        if is_selected "${id}"; then
            state="ON"
        elif [[ "$(pkg_default_checked "${id}")" == "1" ]]; then
            state="ON"
        else
            state="OFF"
        fi
        items+=("${id}" "${label}" "${state}")
    done

    local result
    result=$(whiptail --title " ${title} " \
        --separate-output \
        --checklist "Space=toggle  Enter=OK  ESC=quit" \
        "${h}" "${w}" "${list_h}" \
        "${items[@]}" \
        3>&1 1>&2 2>&3)
    local ret=$?

    if [[ "${ret}" -eq 255 ]]; then
        return 255
    fi
    if [[ "${ret}" -ne 0 ]]; then
        return 1
    fi

    # Deselect all in category, then re-select from result
    for id in $(pkgs_in_category "${category}"); do
        deselect_pkg "${id}"
    done
    while IFS= read -r id; do
        [[ -n "${id}" ]] && select_pkg "${id}"
    done <<< "${result}"

    return 0
}

# Step 1: system essentials checklist
screen_essentials() {
    _screen_checklist "essentials" "Step 1 — System Essentials"
}

# Step 2: dev tools checklist
screen_devtools() {
    _screen_checklist "devtools" "Step 2 — Dev Tools"
}

# Step 3: AI tools checklist
screen_ai_tools() {
    _screen_checklist "ai" "Step 3 — AI Tools"
}

# Step 4: other tools checklist
screen_other() {
    _screen_checklist "other" "Step 4 — Other Tools"
}

# Show review screen: summary of selected packages and total size estimate
# Returns 0=Install 1=Back 255=Esc
screen_review() {
    _refresh_term_size
    local h=$(( _TERM_H - 4 ))
    local w=$(( _TERM_W - 6 ))
    [[ "${h}" -lt 16 ]] && h=16
    [[ "${w}" -lt 72 ]] && w=72

    if [[ "${#SELECTED_PKGS[@]}" -eq 0 ]]; then
        whiptail --title " Review " --msgbox \
            "No packages selected. Go back and select at least one package." \
            10 60
        return 1
    fi

    local total_mb=0
    local pkg_list=""
    for id in "${SELECTED_PKGS[@]}"; do
        local name tag
        name=$(pkg_name "${id}")
        tag=$(pkg_tag "${id}")
        local mb
        mb=$(pkg_size_mb "${id}")
        total_mb=$(( total_mb + mb ))
        [[ -n "${tag}" ]] && pkg_list+="  • ${name}  [${tag}]\n" || pkg_list+="  • ${name}\n"
    done

    local body="Selected packages (${#SELECTED_PKGS[@]}), estimated ~${total_mb} MB:\n\n${pkg_list}\nProceed with installation?"

    whiptail --title " Review & Confirm " \
        --yesno "${body}" \
        "${h}" "${w}" \
        --yes-button "Install" --no-button "Back" \
        3>&1 1>&2 2>&3
    local ret=$?

    if [[ "${ret}" -eq 0 ]]; then
        # Offer to save profile
        if whiptail --title " Save Profile " \
            --yesno "Save your selections as a profile for future use?" \
            8 60 3>&1 1>&2 2>&3; then
            save_profile
        fi
        return 0
    elif [[ "${ret}" -eq 255 ]]; then
        return 255
    else
        return 1
    fi
}

# Show a whiptail gauge that advances as packages are installed
# Called with a named pipe; the install engine writes progress percentages to it
screen_progress() {
    local total="$1"
    local current=0
    local pct=0
    local id=""

    {
        while IFS=: read -r action data; do
            case "${action}" in
                PKG)    id="${data}" ;;
                DONE)   (( current++ )) || true
                        pct=$(( current * 100 / total ))
                        echo "${pct}"
                        ;;
                FINISH) echo 100; break ;;
            esac
        done
    } | whiptail --title " Installing " \
        --gauge "Installing ${total} packages..." \
        8 70 0
}

# Show final summary screen (text-only, no whiptail — called after terminal is restored)
screen_summary() {
    printf "\n${BOLD}${CYAN}══ Installation Complete ══${NC}\n\n"
    success "${#INSTALLED_PKGS[@]} package(s) installed successfully"
    if [[ "${#FAILED_PKGS[@]}" -gt 0 ]]; then
        err "${#FAILED_PKGS[@]} package(s) failed:"
        for entry in "${FAILED_PKGS[@]}"; do
            printf "  ${RED}✗${NC}  %s\n" "${entry}"
        done
    fi
    printf "\n"
    log "Log file: ${LOG_FILE}"
    if [[ "${PROFILE_SAVED}" -eq 1 ]]; then
        log "Profile:  ${PROFILE_PATH}"
    fi
}

# Ask for quit confirmation; returns 0 if user confirms quit
screen_confirm_quit() {
    whiptail --title " Quit " \
        --yesno "Are you sure you want to quit?" \
        8 40 3>&1 1>&2 2>&3
}

# =============================================================================
# Section 8: Navigation Loop
# =============================================================================

# Pre-select all default_checked packages at startup
_preselect_defaults() {
    for id in "${!PKG_REGISTRY[@]}"; do
        if [[ "$(pkg_default_checked "${id}")" == "1" ]]; then
            select_pkg "${id}"
        fi
    done
}

# Main navigation loop: drives the user through all screens using current_step
run_navigation_loop() {
    _preselect_defaults
    CURRENT_STEP=0

    while true; do
        local ret=0
        case "${CURRENT_STEP}" in
            0)  # Welcome
                screen_welcome
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                else
                    CURRENT_STEP=1
                fi
                ;;
            1)  # Profile choice
                screen_profile_choice
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                else
                    CURRENT_STEP=2
                fi
                ;;
            2)  # Essentials
                screen_essentials
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                elif [[ "${ret}" -eq 1 ]]; then
                    CURRENT_STEP=1
                else
                    CURRENT_STEP=3
                fi
                ;;
            3)  # Dev tools
                screen_devtools
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                elif [[ "${ret}" -eq 1 ]]; then
                    CURRENT_STEP=2
                else
                    CURRENT_STEP=4
                fi
                ;;
            4)  # AI tools
                screen_ai_tools
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                elif [[ "${ret}" -eq 1 ]]; then
                    CURRENT_STEP=3
                else
                    CURRENT_STEP=5
                fi
                ;;
            5)  # Other tools
                screen_other
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                elif [[ "${ret}" -eq 1 ]]; then
                    CURRENT_STEP=4
                else
                    CURRENT_STEP=6
                fi
                ;;
            6)  # Review
                screen_review
                ret=$?
                if [[ "${ret}" -eq 255 ]]; then
                    screen_confirm_quit && exit 0
                elif [[ "${ret}" -eq 1 ]]; then
                    CURRENT_STEP=5
                else
                    CURRENT_STEP=7
                fi
                ;;
            7)  # Install
                return 0
                ;;
        esac
    done
}

# =============================================================================
# Section 9: Install Engine
# =============================================================================

# Walk selection list and auto-add any missing dependency packages
resolve_dependencies() {
    local added=1
    while [[ "${added}" -eq 1 ]]; do
        added=0
        for id in "${SELECTED_PKGS[@]}"; do
            local deps
            deps=$(pkg_deps "${id}")
            for dep in ${deps}; do
                if [[ -v "PKG_REGISTRY[${dep}]" ]] && ! is_selected "${dep}"; then
                    warn "Auto-adding dependency '$(pkg_name "${dep}")' required by '$(pkg_name "${id}")'"
                    select_pkg "${dep}"
                    added=1
                fi
            done
        done
    done
}

# Run a shell command, or in dry-run mode just log it
_run_cmd() {
    local cmd="$@"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[DRY-RUN] Would run: ${cmd}"
        return 0
    fi
    debug "Running: ${cmd}"
    eval "${cmd}" >> "${LOG_FILE}" 2>&1
    return $?
}

# Run a sudo command, respecting dry-run mode
_run_sudo() {
    local cmd="$@"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        log "[DRY-RUN] Would run: sudo ${cmd}"
        return 0
    fi
    debug "Running: sudo ${cmd}"
    sudo sh -c "${cmd}" >> "${LOG_FILE}" 2>&1
    return $?
}

# Run apt update once per session before first apt install
_ensure_apt_updated() {
    if [[ "${APT_UPDATED}" -eq 0 ]]; then
        log "Updating apt package index..."
        _run_sudo "apt-get update -qq"
        APT_UPDATED=1
    fi
}

# Install a package via pacman
pkg_install_pacman() {
    local packages="$1"
    _run_sudo "pacman -S --needed --noconfirm ${packages}"
}

# Install a package via apt
pkg_install_apt() {
    local packages="$1"
    _ensure_apt_updated
    _run_sudo "apt-get install -y ${packages}"
}

# Install a package via AUR helper (bootstraps yay if none present)
pkg_install_yay() {
    local packages="$1"
    ensure_yay
    _run_cmd "${AUR_HELPER} -S --needed --noconfirm ${packages}"
}

# Bootstrap yay from AUR if no AUR helper is available
ensure_yay() {
    if [[ -n "${AUR_HELPER}" ]]; then
        return 0
    fi
    log "Bootstrapping yay AUR helper..."
    local build_dir="/tmp/yay-bootstrap-$$"
    _run_cmd "git clone https://aur.archlinux.org/yay.git ${build_dir}"
    if [[ "${DRY_RUN}" -eq 0 ]]; then
        (cd "${build_dir}" && makepkg -si --noconfirm) >> "${LOG_FILE}" 2>&1 || {
            err "Failed to build yay from AUR"
            rm -rf "${build_dir}"
            return 1
        }
        rm -rf "${build_dir}"
    fi
    AUR_HELPER="yay"
    success "yay installed"
}

# Main package installer dispatcher — reads spec prefix and routes accordingly
pkg_install() {
    local id="$1"
    local spec
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        spec=$(pkg_arch_spec "${id}")
    else
        spec=$(pkg_debian_spec "${id}")
    fi

    local prefix="${spec%%:*}"
    local value="${spec#*:}"

    case "${prefix}" in
        pacman)  pkg_install_pacman "${value}" ;;
        apt)     pkg_install_apt "${value}" ;;
        yay)     pkg_install_yay "${value}" ;;
        script)  "${value}" ;;
        npm)     _run_cmd "npm install -g ${value}" ;;
        pip)     _run_cmd "pip3 install --user ${value}" ;;
        *)       err "Unknown install spec prefix '${prefix}' for package '${id}'"; return 1 ;;
    esac
}

# Install all selected packages, tracking success/failure; updates progress pipe if provided
run_install_engine() {
    local total="${#SELECTED_PKGS[@]}"
    local progress_fd="${1:-}"

    resolve_dependencies
    total="${#SELECTED_PKGS[@]}"

    log "Starting installation of ${total} package(s)..."

    local i=0
    for id in "${SELECTED_PKGS[@]}"; do
        (( i++ )) || true
        local name
        name=$(pkg_name "${id}")
        log "Installing [${i}/${total}]: ${name}..."

        [[ -n "${progress_fd}" ]] && echo "PKG:${name}" >&"${progress_fd}" || true

        local attempts=0
        local success_flag=0
        while [[ "${attempts}" -lt 2 ]]; do
            if pkg_install "${id}"; then
                success_flag=1
                break
            else
                (( attempts++ )) || true
                if [[ "${attempts}" -lt 2 ]]; then
                    warn "Install of '${name}' failed — retrying..."
                fi
            fi
        done

        if [[ "${success_flag}" -eq 1 ]]; then
            success "${name} installed"
            INSTALLED_PKGS+=("${id}")
        else
            err "${name} failed to install"
            FAILED_PKGS+=("${id} — install failed")
        fi

        [[ -n "${progress_fd}" ]] && echo "DONE:${name}" >&"${progress_fd}" || true
    done

    [[ -n "${progress_fd}" ]] && echo "FINISH:" >&"${progress_fd}" || true
    run_post_install_hooks
}

# =============================================================================
# Section 10: Custom Installer Functions
# =============================================================================

# Install Node.js via NodeSource on Debian, pacman on Arch
install_nodejs() {
    if command -v node > /dev/null 2>&1; then
        success "Node.js is already installed ($(node --version)) — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "nodejs npm"
    else
        log "Installing Node.js via NodeSource..."
        _run_cmd "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
        pkg_install_apt "nodejs"
    fi
}

# Install Rust via rustup (official installer)
install_rustup() {
    if command -v rustc > /dev/null 2>&1; then
        success "Rust is already installed ($(rustc --version)) — skipping"
        return 0
    fi
    log "Installing Rust via rustup..."
    _run_cmd "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
}

# Install Docker via official Docker repository on Debian; pacman on Arch
install_docker() {
    if command -v docker > /dev/null 2>&1; then
        success "Docker is already installed ($(docker --version 2>/dev/null | head -1)) — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "docker docker-compose"
    else
        log "Installing Docker via official Docker apt repo..."
        _ensure_apt_updated
        _run_sudo "apt-get install -y ca-certificates gnupg"
        _run_cmd "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
        local arch
        arch=$(dpkg --print-architecture 2>/dev/null || echo amd64)
        local codename
        codename=$(grep -E '^(UBUNTU_CODENAME|VERSION_CODENAME)=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
        _run_sudo "echo \"deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable\" > /etc/apt/sources.list.d/docker.list"
        APT_UPDATED=0
        _ensure_apt_updated
        _run_sudo "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    fi
}

# Install Zsh and oh-my-zsh (non-interactive)
install_zsh_omz() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "zsh"
    else
        pkg_install_apt "zsh"
    fi
    log "Installing oh-my-zsh..."
    if [[ "${DRY_RUN}" -eq 0 ]] && [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
        _run_cmd "RUNZSH=no CHSH=no curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | bash"
    else
        log "[DRY-RUN] Would install oh-my-zsh"
    fi
}

# Install GitHub CLI via official apt repo on Debian; pacman on Arch
install_gh() {
    if command -v gh > /dev/null 2>&1; then
        success "GitHub CLI is already installed ($(gh --version 2>/dev/null | head -1)) — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "github-cli"
    else
        log "Installing GitHub CLI via official repo..."
        _run_cmd "curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg"
        _run_sudo "chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg"
        _run_sudo "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" > /etc/apt/sources.list.d/github-cli.list"
        APT_UPDATED=0
        _ensure_apt_updated
        pkg_install_apt "gh"
    fi
}

# Install lazygit via pre-built binary on Debian; pacman on Arch
install_lazygit() {
    if command -v lazygit > /dev/null 2>&1; then
        success "lazygit is already installed — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "lazygit"
    else
        log "Installing lazygit..."
        local version
        version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
        _run_cmd "curl -fsSL \"https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_x86_64.tar.gz\" | sudo tar xz -C /usr/local/bin lazygit"
    fi
}

# Install Starship prompt via official install script
install_starship() {
    if command -v starship > /dev/null 2>&1; then
        success "Starship is already installed ($(starship --version 2>/dev/null | head -1)) — skipping"
        return 0
    fi
    log "Installing Starship prompt..."
    _run_cmd "curl -sS https://starship.rs/install.sh | sh -s -- --yes"
}

# Install Ollama via official install script
install_ollama() {
    if command -v ollama > /dev/null 2>&1; then
        success "Ollama is already installed — skipping"
        return 0
    fi
    log "Installing Ollama..."
    _run_cmd "curl -fsSL https://ollama.com/install.sh | sh"
}

# Install Claude Code via official npm package
install_claude_code() {
    log "Installing Claude Code..."
    _run_cmd "npm install -g @anthropic-ai/claude-code"
}

# Install Gemini CLI via npm
install_gemini_cli() {
    log "Installing Gemini CLI..."
    _run_cmd "npm install -g @google/gemini-cli"
}

# Install GitHub Copilot CLI via gh extension
install_copilot_cli() {
    log "Installing GitHub Copilot CLI..."
    _run_cmd "gh extension install github/gh-copilot"
}

# Install Cursor AppImage on Debian; yay on Arch
install_cursor() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "cursor-bin"
    else
        log "Installing Cursor (AppImage)..."
        local appimg_dir="${HOME}/.local/bin"
        _run_cmd "mkdir -p ${appimg_dir}"
        _run_cmd "curl -fsSL 'https://downloader.cursor.sh/linux/appImage/x64' -o '${appimg_dir}/cursor.AppImage'"
        _run_cmd "chmod +x '${appimg_dir}/cursor.AppImage'"
        success "Cursor AppImage saved to ${appimg_dir}/cursor.AppImage"
    fi
}

# Install aider via pip
install_aider() {
    log "Installing aider..."
    _run_cmd "pip3 install --user aider-chat"
}

# Install Continue.dev VS Code extension
install_continue() {
    log "Installing Continue.dev VS Code extension..."
    _run_cmd "code --install-extension Continue.continue"
}

# Install Codex CLI via npm
install_codex_cli() {
    log "Installing Codex CLI..."
    _run_cmd "npm install -g @openai/codex"
}

# Install VS Code via Microsoft apt repo on Debian; yay on Arch
install_vscode() {
    if command -v code > /dev/null 2>&1; then
        success "VS Code is already installed — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "visual-studio-code-bin"
    else
        log "Installing VS Code via Microsoft repo..."
        _run_cmd "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg"
        _run_sudo "echo \"deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main\" > /etc/apt/sources.list.d/vscode.list"
        APT_UPDATED=0
        _ensure_apt_updated
        pkg_install_apt "code"
    fi
}

# Install Postman via snap on Debian; yay on Arch
install_postman_snap() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "postman-bin"
    else
        log "Installing Postman via snap..."
        _run_sudo "snap install postman"
    fi
}

# Install Bruno via .deb download on Debian; yay on Arch
install_bruno() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "bruno-bin"
    else
        log "Installing Bruno..."
        local version="1.38.1"
        local deb_url="https://github.com/usebruno/bruno/releases/download/v${version}/bruno_${version}_amd64_linux.deb"
        local tmp_deb="/tmp/bruno-$$.deb"
        _run_cmd "curl -fsSL '${deb_url}' -o '${tmp_deb}'"
        _run_sudo "dpkg -i '${tmp_deb}'"
        _run_cmd "rm -f '${tmp_deb}'"
    fi
}

# Install Obsidian via .deb download on Debian; yay on Arch
install_obsidian() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "obsidian"
    else
        log "Installing Obsidian..."
        local version
        version=$(curl -s "https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest" | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
        local deb_url="https://github.com/obsidianmd/obsidian-releases/releases/download/v${version}/obsidian_${version}_amd64.deb"
        local tmp_deb="/tmp/obsidian-$$.deb"
        _run_cmd "curl -fsSL '${deb_url}' -o '${tmp_deb}'"
        _run_sudo "dpkg -i '${tmp_deb}'"
        _run_cmd "rm -f '${tmp_deb}'"
    fi
}

# Install Discord via .deb download on Debian; pacman on Arch
install_discord() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_pacman "discord"
    else
        log "Installing Discord..."
        local tmp_deb="/tmp/discord-$$.deb"
        _run_cmd "curl -fsSL 'https://discord.com/api/download?platform=linux&format=deb' -o '${tmp_deb}'"
        _run_sudo "dpkg -i '${tmp_deb}'"
        _run_cmd "rm -f '${tmp_deb}'"
    fi
}

# Install Brave via official apt repo on Debian; yay on Arch
install_brave() {
    if command -v brave-browser > /dev/null 2>&1 || command -v brave > /dev/null 2>&1; then
        success "Brave is already installed — skipping"
        return 0
    fi
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "brave-bin"
    else
        log "Installing Brave..."
        _run_sudo "apt-get install -y apt-transport-https curl"
        _run_cmd "curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | sudo tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null"
        _run_sudo "echo \"deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main\" > /etc/apt/sources.list.d/brave-browser-release.list"
        APT_UPDATED=0
        _ensure_apt_updated
        pkg_install_apt "brave-browser"
    fi
}

# Install Slack via .deb download on Debian; yay on Arch
install_slack() {
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        pkg_install_yay "slack-desktop"
    else
        log "Installing Slack..."
        local version="4.38.125"
        local deb_url="https://downloads.slack-edge.com/desktop-releases/linux/x64/${version}/slack-desktop-${version}-amd64.deb"
        local tmp_deb="/tmp/slack-$$.deb"
        _run_cmd "curl -fsSL '${deb_url}' -o '${tmp_deb}'"
        _run_sudo "dpkg -i '${tmp_deb}'"
        _run_cmd "rm -f '${tmp_deb}'"
    fi
}

# =============================================================================
# Section 11: Post-Install Hooks
# =============================================================================

# Add user to docker group and enable docker.service
hook_docker() {
    log "Configuring Docker post-install..."
    _run_sudo "usermod -aG docker ${USER}"
    _run_sudo "systemctl enable --now docker.service"
    warn "You must log out and back in (or run 'newgrp docker') for Docker group to take effect."
}

# Ensure postgres cluster is initialized and service is enabled
hook_postgres() {
    log "Configuring PostgreSQL post-install..."
    if [[ "${OS_FAMILY}" == "arch" ]]; then
        _run_cmd "sudo -u postgres initdb -D /var/lib/postgres/data"
        _run_sudo "systemctl enable --now postgresql.service"
    else
        _run_sudo "systemctl enable --now postgresql"
    fi
}

# Offer to change default shell to zsh
hook_zsh() {
    local zsh_path
    zsh_path=$(command -v zsh 2>/dev/null || echo "")
    if [[ -z "${zsh_path}" ]]; then
        return
    fi
    if [[ "${SHELL}" != "${zsh_path}" ]]; then
        if [[ "${DRY_RUN}" -eq 0 ]]; then
            if whiptail --title " Shell " --yesno \
                "Set zsh as your default shell?\n\nCurrent shell: ${SHELL}" \
                10 50 3>&1 1>&2 2>&3; then
                _run_cmd "chsh -s '${zsh_path}'"
                success "Default shell changed to zsh (takes effect on next login)"
            fi
        else
            log "[DRY-RUN] Would offer to change shell to ${zsh_path}"
        fi
    fi
}

# Append NVM_DIR initialization lines to shell rc files
hook_nvm() {
    local nvm_line='export NVM_DIR="$HOME/.nvm"'
    local nvm_source='[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [[ -f "${rc}" ]] && ! grep -qF 'NVM_DIR' "${rc}"; then
            if [[ "${DRY_RUN}" -eq 0 ]]; then
                printf "\n%s\n%s\n" "${nvm_line}" "${nvm_source}" >> "${rc}"
                success "Added NVM init to ${rc}"
            else
                log "[DRY-RUN] Would add NVM init to ${rc}"
            fi
        fi
    done
}

# Append cargo env source line to shell rc files
hook_rustup() {
    local cargo_line='source "$HOME/.cargo/env"'
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [[ -f "${rc}" ]] && ! grep -qF '.cargo/env' "${rc}"; then
            if [[ "${DRY_RUN}" -eq 0 ]]; then
                printf "\n%s\n" "${cargo_line}" >> "${rc}"
                success "Added cargo env to ${rc}"
            else
                log "[DRY-RUN] Would add cargo env to ${rc}"
            fi
        fi
    done
}

# Add Go binary path to shell rc files
hook_go() {
    local go_line='export PATH="$PATH:$HOME/go/bin"'
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [[ -f "${rc}" ]] && ! grep -qF 'go/bin' "${rc}"; then
            if [[ "${DRY_RUN}" -eq 0 ]]; then
                printf "\n%s\n" "${go_line}" >> "${rc}"
                success "Added ~/go/bin to PATH in ${rc}"
            else
                log "[DRY-RUN] Would add ~/go/bin to PATH in ${rc}"
            fi
        fi
    done
}

# Set JAVA_HOME in shell rc files
hook_java() {
    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java 2>/dev/null || echo "")")")" 2>/dev/null || echo "")
    if [[ -z "${java_home}" ]]; then
        return
    fi
    local java_line="export JAVA_HOME=${java_home}"
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [[ -f "${rc}" ]] && ! grep -qF 'JAVA_HOME' "${rc}"; then
            if [[ "${DRY_RUN}" -eq 0 ]]; then
                printf "\n%s\n" "${java_line}" >> "${rc}"
                success "Added JAVA_HOME to ${rc}"
            else
                log "[DRY-RUN] Would add JAVA_HOME to ${rc}"
            fi
        fi
    done
}

# Add starship init line to shell rc files
hook_starship() {
    for rc_pair in "${HOME}/.bashrc:bash" "${HOME}/.zshrc:zsh"; do
        local rc="${rc_pair%%:*}"
        local shell="${rc_pair##*:}"
        if [[ -f "${rc}" ]] && ! grep -qF 'starship init' "${rc}"; then
            if [[ "${DRY_RUN}" -eq 0 ]]; then
                printf '\neval "$(starship init %s)"\n' "${shell}" >> "${rc}"
                success "Added starship init to ${rc}"
            else
                log "[DRY-RUN] Would add starship init to ${rc}"
            fi
        fi
    done
}

# Run fzf keybindings install script
hook_fzf() {
    local fzf_install="${HOME}/.fzf/install"
    if [[ -x "${fzf_install}" ]]; then
        _run_cmd "${fzf_install} --all --no-update-rc"
    fi
}

# Dispatch post-install hooks for all installed packages
run_post_install_hooks() {
    log "Running post-install hooks..."
    local needs_relogin=0

    for id in "${INSTALLED_PKGS[@]}"; do
        case "${id}" in
            docker)     hook_docker;  needs_relogin=1 ;;
            zsh-omz)    hook_zsh ;;
            rust)       hook_rustup ;;
            go)         hook_go ;;
            java)       hook_java ;;
            starship)   hook_starship ;;
            fzf)        hook_fzf ;;
        esac
    done

    if [[ "${needs_relogin}" -eq 1 ]]; then
        warn "IMPORTANT: Log out and back in for group membership changes to take effect."
    fi
}

# =============================================================================
# Section 12: Summary & Cleanup
# =============================================================================

# Print the final installation summary to console
print_summary() {
    screen_summary

    if [[ "${#FAILED_PKGS[@]}" -gt 0 ]]; then
        printf "\n${YELLOW}Suggested fixes:${NC}\n"
        printf "  • Check %s for details\n" "${LOG_FILE}"
        printf "  • Re-run the script with just the failed packages\n"
    fi

    printf "\n${BOLD}Next steps:${NC}\n"
    printf "  source ~/.bashrc   # reload shell config\n"
    if is_selected "docker"; then
        printf "  docker run hello-world   # verify Docker works\n"
    fi
    printf "\n"
}

# Final cleanup: kill keep-alive, remove temp files
do_cleanup() {
    stop_sudo_keepalive
    cleanup_temp
}

# =============================================================================
# Section 13: Main Entry Point
# =============================================================================

# Print usage information
usage() {
    printf "Usage: %s [OPTIONS]\n\n" "${SCRIPT_NAME}"
    printf "Options:\n"
    printf "  --dry-run           Preview all actions without executing them\n"
    printf "  --profile <path>    Load a profile file or URL (non-interactive)\n"
    printf "  --quiet             Suppress non-essential output\n"
    printf "  --verbose           Show extra debug output\n"
    printf "  --help              Show this help message\n"
    printf "  --version           Show script version\n"
}

# Parse command-line flags and set global variables accordingly
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                ;;
            --quiet)
                QUIET=1
                ;;
            --verbose)
                VERBOSE=1
                ;;
            --profile)
                [[ $# -lt 2 ]] && die "--profile requires a path or URL argument"
                PROFILE_LOAD_PATH="$2"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --version|-v)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done
}

# Script entry point
main() {
    parse_args "$@"
    setup_trap

    # Initialise log file
    touch "${LOG_FILE}"

    detect_os
    print_banner

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        warn "DRY-RUN mode enabled — no changes will be made to your system."
    fi

    preflight

    # If --profile was given, load it and skip interactive UI
    if [[ -n "${PROFILE_LOAD_PATH}" ]]; then
        if [[ "${PROFILE_LOAD_PATH}" == http* ]]; then
            load_profile_from_url "${PROFILE_LOAD_PATH}"
        else
            load_profile_from_file "${PROFILE_LOAD_PATH}"
        fi
        if [[ "${#SELECTED_PKGS[@]}" -eq 0 ]]; then
            die "Profile loaded but no valid packages found."
        fi
        log "Non-interactive install: ${#SELECTED_PKGS[@]} package(s) from profile"
    else
        run_navigation_loop
    fi

    run_install_engine

    print_summary
    do_cleanup

    if [[ "${#FAILED_PKGS[@]}" -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
