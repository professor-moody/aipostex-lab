# Single-Service Sandbox

A **dev-machine** harness for pointing `aipostex` at **one real AI-infra product** at a time, fast —
without standing up the full 6-VM lab. It's the realism-principle dev loop:

```
up <svc>  →  run the matching aipostex module against the real API  →  confirm the module is honest  →  down
```

It runs on your **workstation under Docker** and is **separate from the deployed lab** (the Proxmox
VMs). Docker is the right tool *here* — single-service API testing, not the lab's host-path artifact
scan — so the lab's [native-vs-docker rationale](architecture/native-vs-docker.md) doesn't apply.

!!! tip "Why it exists"
    Tool-shaped mocks hide tool bugs. Pointing the tool at the **real** product immediately surfaces
    them — this loop caught a `wandb` module mis-reporting a version against a still-starting server,
    and the 5 new A2A probe verbs crashing against an auth-enforcing agent. See *Findings* below.

## Prerequisites

- **Docker** on your workstation.
- A built `aipostex` binary:

```bash
( cd ../aipostex && make build )                 # or your aipostex checkout
export AIPOSTEX=/path/to/aipostex/bin/aipostex   # default: 'aipostex' on PATH
```

## Use

From the lab repo's `sandbox/` directory:

```bash
./sandbox list                 # services + running status
./sandbox up chromadb          # pull/build + start + health-check + (seed) + print URL & prove cmd
./sandbox prove chromadb       # run the matching `aipostex <module>` against the real product
./sandbox down chromadb        # stop + remove (volumes too)
./sandbox up --all | down --all
./sandbox logs wandb           # tail container logs
```

## Services

Each service is `services/<svc>.yml` (a Compose file) + `services/<svc>.meta`
(`DESC`/`PORT`/`URL`/`HEALTH`/`PROVE`/`SEED`). Bump an image tag to test the tool against a newer API
version — a deliberate source of real findings.

| Service | Real product | Module | Notes |
|---|---|---|---|
| `chromadb` | ChromaDB vector store | `vectordb --type chromadb` | validated (enum clean) |
| `wandb` | Weights & Biases (`wandb/local`) | `wandb` | validated (real GraphQL) |
| `qdrant` | Qdrant vector store | `vectordb --type qdrant` | defined |
| `mlflow` | MLflow tracking server | `mlflow` | defined |
| `ollama` | Ollama model server | `ollama` | defined |
| `a2a` | Real a2a-sdk agent (vuln + secure peer) | `a2a` (5 probe verbs) | validated — vuln on `:8103`, hardened peer on `:8104` |
| `k8s` | Real k3s API server (vuln + secure) | `k8s` (rbac-probe, enum, secret-read, pod-exec) | validated — anon-open vuln on `:6443`, default-secure control on `:6444` |

The `a2a` service builds **two** containers from one compose file: a deliberately-weak agent
(`A2A_MODE=vuln`, `:8103`) where the 5 probe verbs must report **weak**, and a hardened
`A2A_MODE=secure` peer (`:8104`) where they must report **not-weak** (it's also the in-network
delegation peer). `prove a2a` runs the weak side; point the verbs at `:8104` for the control.

The `k8s` service runs **two** real single-node k3s clusters from one compose file: an anon-open
`k8s-vuln` on `:6443` (anonymous-auth on + a `ClusterRole` bound to `system:anonymous`) where the
verbs must report **weak** — anonymous cross-namespace secret exfiltration, in-pod root RCE, and an
in-cluster privilege escalation (`sa-loot` steals the model-server pod's over-granted `pipeline-runner`
service-account token and re-authenticates as the write-capable identity) — and a default-secure
`k8s-secure` on `:6444` where the verbs must report **not-weak** (401 enforced). Each auto-deploys its
seed ML manifests; the weak anon RBAC binding + the escalation ServiceAccount are in the vuln set only.
The API server uses a self-signed cert, so the verbs pass `--insecure`.

## Adding a service

1. `services/<svc>.yml` — a Compose file pulling/building the **real** product.
2. `services/<svc>.meta` — `DESC`, `PORT`, `URL`, `HEALTH` (a URL that 200s when ready),
   `PROVE` (the `aipostex` command, referencing `"$AIPOSTEX"`), optional `SEED` (a script in
   `services/` that plants minimal data so the tool finds something).
3. `./sandbox up <svc> && ./sandbox prove <svc>`.

Full details, the runner, and the per-service definitions live in
[`sandbox/`](https://github.com/professor-moody/aipostex-lab/tree/main/sandbox) (see its `README.md`).

## Findings log (the point of this harness)

Real bugs this loop surfaced (and that got fixed in `aipostex`):

- **A2A probe verbs vs a secured agent** — the 5 verbs crashed (`request failed 401`) against an
  auth-enforcing agent instead of honestly reporting "not weak"; fixed so a 4xx/5xx is a valid
  not-weak signal, not a fatal error.
- **`wandb` version robustness** — against a still-starting `wandb/local`, `wandb enum` scraped a
  version out of a `/healthz` liveness token / HTML error page; fixed to treat `/healthz` as a
  liveness probe, not a version source.
