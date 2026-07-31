#!/bin/bash
# Compatibility wrapper for the guided-chain verifier.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/ctf/verify-chain.sh" "$@"
