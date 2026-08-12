---
title: Elastic Detection Stack (ailab-siem)
---

# Elastic Detection Stack (ailab-siem)

## What It Is

The lab's **real detection surface** — a genuine Elastic Security deployment (Elasticsearch +
Kibana + host agents), replacing the earlier lightweight `ai-siem` mock. This is the detection a
realistic target enterprise would field: ingest host + application telemetry, run detection rules,
raise alerts.

Runs on a **dedicated, persistent VM** (`ailab-siem`, `172.16.50.60`) that is **not** rolled by
`reset-wave` — detection infrastructure stays up continuously while the target VMs get reset. The
Beats agents on the target hosts are baked into `lab-ready`, so they survive a reset and reconnect
on boot.

## Components

| Component | Where | Purpose |
|---|---|---|
| Elasticsearch 8.19 | `ailab-siem:9200` | Store + search + detection engine |
| Kibana 8.19 | `ailab-siem:5601` | Elastic Security UI, rules, alerts |
| Auditbeat | each target host | Endpoint telemetry: process, socket, user, `auditd` (execve, FIM) |
| Filebeat | each target host | Auth/syslog + application event logs (`/var/log/aipostex/*.jsonl`) |

Lab posture: single-node, **security enabled** (required for the Detection Engine) but HTTP/transport
TLS **off** (isolated subnet — auth over plain HTTP, no certs). Login: `elastic` /
`_rw*oVdZSeBz5vksgFA-`.

## What It Detects

- **Endpoint (the tool's real impact):** reverse shells and suspicious process spawns (Auditbeat
  `system/process` + `auditd execve`), the Ollama→root privesc (FIM on `/usr/local/bin` +
  `/etc/passwd` + sudo/auth events), Jupyter/k8s code-exec.
- **Application layer:** prompt injection, document/source enumeration, RAG poisoning, and
  secret-in-output — via the apps' event logs shipped by Filebeat and matched by custom detection
  rules.

## Using It

```bash
# Kibana (Elastic Security): http://172.16.50.60:5601  (elastic / _rw*oVdZSeBz5vksgFA-)

# What's landing (from the attack box or proxmox):
curl -s -u elastic:_rw*oVdZSeBz5vksgFA- \
  'http://172.16.50.60:9200/_cat/indices/auditbeat*,filebeat*?v&h=index,docs.count'

# Detect/evade loop: run a tool action, then check Elastic for the alert it raised.
```

See [Scenario 16](../../attack-scenarios/scenario-16.md) (detect & evade, now against real Elastic).
