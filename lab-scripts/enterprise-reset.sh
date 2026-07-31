#!/bin/bash
# enterprise-reset.sh — restore enterprise VMs to a named snapshot.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT="${1:-enterprise-ready}"

exec bash "${SCRIPT_DIR}/enterprise-snapshots.sh" --yes restore "$SNAPSHOT"
