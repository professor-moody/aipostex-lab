#!/bin/bash
# sync-files.sh — Copy lab-scripts/ into Ludus role files/ directories.
#
# Ludus requires roles to be self-contained when uploaded via
# `ludus ansible role add -d`. This script copies the canonical
# bash scripts into each role's files/ directory so they can be
# shipped to the Ludus server.
#
# The synced files/ dirs are .gitignored to avoid duplication in VCS.
#
# Usage: bash ludus/sync-files.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAB="${REPO_ROOT}/lab-scripts"
ROLES="${SCRIPT_DIR}/roles"

log() { echo "[*] $1"; }
ok()  { echo "[+] $1"; }

# ── aipostex_base ────────────────────────────────────────────
log "Syncing aipostex_base..."
rm -rf "${ROLES}/aipostex_base/files"
mkdir -p "${ROLES}/aipostex_base/files/lib"
cp "${LAB}/base-setup.sh" "${ROLES}/aipostex_base/files/"
cp "${LAB}/lib/inventory.sh" "${ROLES}/aipostex_base/files/lib/"
ok "aipostex_base"

# ── aipostex_dev_workstation ─────────────────────────────────
log "Syncing aipostex_dev_workstation..."
rm -rf "${ROLES}/aipostex_dev_workstation/files"
mkdir -p "${ROLES}/aipostex_dev_workstation/files"
cp -r "${LAB}/dev-workstation/"* "${ROLES}/aipostex_dev_workstation/files/"
cp -r "${LAB}/lib" "${ROLES}/aipostex_dev_workstation/files/"
ok "aipostex_dev_workstation"

# ── aipostex_ml_platform ─────────────────────────────────────
log "Syncing aipostex_ml_platform..."
rm -rf "${ROLES}/aipostex_ml_platform/files"
mkdir -p "${ROLES}/aipostex_ml_platform/files"
cp -r "${LAB}/ml-platform/"* "${ROLES}/aipostex_ml_platform/files/"
cp -r "${LAB}/lib" "${ROLES}/aipostex_ml_platform/files/"
ok "aipostex_ml_platform"

# ── aipostex_data_sci ────────────────────────────────────────
log "Syncing aipostex_data_sci..."
rm -rf "${ROLES}/aipostex_data_sci/files"
mkdir -p "${ROLES}/aipostex_data_sci/files"
cp -r "${LAB}/data-sci/"* "${ROLES}/aipostex_data_sci/files/"
cp -r "${LAB}/lib" "${ROLES}/aipostex_data_sci/files/"
ok "aipostex_data_sci"

# ── aipostex_app_platform ────────────────────────────────────
log "Syncing aipostex_app_platform..."
rm -rf "${ROLES}/aipostex_app_platform/files"
mkdir -p "${ROLES}/aipostex_app_platform/files"
cp -r "${LAB}/app-platform/"* "${ROLES}/aipostex_app_platform/files/"
cp -r "${LAB}/lib" "${ROLES}/aipostex_app_platform/files/"
ok "aipostex_app_platform"

# ── aipostex_attack_box ──────────────────────────────────────
log "Syncing aipostex_attack_box..."
rm -rf "${ROLES}/aipostex_attack_box/files"
mkdir -p "${ROLES}/aipostex_attack_box/files"
cp -r "${LAB}/attack-box/"* "${ROLES}/aipostex_attack_box/files/"
cp -r "${LAB}/lib" "${ROLES}/aipostex_attack_box/files/"
ok "aipostex_attack_box"

echo ""
ok "All role files synced from lab-scripts/"
