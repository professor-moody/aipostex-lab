---
title: aipostex Lab Environment
---

<div class="apx-dc" markdown="0">
  <span class="apx-dc-txt">✦ See you at DEF&nbsp;CON&nbsp;34 · Red&nbsp;Team&nbsp;Village ✦</span>
</div>
<style>
.apx-dc { text-align: center; margin: .2rem 0 1.4rem; }
.apx-dc-txt {
  display: inline-block;
  font-weight: 800;
  font-size: clamp(1rem, 3.4vw, 1.7rem);
  letter-spacing: .02em;
  background: linear-gradient(90deg,#a855f7,#8b5cf6,#6366f1,#3b82f6,#06b6d4,#3b82f6,#6366f1,#8b5cf6,#a855f7);
  background-size: 300% auto;
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  -webkit-text-fill-color: transparent;
  animation: apx-dc-shim 7s linear infinite;
}
@keyframes apx-dc-shim { to { background-position: 300% center; } }
@media (prefers-reduced-motion: reduce) { .apx-dc-txt { animation: none; background-position: 50% center; } }
</style>

# aipostex Lab Environment

**A 6-VM Proxmox lab for testing aipostex against realistic shadow AI sprawl.**

The lab spans five target personas: developer workstation, ML platform, data science, shared AI apps, and a Kubernetes node. The current mini lab includes A2A protocol fixtures, a shared callback listener, a post-exploitation validation oracle, and a localhost-gated lateral movement target. Together these expand the service surface to **29 health-checked endpoints** and **170 planted sensitive findings**.

!!! tip "Just need to test the tool against one product?"
    The [Single-Service Sandbox](sandbox.md) spins up one **real** AI-infra product (ChromaDB, W&B,
    Qdrant, MLflow, Ollama, or a real a2a-sdk agent) under Docker on your workstation — no full lab
    required. It's the fast realism dev loop.

---

## Lab at a Glance

| Metric | Count |
|---|---|
| Virtual machines | **6** (5 targets + 1 attack box) |
| Target VMs | **5** |
| Health-checked service endpoints | **29** |
| Planted sensitive findings | **170** |
| `verify-lab.sh` checks | **62** |

---

## Feature Highlights

![Lab network topology](assets/aipostex_lab_network_topology.svg)

### Network Discovery

Scan `172.16.50.0/24` and fingerprint the exposed AI/ML surface including Ollama, Jupyter, MCP, Gradio, ChromaDB, MLflow, LiteLLM, Ray, Weaviate, Qdrant, LangServe, Streamlit, an auth-gated HF TGI gateway, HF TEI, vLLM, TorchServe, BentoML, Triton, W&B, Kubeflow, TF Serving, pgvector, three A2A protocol agents, and a Kubernetes node (`kube-apiserver` on `:6443`).

### A2A Protocol Testing

Three A2A agent fixtures on ailab-app (ports 8100–8102) exercise the full A2A attack chain: agent card enumeration, unauthenticated task injection, task history credential leak, streaming eavesdrop, push-notification hijack, and A2A-to-MCP cross-protocol pivoting.

### Post-Exploitation Validation

A callback listener (ailab-attack:9000) confirms webhook callbacks fire. A Post-Ex Oracle (ailab-app:8765) validates credentials, persistence heartbeats, and execution sentinels. A localhost-only lateral target on ailab-dev requires prior RCE to reach.

### Tier 2 Workflow Validation

The lab includes verification coverage for bounded Tier 2 exploit workflows: Ollama exfiltration, Jupyter kernel abuse, Ray pip injection, MLflow tamper-proof paths, MCP stdio transport, and A2A push-notification hijack with callback confirmation.

### Deployment Evolution

The repo keeps Bash as the canonical path, introduces a shared inventory source, adds an optional Ansible wrapper, and documents the later Packer/Ludus path.

### Enterprise Track (in development)

The 6-VM lab here is the **Mini tier** and is fully supported today. A larger multi-host **Enterprise track** (`ent-*` hosts, routed Proxmox zones, internal DNS-style aliases, staged Ansible) is in development — see [Enterprise Lab Architecture](architecture/enterprise.md) for its layout and sizing.

---

## Quick Start

```bash
bash lab-scripts/proxmox-setup.sh
bash lab-scripts/attack-box/setup.sh
bash lab-scripts/deploy-all.sh
bash lab-scripts/verify-lab.sh
```

For the staged automation roadmap, see [Deployment Evolution](deployment/evolution.md).
