# Resource Tuning

The lab runs on a single Proxmox host. This page covers resource allocation for different host sizes, from a tight 16 GB system to a comfortable 32 GB+ setup.

---

## Minimum Viable (16 GB Host)

Cuts every VM to the bare minimum while keeping all services functional. Expect slower Ollama inference and modest Jupyter performance.

| VM | vCPU | RAM | Notes |
|----|------|-----|-------|
| ailab-dev | 2 | 3 GB | Ollama needs ~1.5 GB for smollm2 |
| ailab-ml | 1 | 2 GB | ChromaDB + MLflow lightweight |
| ailab-ds | 2 | 3 GB | Multiple services but small footprint |
| ailab-app | 1 | 1 GB | LangServe + Streamlit, low resource |
| ailab-attack | 1 | 1 GB | Just CLI tools and SSH |
| **Total** | **7 vCPU** | **10 GB** | Leaves ~6 GB for Proxmox + headroom |

!!! warning "Tight on RAM"
    With 10 GB allocated to VMs and Proxmox needing 2–3 GB, a 16 GB host has very little headroom. Avoid running additional workloads on the host during the demo.

---

## Comfortable (32 GB+ Host)

The recommended allocation. Services respond quickly, Ollama inference is noticeably faster, and there's room to experiment.

| VM | vCPU | RAM | Notes |
|----|------|-----|-------|
| ailab-dev | 4 | 8 GB | Fast inference, comfortable Jupyter |
| ailab-ml | 2 | 4 GB | Room for larger ChromaDB collections |
| ailab-ds | 4 | 8 GB | Weaviate and Qdrant run smoothly |
| ailab-app | 2 | 2 GB | LangServe + Streamlit with headroom |
| ailab-attack | 2 | 2 GB | Parallel scans, faster builds |
| **Total** | **14 vCPU** | **24 GB** | Leaves 8+ GB for Proxmox |

---

## Tuning Notes

### CPU and Ollama Inference

Ollama CPU inference with `smollm2:135m` works on 2 vCPU at roughly 5 tokens/sec. More cores improve throughput linearly up to about 8 cores. For demo purposes, 2 vCPU is sufficient — aipostex extracts system prompts regardless of inference speed.

### Disk

Each VM uses approximately 10–15 GB of disk after provisioning (OS + installed packages + seeded data). Cloud image templates consume about 3 GB total. Plan for at least 60 GB of free storage on the Proxmox host to be comfortable.

### Where to Cut First

If the host is constrained, reduce RAM on `ailab-ml` first — it has the lightest workload. ChromaDB, MLflow, LiteLLM, and Ray are all lightweight Python services that run fine in 2 GB. The attack box can also drop to 1 GB since it only runs CLI tools.

`ailab-dev` and `ailab-ds` both run Ollama, which is the most RAM-hungry process. Keep them at 3 GB minimum to avoid OOM kills during model loading.

### Overcommit

Proxmox allows CPU overcommit by default. Allocating more total vCPUs than physical cores is fine for this lab — the VMs are rarely all CPU-active simultaneously. RAM overcommit is riskier and not recommended; allocate only what the host physically has.
