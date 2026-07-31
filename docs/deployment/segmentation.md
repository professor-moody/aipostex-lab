---
title: Opt-in Network Segmentation
---

# Opt-in network segmentation (experimental)

The default lab is **flat**: every host is reachable at enumeration (the shadow-AI
premise), and that flat estate is the **validated benchmark** premise. The guided
credential chain ([Scenario 08](../attack-scenarios/scenario-08.md)) demonstrates
*credential chaining through gated services* — the MLflow auth gateway
(`ailab-ds:5000`) and the TGI gateway (`ailab-app:8180`) each require a credential
looted from the prior hop. The separate MLflow **platform backend**
(`ailab-ml:5000`) is directly reachable by design — it is the exposed-backend path
that [Scenario 06](../attack-scenarios/scenario-06.md)/[10](../attack-scenarios/scenario-10.md)
use, not a gateway bypass.

If you want an **enterprise feel** where that credential-gated hop is *also*
enforced at the network layer, enable the opt-in segmentation toggle. It is
**off by default** and is **not part of the scored benchmark** — leave it disabled
for standard runs. (Hard, multi-zone segmentation lives in the
[Enterprise lab line](enterprise-readiness.md); this is the lightweight
single-rule version.)

## What it does

`lab-scripts/segmentation.sh` adds one `iptables` rule on `ailab-ml` that DROPs
traffic **from the attack box (`172.16.50.99`) to the MLflow backend port (5000)**.
The credential-gated gateway path (`ailab-ds:5000`, which proxies upstream) is
unaffected, so:

- direct `aipostex mlflow --target http://172.16.50.20:5000 …` from the attack box is **refused**, and
- the chained path `aipostex mlflow --target http://172.16.50.30:5000 --header "Authorization: Basic …"` still works.

## Enable / disable

```bash
# On ailab-ml (or via proxmox: ssh labadmin@172.16.50.20 'sudo bash ~/lab/segmentation.sh …')
sudo bash segmentation.sh enable     # block direct backend access from the attack box
sudo bash segmentation.sh status
sudo bash segmentation.sh disable    # restore the flat default
```

The rule is not persisted across reboots (deliberately — a reboot returns to the
flat default).

## Verify

```bash
# From the attack box, with the toggle on:
AIPOSTEX_SEGMENTATION=1 bash verify-chain.sh
```

The chain verifier adds two checks when `AIPOSTEX_SEGMENTATION=1`: the direct
backend (`ailab-ml:5000`) is refused from the attack box, and the gated gateway
(`ailab-ds:5000`) still answers. Without the env var, the standard chain
verification is unchanged.
