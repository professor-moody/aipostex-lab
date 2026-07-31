#!/bin/bash
# Generate Ansible inventory for enterprise hosts from enterprise-inventory.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab-scripts/lib/enterprise-inventory.sh
source "${SCRIPT_DIR}/lib/enterprise-inventory.sh"

cat <<'YAML'
---
all:
  vars:
    ansible_user: labadmin
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    lab_root: "/home/{{ ansible_user }}/lab"
    repo_root: "{{ playbook_dir }}/../.."
  children:
    enterprise:
      hosts:
YAML

for host in ${ENT_HOSTS}; do
    cat <<YAML
        ${host}:
          ansible_host: $(enterprise_host_ip "$host")
          enterprise_zone: $(enterprise_host_zone "$host")
          lab_role_dir: $(enterprise_host_role_dir "$host")
YAML
done

cat <<'YAML'
    enterprise_targets:
      hosts:
YAML
for host in ${ENT_TARGET_HOSTS}; do
    cat <<YAML
        ${host}:
YAML
done

cat <<'YAML'
    enterprise_attack:
      hosts:
        ent-attack:
YAML
