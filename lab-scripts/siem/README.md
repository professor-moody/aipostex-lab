# Elastic Detection Stack (`ailab-siem`)

The lab's **real** detection surface — a genuine Elastic Security deployment (Elasticsearch +
Kibana + Beats on the target hosts), replacing the earlier `ai-siem` mock. It ingests endpoint
and application telemetry, runs detection rules, and raises alerts, so the tool's actions can be
run against a detection stack that behaves like a real one.

Runs on a **dedicated, persistent VM** (`ailab-siem`, `.60`) that is **not** rolled by
`reset-wave` — detection infrastructure stays up while the target VMs reset. The Beats agents on
the target hosts are baked into `lab-ready`, so they survive a reset and reconnect on boot.

## Layout

| File | Runs on | Purpose |
|---|---|---|
| `install-elasticsearch.sh` | SIEM VM | Elasticsearch 8.x — single-node, security on, TLS off |
| `install-kibana.sh` | SIEM VM | Kibana 8.x — Elastic Security UI + Detection Engine |
| `load-detection-rules.sh` | anywhere w/ HTTP to Kibana | Import `detection-rules.ndjson` |
| `detection-rules.ndjson` | — | The 5 detection rules (round-trip export from Kibana) |
| `beats/filebeat.yml` | target host (template) | App JSONL (`ai.*`) + auth/syslog → ES |
| `beats/auditbeat.yml` | target host (template) | Process/socket/user/login + File Integrity → ES |
| `install-beats.sh` | target host | Install + render + start Filebeat & Auditbeat |

Credentials (`ELASTIC_PASSWORD`, `KIBANA_PASSWORD`) are supplied via env at install time and live
in the operator notes — never committed here.

## Build order

```bash
# On the SIEM VM (.60):
sudo ELASTIC_PASSWORD=… KIBANA_PASSWORD=… bash install-elasticsearch.sh
sudo SIEM_HOST=172.16.50.60 KIBANA_PASSWORD=… bash install-kibana.sh
SIEM_HOST=172.16.50.60 ELASTIC_PASSWORD=… bash load-detection-rules.sh

# On each target host (.10 .20 .30 .40 .50) — also called from base-setup.sh:
sudo SIEM_HOST=172.16.50.60 ELASTIC_PASSWORD=… bash install-beats.sh
```

## Detection rules

| rule_id | Severity | Fires on |
|---|---|---|
| `aipostex-revshell-indicators` | high | `process.args` contains `/dev/tcp` or `/dev/udp` (reverse shell) |
| `aipostex-fim-sensitive-path` | high | File Integrity change in `/usr/local/bin`, `/etc/passwd`, sudoers, cron, `/root/.ssh` |
| `aipostex-app-prompt-injection` | high | Injection / output-encoding-bypass phrasing in `ai.query` |
| `aipostex-app-kb-enumeration` | medium | Knowledge-base / secret enumeration phrasing in `ai.query` |
| `aipostex-app-rag-ingestion` | medium | `ai.event_type:ingest` (RAG poisoning surface) |

### Field mapping gotcha (why app fields are namespaced under `ai.*`)

The apps write events as JSON lines to `/var/log/aipostex/*.jsonl` with a scalar `source` field
(e.g. `"rag-app"`). ECS maps `source` as an **object**, so placing app fields at the document root
makes Elasticsearch 400-reject every app event — they silently never land. Filebeat's ndjson parser
nests them under `ai.*` (`parsers: [{ndjson: {target: "ai"}}]`), so `source` becomes `ai.source`
and the collision disappears. Detection rules therefore key on `ai.query`, `ai.event_type`, etc.

`ai.query` maps as a **keyword**, so substring detection uses KQL wildcards
(`ai.query:*reveal*`), not analyzed phrase matching.

## Detect / evade loop

Run a tool action against a target, then check Elastic for the alert it raised:

```bash
curl -s -u "elastic:${ELASTIC_PASSWORD}" \
  'http://172.16.50.60:9200/.alerts-security.alerts-default*/_search' \
  -H 'Content-Type: application/json' \
  --data '{"query":{"wildcard":{"kibana.alert.rule.tags":"aipostex"}},"aggs":{"r":{"terms":{"field":"kibana.alert.rule.name"}}},"size":0}'
```
