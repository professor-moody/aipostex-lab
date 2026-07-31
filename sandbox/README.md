# sandbox — single-service real-product test harness

> 📖 Published guide: **[Single-Service Sandbox](../docs/sandbox.md)** (rendered on the docs site).

A **dev-machine** harness for pointing `aipostex` at **one real AI-infra product** at a time, fast:
`up` → run the matching module against the real API → confirm the module is honest → `down`. This is
the realism-principle dev loop, and it's the loop that surfaces real tool bugs that tool-shaped mocks
hide (e.g. it immediately caught the `wandb` module mis-reporting a version against a still-starting
server — see *Findings* below).

This is **not** part of the deployed lab. It runs on your workstation under Docker. Docker is the right
tool *here* — single-service API testing, not the lab's host-path artifact scan — so the lab's
[native-only rationale](../docs/architecture/native-vs-docker.md) does not apply.

## Use

```bash
# Build the tool once and point the harness at it:
( cd ../../aipostex && make build )          # or your aipostex checkout
export AIPOSTEX=/path/to/aipostex/bin/aipostex   # default: 'aipostex' on PATH

./sandbox list                 # services + running status
./sandbox up chromadb          # pull + start + health-check + (seed) + print URL & proof cmd
./sandbox prove chromadb       # run the matching `aipostex <module>` against the real product
./sandbox down chromadb        # stop + remove (volumes too)
./sandbox up --all | down --all
./sandbox logs wandb           # tail container logs
```

## Services

Each service is `services/<svc>.yml` (a Compose file) + `services/<svc>.meta`
(`DESC`/`PORT`/`URL`/`HEALTH`/`PROVE`/`SEED`). Bump an image tag to test the tool against newer API
versions — that's a deliberate source of real findings (e.g. Chroma's v1→v2 API shift).

| Service | Real product | Module | Status |
|---|---|---|---|
| `chromadb` | ChromaDB vector store | `vectordb --type chromadb` | **validated** (enum clean; reported `version=v2`) |
| `wandb` | Weights & Biases (`wandb/local`) | `wandb` | **validated** (real GraphQL; one robustness nit, see below) |
| `qdrant` | Qdrant vector store | `vectordb --type qdrant` | defined — validate on first `up` |
| `mlflow` | MLflow tracking server | `mlflow` | defined — validate on first `up` |
| `ollama` | Ollama model server | `ollama` | defined — validate on first `up` |
| `a2a` | Real a2a-sdk agent (vuln target + secure peer) | `a2a` (5 probe verbs) | **validated** (built from the lab a2a-real-agent; caught a real verb bug, see below) |
| `k8s` | Real k3s API server (anon-open vuln + default-secure) | `k8s` (rbac-probe, enum, secret-read, pod-exec) | **validated** (full kill chain: anon enum → secret exfil → in-pod root RCE; `:6444` is the auth-enforced control) |

The `a2a` service builds **two** containers from one compose file: the agent under test in
`A2A_MODE=vuln` on `:8103` (the 5 probe verbs MUST report weak) and a hardened `A2A_MODE=secure`
peer on `:8104` (the same verbs MUST report not-weak; it is also the in-network delegation peer the
vuln agent dials at `http://peer:8103/`). `prove` runs the weak side; point the verbs at `:8104` for
the not-weak control. The `A2A_MODE` env (stock/vuln/secure) lives in the lab agent's `server.py` and
is opt-in — the deployed lab agent on `:8103` leaves it unset and is unchanged.

The `k8s` service runs **two** real single-node k3s clusters from one compose file: `k8s-vuln` on
`:6443` (anonymous-auth on + a `ClusterRole` bound to `system:anonymous` granting read on
workloads/secrets and create on `pods/exec`) and `k8s-secure` on `:6444` (default-secure: anon-auth
off, no anon binding). Each auto-deploys its seed manifests (an `ml-prod` namespace with a
model-registry `Secret`, a `model-server` `Deployment`, and a KServe `InferenceService` CRD; the vuln
set also adds an `ml-system` namespace and runs the model-server pod under a `pipeline-runner`
ServiceAccount over-granted cluster-wide **write**) from `/var/lib/rancher/k3s/server/manifests`; the
deliberately-weak anon RBAC binding + the escalation SA are in the **vuln** manifest set only. `prove`
runs `rbac-probe`/`enum --all-namespaces`/`secret-read --all-namespaces`/`pod-exec`/`sa-loot` against
`:6443` (each MUST report weak — anonymous cross-namespace secret exfil, in-pod root RCE, and a
privilege escalation where `sa-loot` steals the pod's token and re-auths as the write-capable SA) and
`rbac-probe` against `:6444` for the not-weak control (401 enforced). The API server uses a self-signed
cert, so every call passes `--insecure`; pods take ~30s to schedule, so re-run `pod-exec`/`sa-loot` if
they find no pod on the first try.

**Planned (need a build/config, not just a pull):** `litellm` (needs a model config), `weaviate`,
`ray`. (`mcp` is now FULLY REAL on the lab `:3000`; build a sandbox service from
`../lab-scripts/dev-workstation/mcp-real-server/server.py` when needed.) GPU products
(vLLM/Triton/TGI/TEI) stay opt-in.

## Adding a service

1. `services/<svc>.yml` — a Compose file pulling/building the **real** product.
2. `services/<svc>.meta` — `DESC`, `PORT`, `URL`, `HEALTH` (a URL that 200s when ready),
   `PROVE` (the `aipostex` command, using `"$AIPOSTEX"`), optional `SEED` (a script in `services/`
   that plants minimal data so the tool finds something).
3. `./sandbox up <svc> && ./sandbox prove <svc>`.

## Findings log (the point of this harness)

- **`a2a` module, all 5 new probe verbs — crashed against a properly-secured agent (FIXED):** the
  `auth-probe`, `msg-integrity`, `sender-spoof`, `delegate-probe`, and `card-spoof` verbs were only
  ever exercised against agents that *accept* requests. Pointed at the `A2A_MODE=secure` peer (which
  enforces auth with HTTP 401), every verb **errored out** (`request failed 401`) instead of honestly
  reporting the not-weak result (auth enforced / message rejected). A JSON-RPC call that gets a real
  HTTP status was being treated as a transport failure. Fix (tool side): a 4xx/5xx rejection is a
  valid "not weak" signal, not a fatal error; only a true transport failure (no response) aborts the
  probe. After the fix the verbs are honest in **both** directions — weak vs the vuln target, not-weak
  vs the secure peer — which is the whole point of having both. Validated weak-vs-secure matrix:
  auth-probe MED↔INFO, msg-integrity MED↔INFO, sender-spoof MED↔INFO, delegate-probe HIGH↔INFO,
  card-spoof MED↔INFO.
- **`wandb` module, robustness:** against `wandb/local` that is still starting (DB migration window;
  `/graphql` returns 502 behind an HTML error page), `wandb enum` reported `version=ready!` — it
  scraped the error page instead of reporting the API as unavailable. Once the server is fully up
  (`/graphql` 200; serves unauthenticated `serverInfo`/`viewer`), enum behaves correctly. Fix: have
  `wandb enum` treat a non-2xx/HTML `/graphql` as unavailable rather than parsing a version out of it.
