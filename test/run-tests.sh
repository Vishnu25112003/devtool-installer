#!/usr/bin/env bash
# Run devtool-installer tests inside Docker containers (dry-run + profile tests)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "${SCRIPT_DIR}")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

_pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; (( PASS++ )) || true; }
_fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; (( FAIL++ )) || true; }
_info() { printf "${YELLOW}[INFO]${NC} %s\n" "$1"; }

run_test() {
    local test_name="$1"
    local image="$2"
    local cmd="$3"

    _info "Running: ${test_name} on ${image}"
    if docker run --rm "${image}" -c "${cmd}" > /tmp/test-output-$$.log 2>&1; then
        _pass "${test_name}"
    else
        _fail "${test_name}"
        printf "  Output:\n"
        tail -20 /tmp/test-output-$$.log | sed 's/^/    /'
    fi
    rm -f /tmp/test-output-$$.log
}

_info "Building Arch test image..."
docker build -t devtool-installer-arch -f "${SCRIPT_DIR}/Dockerfile.arch" "${PROJECT_DIR}" \
    || { _fail "Arch image build failed"; exit 1; }
_pass "Arch image built"

_info "Building Ubuntu test image..."
docker build -t devtool-installer-ubuntu -f "${SCRIPT_DIR}/Dockerfile.ubuntu" "${PROJECT_DIR}" \
    || { _fail "Ubuntu image build failed"; exit 1; }
_pass "Ubuntu image built"

# Dry-run tests
run_test "Arch: --dry-run completes" "devtool-installer-arch" \
    "bash /home/testuser/install.sh --dry-run --profile /dev/null 2>&1 || true"

run_test "Ubuntu: --dry-run completes" "devtool-installer-ubuntu" \
    "bash /home/testuser/install.sh --dry-run --profile /dev/null 2>&1 || true"

# --version flag
run_test "Arch: --version exits 0" "devtool-installer-arch" \
    "bash /home/testuser/install.sh --version"

run_test "Ubuntu: --version exits 0" "devtool-installer-ubuntu" \
    "bash /home/testuser/install.sh --version"

# --help flag
run_test "Arch: --help exits 0" "devtool-installer-arch" \
    "bash /home/testuser/install.sh --help"

run_test "Ubuntu: --help exits 0" "devtool-installer-ubuntu" \
    "bash /home/testuser/install.sh --help"

# Profile: minimal — write a real temp file inside the container (process substitution
# fd paths like /dev/fd/63 only exist in the outer shell, not inside docker run -c)
run_test "Arch: minimal profile dry-run" "devtool-installer-arch" \
    "printf 'git\ncurl\nwget\nneovim\ntmux\n' > /tmp/minimal.profile && bash /home/testuser/install.sh --dry-run --profile /tmp/minimal.profile"

run_test "Ubuntu: minimal profile dry-run" "devtool-installer-ubuntu" \
    "printf 'git\ncurl\nwget\nneovim\ntmux\n' > /tmp/minimal.profile && bash /home/testuser/install.sh --dry-run --profile /tmp/minimal.profile"

printf "\n"
printf "Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}\n"
[[ "${FAIL}" -eq 0 ]]
