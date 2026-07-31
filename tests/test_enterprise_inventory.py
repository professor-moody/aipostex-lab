from __future__ import annotations

import shlex
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ENTERPRISE_INVENTORY = ROOT / "lab-scripts" / "lib" / "enterprise-inventory.sh"
MINI_INVENTORY = ROOT / "lab-scripts" / "lib" / "inventory.sh"
ENTERPRISE_SETUP = ROOT / "lab-scripts" / "proxmox-enterprise-setup.sh"
ENTERPRISE_SNAPSHOTS = ROOT / "lab-scripts" / "enterprise-snapshots.sh"
ENTERPRISE_DEPLOY = ROOT / "lab-scripts" / "enterprise-deploy.sh"
ENTERPRISE_DEPLOY_ANSIBLE = ROOT / "lab-scripts" / "enterprise-deploy-ansible.sh"
ENTERPRISE_POLICY = ROOT / "lab-scripts" / "enterprise-policy.sh"
ENTERPRISE_ANSIBLE = ROOT / "lab-scripts" / "enterprise-generate-ansible-inventory.sh"
ENTERPRISE_ANSIBLE_PLAYBOOK = ROOT / "lab-scripts" / "ansible" / "enterprise.yml"
ENTERPRISE_VERIFY = ROOT / "lab-scripts" / "enterprise-verify.sh"


def run_bash(command: str):
    return subprocess.run(
        ["bash", "-lc", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_enterprise_inventory_defines_expected_hosts_and_zones():
    result = run_bash(
        f"source {shlex.quote(str(ENTERPRISE_INVENTORY))} && "
        "enterprise_host_summary"
    )

    assert result.returncode == 0
    lines = result.stdout.splitlines()
    assert len(lines) == 8
    assert "ent-attack|360|172.16.60.99|operator|vmbr160|172.16.60.1|operator-attack-box" in lines
    assert "ent-mlops-01|362|172.16.62.20|mlops|vmbr162|172.16.62.1|mlops-platform" in lines
    assert "ent-idp-01|367|172.16.66.70|security|vmbr166|172.16.66.1|identity-and-secrets" in lines


def test_enterprise_inventory_does_not_overlap_mini_vm_ids():
    result = run_bash(
        f"source {shlex.quote(str(MINI_INVENTORY))} && "
        "mini_ids=\"$(inventory_host_id ailab-dev) $(inventory_host_id ailab-ml) $(inventory_host_id ailab-ds) $(inventory_host_id ailab-app) $(inventory_host_id ailab-attack)\" && "
        f"source {shlex.quote(str(ENTERPRISE_INVENTORY))} && "
        "for host in $ENT_HOSTS; do enterprise_host_id \"$host\"; done | "
        "while read -r id; do case \" $mini_ids \" in *\" $id \"*) echo overlap:$id; exit 9;; esac; done"
    )

    assert result.returncode == 0
    assert "overlap:" not in result.stdout


def test_enterprise_dns_aliases_include_ai_service_names():
    result = run_bash(
        f"source {shlex.quote(str(ENTERPRISE_INVENTORY))} && "
        "enterprise_hosts_entries"
    )

    assert result.returncode == 0
    assert "mlflow.mlops.acme.internal" in result.stdout
    assert "litellm.platform.acme.internal" in result.stdout
    assert "jupyter.research.acme.internal" in result.stdout


def test_enterprise_setup_dry_run_is_non_mutating_and_mentions_terraform_boundary():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_SETUP), "--dry-run", "--profile", "pro"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "Proxmox Enterprise Setup" in result.stdout
    assert "DRY-RUN: append bridge vmbr160" in result.stdout
    assert "DRY-RUN: qm clone" in result.stdout
    assert "ent-inference-01" in result.stdout


def test_enterprise_snapshot_decline_is_nonzero():
    result = subprocess.run(
        ["bash", "-lc", f"printf 'n\\n' | bash {shlex.quote(str(ENTERPRISE_SNAPSHOTS))} restore enterprise-ready"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 3
    assert "Aborted by user" in result.stdout


def test_enterprise_deploy_exposes_full_phase_contract():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_DEPLOY), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "--phase infra|base|provision|seed|verify|policy|all" in result.stdout
    assert "Run infra, base, provision, seed, policy, verify" in result.stdout


def test_enterprise_ansible_inventory_is_generated_from_inventory_source():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_ANSIBLE)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "ent-attack:" in result.stdout
    assert "ansible_host: 172.16.60.99" in result.stdout
    assert "lab_role_dir: enterprise/inference-platform" in result.stdout
    assert "enterprise_targets:" in result.stdout


def test_enterprise_policy_render_contains_pro_cross_zone_rules():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_POLICY), "render"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "AIPOSTEX_ENT_PRO" in result.stdout
    assert "-s 172.16.60.0/24 -d 172.16.60.0/21 -j ACCEPT" in result.stdout
    assert "-s 172.16.65.0/24 -d 172.16.63.0/24 -j ACCEPT" in result.stdout
    assert "-s 172.16.60.0/21 -d 172.16.60.0/21 -j DROP" in result.stdout


def test_enterprise_verify_accepts_layer_and_profile_options():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_VERIFY), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "--layer net|services|seed|policy|all" in result.stdout
    assert "--profile team|pro" in result.stdout


def test_enterprise_ansible_wrapper_accepts_service_phases():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_DEPLOY_ANSIBLE), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert "--phase base|provision|seed|verify|all" in result.stdout
    assert "--profile team|pro" in result.stdout


def test_enterprise_ansible_wrapper_rejects_infrastructure_phases():
    result = subprocess.run(
        ["bash", str(ENTERPRISE_DEPLOY_ANSIBLE), "--phase", "infra"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 2
    assert "Enterprise infra is Bash-only" in result.stderr
    assert "enterprise-deploy.sh --phase infra" in result.stderr


def test_enterprise_ansible_playbook_uses_inventory_variables_not_hardcoded_ips():
    playbook = ENTERPRISE_ANSIBLE_PLAYBOOK.read_text()

    assert "172.16.60." not in playbook
    assert "172.16.61." not in playbook
    assert "{{ lab_role_dir }}" in playbook
    assert "{{ repo_root }}/lab-scripts/" in playbook
    assert "enterprise-verify.sh --layer all --profile {{ enterprise_profile }}" in playbook


def test_mini_ansible_wrapper_still_uses_mini_inventory():
    wrapper = (ROOT / "lab-scripts" / "deploy-ansible.sh").read_text()

    assert "lib/inventory.sh" in wrapper
    assert "enterprise-inventory.sh" not in wrapper
    assert "enterprise.yml" not in wrapper
