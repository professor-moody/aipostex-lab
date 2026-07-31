---
title: Adding a Service or Mock to the Lab
---

# Adding a Service or Mock to the Lab

This is the ordered checklist for landing a new service in the lab. The lab runs **real
upstream software wherever CPU allows** and uses honestly-labeled mocks only where the real
product needs a GPU or an external SaaS account (see [Mock & Fixture
Fidelity](../reference/mock-fidelity.md)). Before you write a mock, confirm the real thing
can't just run natively — a mock is a last resort, not a shortcut.

Everything below assumes you are adding a **protocol mock** (a standalone Python HTTP server
seeded with data) to one of the ML/DS/app roles. A mock is only correct if `aipostex`
fingerprints it, `verify-lab.sh` health-checks it, and the RRR matrix classifies what it
claims. All the steps matter; skipping one leaves the service invisible, unverified, or
over-claiming.

---

## Understanding the lab architecture: VMs, roles, and placement

The lab is a small set of role VMs; put the service where its real-world counterpart would
live:

| Role | Host | IP | What lives here |
|---|---|---|---|
| Developer workstation | `ailab-dev` | `172.16.50.10` | Ollama, Jupyter, MCP, Gradio |
| ML platform | `ailab-ml` | `172.16.50.20` | Training/serving: MLflow, Ray, W&B, Kubeflow, inference fixtures |
| Data science | `ailab-ds` | `172.16.50.30` | Vector DBs, notebooks |
| Shared AI apps | `ailab-app` | `172.16.50.40` | LangServe, Streamlit, A2A agents |
| Attack box | `ailab-attack` | `172.16.50.99` | Operator tooling, callback listener |

Each role has a provisioning script under `lab-scripts/<role>/provision.sh`. **The role
directory names are `dev-workstation`, `ml-platform`, `data-sci`, and `app-platform`** (note the
`data-sci` suffix — not `data-science`). The mock's `server.py` lives beside it. A W&B-style
GraphQL surface belongs on `ailab-ml`; an agent surface belongs on `ailab-app`. Pick the role
first — it decides every path below.

---

## Step 1 — Implement the mock server (`server.py`) with fingerprint probes

Write a **standalone Python 3 `BaseHTTPRequestHandler`** server — no framework, no external
deps beyond the stdlib. Place it at:

```
lab-scripts/<role>/<service>-mock/server.py
```

for example `lab-scripts/ml-platform/wandb-mock/server.py`. Provisioning copies it to
`/home/mluser/projects/<service>-mock/` on the VM.

The mock's one job is to answer the exact probes `aipostex` sends. **The probe is the contract.**
Fingerprinting is driven by `HTTPProbe` definitions in `pkg/fingerprint/fingerprint.go` in the
aipostex repo — `BuiltinProbes()` begins around line 1111, and each probe carries `Path`,
`MatchStatus`, `MatchBody`, optional `MatchBodyNot` / `MatchHeader`, and an optional
`VersionRegex`. Your server must satisfy the probe for the service you're modeling. For example,
the W&B probe posts a GraphQL `Viewer` query to `/graphql` and matches `viewer` in a `200` body,
with `/healthz` returning `wandb` as a supporting signal:

```go
{
    Name:        "wandb",
    DefaultPort: 8080,
    Probes: []HTTPProbe{
        {
            Method: "POST", Path: "/graphql",
            Headers:     map[string]string{"Content-Type": "application/json"},
            Body:        `{"query":"query Viewer { viewer { username entity } }"}`,
            MatchStatus: 200, MatchBody: "viewer", Specificity: 90,
        },
        {Path: "/healthz", MatchStatus: 200, MatchBody: "wandb", Specificity: 70, Strength: ProbeStrengthSupporting},
    },
},
```

Minimum server skeleton:

```python
#!/usr/bin/env python3
"""<Service> mock for aipostex lab validation.

Mirrors the real product's API shape (the paths/bodies aipostex probes),
seeded with planted findings. Legacy/tool-shaped routes are omitted so a
tool-shaped client fails against it.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("SERVICE_MOCK_PORT", "9200"))  # env-driven; see Step 2

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        if path == "/healthz":
            self._text(200, "service-name 1.0.0")   # supporting-signal body
            return
        self._text(404, "Not Found")

    def do_POST(self):
        path = self.path.split("?")[0].rstrip("/") or "/"
        # dispatch to your API surface here
        self._text(404, "Not Found")

    # helpers: _text / _json set status + Content-Type and write the body
    def log_message(self, *_):  # keep journald quiet
        pass

if __name__ == "__main__":
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
```

Rules that keep the mock honest against the real API — not against `aipostex`:

- **Match the real product's protocol semantics, not the tool's convenience.** The W&B mock
  returns GraphQL parse errors as **HTTP 200 with an `errors[]` array** (real GraphQL), never
  `400`, and sets `Content-Type: application/json; charset=utf-8`; nodes carry `__typename`
  (`Project`/`Run`/`ArtifactCollection`). A mock shaped around what the tool sends can *mask
  tool bugs* — model the product.
- **Bind `0.0.0.0`** so the role VM's IP is reachable from the attack box.
- **Env-driven config where a second instance is useful.** The Kubeflow mock reads
  `KUBEFLOW_MOCK_PORT` (default `9000`) and `KUBEFLOW_API_MODE` (`both`/`v1`/`v2`) so a single
  `server.py` serves both a legacy `v1beta1` instance on `9000` and a modern `v2beta1`-only
  instance on `9001`. Prefer one parameterized `server.py` over a fork.
- **Set `Specificity` deliberately** in the aipostex probe (1–100): `100` = ultra-specific
  (e.g. Ollama), `85–95` = strong (most services), `40–70` = supporting, `20–35` = generic
  (e.g. an OpenAI-compatible `/v1/models`). Strong probes on a service's default port break the
  scan loop early, so don't over-claim specificity on a generic path.

If `aipostex` has no probe for your service yet, add the `ServiceProbe` to `BuiltinProbes()` in
the aipostex repo in the same change — the lab mock and the tool probe are two halves of one
contract.

---

## Step 2 — Wire systemd provisioning (`provision.sh`)

Add a block to the role's `provision.sh` that copies `server.py`, writes a unit, and starts it.
Follow the standard pattern exactly (mirroring the W&B and ChromaDB blocks):

```bash
# ── <Service> Mock ───────────────────────────────────────
echo "[*] Setting up <service> mock..."
sudo -u mluser mkdir -p /home/mluser/projects/<service>-mock
if [ -f "$(dirname "$0")/<service>-mock/server.py" ]; then
    cp "$(dirname "$0")/<service>-mock/server.py" /home/mluser/projects/<service>-mock/server.py
    chown mluser:mluser /home/mluser/projects/<service>-mock/server.py
fi

cat > /etc/systemd/system/<service>-mock.service << 'EOF'
[Unit]
Description=<Service> Mock Server
After=network.target

[Service]
User=mluser
WorkingDirectory=/home/mluser/projects/<service>-mock
ExecStart=/usr/bin/python3 server.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable <service>-mock
systemctl restart <service>-mock

wait_for_service "<Service> mock" "http://localhost:<PORT>/healthz" 20 <service>-mock
```

Notes:

- The unit name convention is `<service>-mock.service`, running as **`mluser`** from the copied
  working directory.
- `wait_for_service` (defined at the top of `provision.sh`) polls the health URL with `curl` up
  to **20 retries at 2-second intervals** and dumps `journalctl` for the unit on failure.
  Always pass the unit name as the fourth argument so a failed boot is diagnosable.
- For a **second instance** of the same server, add `Environment=` lines instead of a second
  `server.py`, as the `kubeflow-mock-v2` unit does with `Environment=KUBEFLOW_MOCK_PORT=9001`
  and `Environment=KUBEFLOW_API_MODE=v2`.

---

## Step 3 — Add runtime seeding if needed (`seed.sh`)

If your service holds runtime state that must be *loaded through its own API* (rather than baked
into `server.py` constants), add a seeding step to the role's `seed.sh`, which runs **after**
provisioning completes. The pattern gates on health, then runs a Python seeder against
`localhost`:

```bash
check_service <service>-mock "http://localhost:<PORT>/healthz" \
    && "${ML_RUNTIME_VENV}/bin/python3" "${SCRIPT_DIR}/seed_<service>.py" localhost <PORT>
```

`check_service <svc_name> <svc_url>` restarts the unit and re-polls if the first probe fails, so
seeding is resilient to a slow boot.

Most protocol mocks **do not need `seed.sh`** — their planted findings are static and belong
in `server.py` constants (the W&B mock's `RUNS` dict and the Kubeflow mock's `PIPELINES` list
embed the fake credentials directly). Use `seed.sh` only for real software whose data lives in
a datastore (ChromaDB, MLflow, Ray). Keep secrets clearly fake, e.g. `FAKE_...` /
`AKIAFAKE...` prefixes.

---

## Step 4 — Register the service in the ports matrix

Add a row to [`docs/reference/ports.md`](../reference/ports.md) under the correct host section,
matching the existing table columns (Port, Service, Systemd Unit):

```markdown
| <PORT> | <Service> mock | `<service>-mock.service` |
```

If the service is replicated on another host (e.g. Ollama on both `ailab-dev` and `ailab-ds`),
add the row under each host. The ports matrix is the single source of truth operators read;
an unlisted port is an unsupported port.

---

## Step 5 — Add a health-check entry to `service-catalog.sh`

`lab-scripts/lib/service-catalog.sh` lists every verifier health check as a **pipe-delimited
tuple** emitted by `inventory_service_health_checks()`:

```
host_alias|port|path|expect_string|display_name|optional_header
```

Add one line for your host. The `expect_string` is grepped **case-insensitively** against the
response body, so pick a stable substring the mock always returns (the W&B row greps `wandb`
from `/healthz`):

```
ailab-ml|<PORT>|/healthz|<expect-string>|<Service> mock|
```

The sixth field is an optional request header — use it only for a *deliberately gated* hop
(the LiteLLM-authed and A2A-authed rows pass `Authorization: Bearer ...`). Leave it empty for
the by-design-unauthenticated surfaces.

---

## Step 6 — Verify with `verify-lab.sh`

`verify-lab.sh` sources the catalog and runs each tuple through its `check()` function: a
`curl -sf --max-time 6`, optionally with your custom header, then a case-insensitive `grep`
for the expect string. No code change is needed — adding the tuple in Step 5 is enough. Run it
and confirm your row passes:

```bash
lab-scripts/verify-lab.sh
```

`check()` has one special case (MCP at `/mcp`, which POSTs a JSON-RPC `initialize` with SSE
`Accept` headers because the real Streamable-HTTP SDK has no GET health route). If your service
also lacks a plain GET health endpoint, model it on that branch rather than forcing a fake
`/healthz`. After adding your service, bump the health-check count in `docs/reference/ports.md`
and `docs/services/index.md` if the total changed.

---

## Step 7 — Create the service documentation page

Add a page at `docs/services/<role>/<service>.md` following the standard template (see
[`wandb.md`](../services/ml/wandb.md) / [`kubeflow.md`](../services/ml/kubeflow.md)). Front
matter is `title:` only; the H1 carries the `(ailab-<role>)` suffix. Keep sections terse —
two or three sentences each:

```markdown
---
title: <Service> Mock (ailab-<role>)
---

# <Service> Mock (ailab-<role>)

## What It Is
One or two sentences: what real product this models and why it's here.

## Surface
| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Health check |
| ... | ... |

## Port & Unit
| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `<PORT>` |
| Unit | `<service>-mock.service` |
| Runtime | `python3 server.py` |

## Seeded Data
- Bullet the planted findings (which credentials, in which fields).

## What aipostex Finds
- What the tool extracts (the finding), not how it probes.
```

Then register the page in the nav (below).

---

## Step 8 — Register the nav entries (`mkdocs.yml`)

Add the service page under the matching role subsection of the `Services` nav in `mkdocs.yml`,
in port order alongside its neighbours, e.g.:

```yaml
    - ailab-ml (ML Platform):
      ...
      - <Service> Mock: services/ml/<service>.md
```

---

## Mock fidelity & RRR honesty expectations

Two rules govern what a mock is allowed to be and to claim:

- **By-design unauthenticated is not a fidelity gap.** These services are *intentionally* open —
  the misconfiguration **is** the planted finding (shadow-AI sprawl left exposed). A fidelity
  audit will flag "no auth validation" against the real product, but adding auth here would
  **delete the scenario**. Keep the surface open unless it is a deliberately *gated* hop in the
  credential chain (the MLflow-auth and TGI gateways). See
  [Mock & Fixture Fidelity](../reference/mock-fidelity.md).
- **RRR — "real result, or it didn't happen."** Detecting a protocol-accurate mock is a real
  result and belongs in the benchmark, labeled a **detection surface**. But a fixture must
  **never emit a credential-gate or state-change claim** — no canned "exploit succeeded",
  callback, or write-readback from a mock. If your mock introduces a new `module:action`, add
  it to `scoring/rrr_matrix.json` with the honest tier (`detection` → max `reachable`); the
  benchmark gate runs `--rrr-require-covered` and **fails the run** on an unclassified action or
  an over-claimed `landed` value. See the [RRR Honesty Matrix](../scoring/rrr.md).

If you want to *prove* a real capability (a real read, write, or execution) rather than
detection, the mock is the wrong tool — deploy the real software (as the A2A `a2a-sdk` agent on
`8103` and the real MCP SDK server on `dev:3000` do) and validate `aipostex` against true
protocol behaviour.

---

## Testing & validation workflow

Run these in order; each gate must pass before the service is done:

1. **Local smoke.** `python3 server.py` locally, then `curl` the probe paths (the health path
   and every path in the aipostex probe) and confirm status + body match the `HTTPProbe`.
2. **Provision on the role VM.** Run `provision.sh`; confirm `wait_for_service` reports ready
   and `systemctl status <service>-mock` is active.
3. **Seed** (if applicable) and confirm the runtime data loaded.
4. **Verify.** Run `verify-lab.sh`; your new row must be green.
5. **Fingerprint.** Point `aipostex` at the host and confirm the service is identified at the
   expected specificity, ideally in the [single-service sandbox](../sandbox.md) first.
6. **RRR.** Run the benchmark gate and confirm no over-claim and no uncovered `module:action`.
