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

Latest run — aipostex **v1.10.0**, 8 cases across 4 modules:

| TP | FP | FN | TN | Precision | Recall | FP rate on hardened |
|---|---|---|---|---|---|---|
| 5 | 0 | 0 | 8 | 100.0% | 100.0% | 0.0% |

| Module | TP | FP | FN | TN | Exposed / hardened pair |
|---|---|---|---|---|---|
| k8s | 2 | 0 | 0 | 3 | anon-open k3s `:6443` / 401-enforced k3s `:6444` |
| litellm | 1 | 0 | 0 | 2 | open proxy `:4000` / key-enforced proxy `:4001` |
| mlflow | 1 | 0 | 0 | 2 | open tracking server / Basic-auth gateway |
| a2a | 1 | 0 | 0 | 1 | unauthenticated agent `:8100` / auth-enforcing agent `:8102` |

Every access verb claimed correctly against the exposed instance and stayed silent against
its hardened twin. Across **8 hardened controls the tool made zero false access claims.**

## How to read these numbers honestly

- **The sample is small.** Eight cases over four modules. A 100% figure on eight cases is
  "nothing broken here", not a general accuracy claim.
- **Coverage is partial by construction.** Only modules with a hardened twin can be measured
  this way — 4 of the tool's ~20. These numbers describe those modules and are *not*
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
