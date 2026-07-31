# AWS Cost & EC2 Right-Sizing

What the cloud lab costs to run — per range and at con scale — and why each node is the size it is.
All prices are **us-east-1 on-demand, Linux** (list, mid-2026); your region/discounts will differ.

## Right-sizing rationale

The lab looks heavy (31 services across the estate) but almost all of it is **lightweight Python
mocks**. The only real compute is **Ollama local inference on dev + ds** (~5 tok/s at 2 vCPU); ml runs
13 mock services + a lightweight Ray scheduler; app/attack are proxies/tooling; the k8s node is a
single-node k3s. So the sizing is driven by two facts:

- **Ollama is CPU-bound** → dev + ds use **`c6i.large`** (non-burstable, guaranteed 100% CPU) so
  sustained multi-attendee inference never hits the t3 CPU-credit cliff.
- **Everything else is idle-light** → ml drops from the original 4×-oversized `t3.xlarge` to
  `t3.large`; app to `t3.small`; k8s to `t3.medium`. The **attack box is `t3.large` (8 GB)**, bumped
  from `t3.small` to host ~25 concurrent seat shells plus the tool.
- **ARM/Graviton is blocked** — Weaviate and Qdrant ship **x86-only** binaries and ds needs both — so
  all nodes are x86. (Graviton would otherwise save ~20%.)

| node | instance | vCPU / RAM | disk | $/hr | why |
|---|---|---|---|---|---|
| ailab-dev | `c6i.large` | 2 / 4 | 20 GB | 0.085 | Ollama — non-burstable |
| ailab-ml | `t3.large` | 2 / 8 | 40 GB | 0.083 | 13 mocks + Ray (down from t3.xlarge) |
| ailab-ds | `c6i.large` | 2 / 4 | 20 GB | 0.085 | Ollama + Weaviate/Qdrant (x86) |
| ailab-k8s | `t3.medium` | 2 / 4 | 30 GB | 0.042 | single-node k3s "ACME cluster" |
| ailab-app | `t3.small` | 2 / 2 | 20 GB | 0.021 | LangServe/Streamlit/A2A proxies |
| ailab-attack | `t3.large` | 2 / 8 | 20 GB | 0.083 | operator tooling + lab-listener + ~25 seat shells |
| **per range** | **6 nodes** | 12 / 30 | 150 GB | **≈ 0.399 compute + 0.015 EBS = 0.41** | |

## Cost at scale

| scenario | cost | note |
|---|---|---|
| 1 range, running | ~$0.41/hr | ~$3.3 for an 8-hr workshop day |
| **5 ranges, running** | **~$2.05/hr** | **~$16 / 8-hr day; ~$49 / 3-day con** |
| 5 ranges, left on 24/7 (month) | ~$1,290/mo | the real cost trap — never leave them running |
| **5 ranges, STOPPED between events** | **$0 compute** | pay only EBS ≈ $58/mo (or terminate + keep AMIs ≈ $6–12/mo) |
| testing / non-demo, Spot | ~$0.12/hr/range | stateless nodes tolerate Spot (~65% off) |

## The takeaways

1. **At con scale the dollar cost is trivial** — ~$16/day for all 5 ranges. The lab is cheap to *run*.
2. **The only real cost risk is leaving instances running idle.** Compute for a *stopped* EC2 instance
   is **$0** — you pay only ~$0.80/mo of EBS per node. So between events, **stop** the ranges
   (`aws ec2 stop-instances`); after the con, `terraform destroy`.
3. **Right-sizing is roughly cost-neutral, not a saving** — dropping ml `t3.xlarge`→`t3.large` funds the
   `c6i` upgrade on the two Ollama hosts. You buy *predictable performance*, not a smaller bill.
4. **The one big lever is the GPU tier** — real inference (`g5.xlarge` ≈ $1.0/hr each) would multiply
   the bill, which is exactly why it stays an optional tier, off for the talk.
5. **Reset between waves is free** — `aws-reset-wave.sh` restores from the baked `lab-ready` AMIs +
   re-seeds; the instances keep running, so there's no extra spend to reset the estate for a new wave.
