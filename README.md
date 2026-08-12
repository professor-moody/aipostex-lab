# aipostex Lab

[![Docs](https://img.shields.io/badge/docs-mkdocs-blue)](https://professor-moody.github.io/aipostex-lab/)

A reproducible Proxmox lab for testing [aipostex](https://github.com/professor-moody/aipostex) against
realistic shadow-AI sprawl: six VMs standing in for four teams that each deployed AI tooling without
coordinated review, plus a Kubernetes node and an operator attack box — all watched by a persistent
Elastic detection stack on a seventh, standalone host.

Everything is installed natively with systemd rather than hidden in one container file, because that is how
this infrastructure actually accumulates. Most of it is the real software — real MLflow, real Ray, a real MCP
server, a real agent framework, a real k3s cluster — with CPU stand-ins only where a GPU would otherwise be
required.

**29 service endpoints · 170 planted findings · 13 attack scenarios · 62 verification checks**

📖 **Full documentation: [professor-moody.github.io/aipostex-lab](https://professor-moody.github.io/aipostex-lab/)**

---

## Try one service first

No hypervisor needed. Runs one real AI-infra product under Docker on your workstation:

```bash
cd sandbox && ./sandbox up chromadb && ./sandbox prove chromadb && ./sandbox down chromadb
```

→ [Single-service sandbox](https://professor-moody.github.io/aipostex-lab/sandbox/)

## Build the full estate

```bash
bash lab-scripts/proxmox-setup.sh       # bridge, templates, clone the VMs
bash lab-scripts/attack-box/setup.sh    # provision the operator box
bash lab-scripts/deploy-all.sh          # deploy and seed the targets
bash lab-scripts/verify-lab.sh          # expect 62 passed / 0 failed
```

Reset between runs, rolling every VM back to the `lab-ready` snapshot and re-arming the seeded state:

```bash
bash lab-scripts/reset-wave.sh
```

→ [Quick Start](https://professor-moody.github.io/aipostex-lab/getting-started/quickstart/) ·
[VM Map](https://professor-moody.github.io/aipostex-lab/getting-started/vm-map/) ·
[Snapshots & Reset](https://professor-moody.github.io/aipostex-lab/deployment/snapshots/)

## Where it can run

| Path | Use it for | Docs |
|---|---|---|
| **Proxmox** | The default. Your own hardware, the full estate. | [Proxmox Setup](https://professor-moody.github.io/aipostex-lab/deployment/proxmox-setup/) |
| **AWS** | Same estate in the cloud, all Terraform. Stop or destroy it and it costs nothing. | [AWS Deployment](https://professor-moody.github.io/aipostex-lab/deployment/aws/) |
| **Docker sandbox** | One real product on a laptop, about a minute. | [Sandbox](https://professor-moody.github.io/aipostex-lab/sandbox/) |
| **Enterprise** | Larger routed topology for training environments. In development. | [Enterprise Proxmox](https://professor-moody.github.io/aipostex-lab/deployment/enterprise-proxmox/) |

→ [Deployment Matrix](https://professor-moody.github.io/aipostex-lab/deployment/deployment-matrix/)

## Verify and score

```bash
bash lab-scripts/verify-lab.sh                                   # estate health, 62 checks
bash lab-scripts/ctf/verify-chain.sh                             # the guided credential chain, 13 checks
bash lab-scripts/attack-box/verify-aipostex.sh --layer all       # deep tool validation
python3 lab-scripts/scoring/score.py results.json --strict       # score a run against the 170-finding key
```

→ [Scoring & Verification](https://professor-moody.github.io/aipostex-lab/scoring/scoring/)

## Start here in the docs

- [Quick Start](https://professor-moody.github.io/aipostex-lab/getting-started/quickstart/) — build it
- [VM Map](https://professor-moody.github.io/aipostex-lab/getting-started/vm-map/) — every host, IP and port
- [Services](https://professor-moody.github.io/aipostex-lab/services/) — what is running and why it is exposed
- [Attack Scenarios](https://professor-moody.github.io/aipostex-lab/attack-scenarios/) — 13 guided missions
- [Demo Walkthrough](https://professor-moody.github.io/aipostex-lab/demo/walkthrough/) — the credential chain end to end
- [Scoring & Verification](https://professor-moody.github.io/aipostex-lab/scoring/scoring/) — grade yourself against the answer key

## Authorized use

This lab is intentionally vulnerable. Run it on infrastructure you own, on an isolated network. It is built
for security research, training and tool development. See [SECURITY.md](SECURITY.md).
