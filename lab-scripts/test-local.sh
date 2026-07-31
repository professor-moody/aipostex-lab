#!/bin/bash
# test-local.sh — Local validation runner for repo checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUIRE_SHELLCHECK="${REQUIRE_SHELLCHECK:-0}"

run_step() {
    echo ""
    echo "[*] $1"
}

cd "${ROOT_DIR}"

run_step "Running pytest"
python3 -m pytest tests

# review-for-recording/ holds transcript-recovered B-roll drivers with session-specific
# scratchpad paths — recording production, not portable lab tooling — so it is out of scope
# for lab validation.
run_step "Checking shell syntax"
while IFS= read -r script; do
    bash -n "${script}"
done < <(git ls-files '*.sh' ':!review-for-recording')

run_step "Checking Python syntax"
git ls-files -z '*.py' | xargs -0 -r python3 -m py_compile

run_step "Building docs"
mkdocs build

if command -v shellcheck >/dev/null 2>&1; then
    run_step "Running shellcheck"
    git ls-files -z '*.sh' ':!review-for-recording' | xargs -0 -r shellcheck --severity=warning
elif [[ "${REQUIRE_SHELLCHECK}" == "1" ]]; then
    echo "[!] shellcheck is required but not installed"
    exit 1
else
    echo ""
    echo "[*] Skipping shellcheck (not installed locally)"
fi

echo ""
echo "[+] Local validation complete"
