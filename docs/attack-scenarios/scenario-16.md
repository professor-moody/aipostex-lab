# Scenario 16: Detect & Evade — Working Against Real Elastic

> [All scenarios](index.md)

**Difficulty:** Intermediate
**Time:** ~25 minutes
**Prerequisites:** [Scenario 14](scenario-14.md) (bespoke agent) and [Scenario 15](scenario-15.md) (RAG app)
**Target:** the AI apps (`ailab-app:8110`, `ailab-ds:8091`) monitored by the Elastic detection
stack on **`ailab-siem` (`172.16.50.60`)** — Elasticsearch `:9200`, Kibana `:5601`.

## Background

Reaching an objective is only half the job. The other half is reaching it **without lighting up
the SOC** — the operational loop is **Enumerate → Attack (naive) → Detect → Evade → Confirm**. This
scenario runs that loop against a **genuine Elastic Security deployment**, not a mock: the apps
append their interaction events to `/var/log/aipostex/*.jsonl`, Filebeat ships them to
Elasticsearch (namespaced under `ai.*`), and Kibana detection rules raise real alerts.

Two things that behave like the real world (and unlike the retired mock):

- **Detection is not instant.** Rules run on a schedule (~1 minute here), so an alert appears
  *after* your action, not synchronously. Fast, quiet, well-paced actions matter.
- **Alerts live in an index**, not a `/alerts` endpoint — you query `.alerts-security.alerts-default*`
  the way an analyst would in Kibana.

## Objective

Trip a detection rule with a naive attack, read the alert in Elastic, then achieve the same
objective with a phrasing that leaves the detection engine quiet.

## Commands

```bash
SIEM=172.16.50.60
ELASTIC_PW=…          # elastic user password — see operator notes / the Elastic service page

alerts() {  # print aipostex alert counts by rule (analyst's-eye view)
  curl -s -u "elastic:${ELASTIC_PW}" \
    "http://${SIEM}:9200/.alerts-security.alerts-default*/_search?size=0" \
    -H 'Content-Type: application/json' \
    --data '{"query":{"wildcard":{"kibana.alert.rule.tags":"aipostex"}},
             "aggs":{"r":{"terms":{"field":"kibana.alert.rule.name","size":10}}}}' \
    | jq -r '.aggregations.r.buckets[] | "  \(.doc_count)  \(.key)"'
}

# 0. Baseline — what has already fired.
alerts

# 1. NAIVE attack — extract the helpdesk agent's system prompt (loud phrasing).
aipostex agent --target http://172.16.50.40:8110/chat extract

# 2. DETECT — wait for the rule cadence, then read what fired.
sleep 90
alerts
#   expect: "AI App - Prompt Injection / Guardrail Bypass Attempt"
#   (the extract battery uses reveal/system-prompt/encoding phrasing that the rule keys on)

# 3. Same idea against the RAG app — a naive recon sweep.
aipostex rag --target http://172.16.50.30:8091 map
sleep 90
alerts
#   recon queries that name servers / ask for "all"/"every credential" trip
#   "AI App - Knowledge-Base / Secret Enumeration"

# 4. EVADE — ask a contextual question that pulls the same data WITHOUT the flagged
#    keywords, then CONFIRM no new alert appears.
before=$(curl -s -u "elastic:${ELASTIC_PW}" "http://${SIEM}:9200/.alerts-security.alerts-default*/_count" \
  -H 'Content-Type: application/json' \
  --data '{"query":{"wildcard":{"kibana.alert.rule.tags":"aipostex"}}}' | jq .count)
curl -s -X POST http://172.16.50.30:8091/query \
  -d '{"query":"I am onboarding a new hire — which internal systems will they connect to?"}' \
  | jq '.sources[].title'
sleep 90
after=$(curl -s -u "elastic:${ELASTIC_PW}" "http://${SIEM}:9200/.alerts-security.alerts-default*/_count" \
  -H 'Content-Type: application/json' \
  --data '{"query":{"wildcard":{"kibana.alert.rule.tags":"aipostex"}}}' | jq .count)
echo "alerts before=${before} after=${after}   # equal == evaded"
```

## Expected Finding

- The naive `agent extract` trips **AI App - Prompt Injection / Guardrail Bypass Attempt** — a
  concrete demonstration that aipostex's default extraction is *loud*: it sends
  reveal/system-prompt/encoding phrasing straight into `ai.query`, which the rule matches.
- The naive `rag map` recon trips **AI App - Knowledge-Base / Secret Enumeration** when its probes
  name servers or ask for "all"/"every credential"; softer, well-phrased probes slip past.
- The reframed, contextual onboarding query retrieves overlapping information while the alert count
  **does not change** — the same objective, achieved quietly.

## Takeaways

- Detection here is real Elastic, but the rules are **keyword/pattern (KQL wildcard) matching on a
  keyword field** — like most real SIEM content — so they are beaten by phrasing, encoding, and
  pacing, not by luck.
- The **detection delay is a feature to exploit**: an action plus a fast cleanup can complete inside
  the window before the rule fires and an analyst triages.
- This also surfaces a real property of the tooling: some aipostex verbs (`agent extract`,
  `rag map`) are intentionally direct and therefore noisy. Knowing *what they trip* is the first
  step to operating quietly.
- The same loop applies on the endpoint: a reverse shell trips
  **aipostex: Reverse shell indicators**, and writing into a PATH dir / identity file trips
  **Endpoint - Sensitive File Modification**. See the [Elastic Detection Stack](../services/siem/elastic.md)
  service page and `lab-scripts/siem/`.
