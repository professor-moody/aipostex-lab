---
title: Precision Benchmark
---

# Precision Benchmark

`score.py` answers *"did the tool find the planted data?"* — coverage, which is a form of
recall. It cannot answer the opposite question, because a coverage manifest has no negative
side:

> **Does the tool claim success when there is nothing to find?**

That is what this benchmark measures. Several lab services run as **pairs**: an exposed
instance and a hardened twin that enforces authentication. The same verb runs against both.
On the exposed instance a success claim is correct. On the hardened twin the identical claim
is a **false positive** — authentication held, so the tool never got in.

Run it with `lab-scripts/scoring/benchmark.py`.

## What counts as a claim

The unit of measurement is a **success claim**: any finding whose `landed` grade is above
`reachable` — `read-confirmed`, `influenced`, `execution-confirmed`, or `takeover-capable`.
Those grades assert the tool *achieved* something.

Findings graded `recon` / `reachable` are observations about the target ("the port answered",
"this model is listed"), not claims of access, and are never scored either way.

| | Success claim present | No success claim |
|---|---|---|
| **Exposed instance** | TP — real weakness, correctly claimed | FN — real weakness, missed |
| **Hardened twin** | **FP — claimed access it never got** | TN — correct restraint |

## Two kinds of verb

The distinction is load-bearing, and getting it wrong produces a benchmark that lies in the
opposite direction — accusing the tool of misses it did not make.

- **Access verbs** (`k8s secret-read`, `mlflow runs`, `litellm config-extract`,
  `a2a task-send`, `k8s rbac-probe`) succeed by reading or changing something, so on the
  exposed side they *must* produce a claim. Silence there is a genuine false negative. Scored
  on both sides.
- **Enumeration verbs** (`k8s enum`, `litellm enum`, `mlflow experiments`) list what an open
  service exposes. That is correctly graded `reachable`, so the exposed side has no claim to
  make and silence is *not* a miss. Scored on the hardened side only — an enumeration verb
  that claims access against an authenticated service is a false positive like any other.

Which verbs fall into which class was determined by running them and reading the grades they
emit, not by assumption.

## Results

Latest run — aipostex **v1.10.0**, 19 cases across 11 modules:

| TP | FP | FN | TN | Precision | Recall | FP rate on hardened |
|---|---|---|---|---|---|---|
| 12 | 0 | 0 | 19 | 100.0% | 100.0% | 0.0% |

| Module | TP | FP | FN | TN | Exposed / hardened pair |
|---|---|---|---|---|---|
| k8s | 2 | 0 | 0 | 3 | anon-open k3s `:6443` / 401-enforced k3s `:6444` |
| litellm | 1 | 0 | 0 | 2 | open proxy `:4000` / key-enforced proxy `:4001` |
| mlflow | 1 | 0 | 0 | 2 | open tracking server / Basic-auth gateway |
| a2a | 1 | 0 | 0 | 1 | unauthenticated agent `:8100` / auth-enforcing agent `:8102` |
| jupyter | 1 | 0 | 0 | 2 | token-less Jupyter `:8888` / token-enforced Jupyter `:8890` |
| mcp | 1 | 0 | 0 | 2 | open MCP server `:3000` / bearer-enforced MCP `:3003` |
| ray | 1 | 0 | 0 | 1 | open Ray dashboard `:8265` / auth-enforcing endpoint |
| ollama | 1 | 0 | 0 | 1 | open Ollama `:11434` / auth-enforcing endpoint |
| vectordb | 1 | 0 | 0 | 2 | open Qdrant `:6333` / API-key-enforced Qdrant `:6335` |
| gradio | 1 | 0 | 0 | 2 | open Gradio `:7860` / login-enforced Gradio `:7861` |
| openai-compat | 1 | 0 | 0 | 1 | open OpenAI-compatible `:8182` / key-enforced proxy `:4001` |

Every access verb claimed correctly against the exposed instance and stayed silent against
its hardened twin. Across **19 hardened controls the tool made zero false access claims.**

### About the Ray and Ollama controls

Ray's dashboard and Ollama's API ship with no authentication at all, so neither has a
"hardened twin" in the sense the other pairs do. Their control is instead a service that
answers HTTP and refuses unauthenticated callers — the bearer-enforced MCP endpoint. That
tests the property the benchmark cares about (does the module claim access against a host
that rejected it?) but it is a weaker pairing than the others, where the twin runs the same
product with its own auth turned on. Read those two rows accordingly.

## The controls

Four controls exist purely so this benchmark has a negative side. They are **not targets**,
and each uses the real product's own mechanism rather than a proxy in front:

| Control | Port | Mechanism | Refuses with |
|---|---|---|---|
| `jupyter-secure.service` | `8890` | JupyterLab's own token protection, switched back on | `403` |
| `acme-mcp-secure.service` | `3003` | The MCP SDK stack + bearer middleware, per the MCP authorization spec | `401` + `WWW-Authenticate` |
| `gradio-secure.service` | `7861` | Gradio's own `auth=` login | `401` |
| `qdrant-secure.service` | `6335` | Qdrant's own `service.api_key` | `401` |

The `openai-compat` pair needed no new service: the key-enforced LiteLLM proxy on `:4001`
already refuses unauthenticated callers and speaks the same OpenAI-compatible API as the
exposed side.

`verify-lab.sh` asserts both still refuse unauthenticated callers, and counts a failure if
either stops. A control that quietly stopped enforcing would make this benchmark report a
clean run it had not earned.

## How to read these numbers honestly

- **The sample is small.** Nineteen cases over eleven modules. A 100% figure on nineteen
  cases is "nothing broken here", not a general accuracy claim.
- **Coverage is partial by construction.** Only modules with a hardened control can be measured
  this way — 11 of the tool's ~20. These numbers describe those modules and are *not*
  extrapolated to the rest.
- **A case counts a verb, not a finding.** A verb emitting twenty correct claims counts once,
  exactly like one emitting a single claim.
- **Recall here is narrow.** It is measured against the paired access cases only.
  `score.py` remains the broader coverage measure against the planted-data manifest.

The benchmark is a **regression gate**, and its value is in the run where a number moves. The
classification logic is unit-tested (`tests/test_benchmark.py`) precisely so a false positive
would be caught rather than silently scored as a pass; `benchmark.py` exits non-zero if any
FP appears.

## Extending it

Add a case to `CASES` in `lab-scripts/scoring/benchmark.py`. A case needs an exposed target, a
hardened twin that genuinely enforces auth, and an honest `expect_claim_on_vulnerable` — set
it by *running* the verb and reading the grades it emits, not by assuming what it should do.

The most useful way to widen this benchmark is to add hardened twins for modules that lack
one, since every new pair converts a module from unmeasurable to measured.
