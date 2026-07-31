---
title: Vector Database Seeds
---

# Vector Database Seeds

Three vector databases across two hosts hold planted sensitive data alongside noise collections. Each database is seeded by a dedicated Python script that runs after the service is provisioned.

---

## ChromaDB (ailab-ml, port 8000)

Seeded by `seed_chromadb.py` using the ChromaDB venv Python (`/opt/chromadb/venv/bin/python3`). Four collections — three sensitive, one noise.

### acme-knowledge-base (12+ documents)

The primary RAG knowledge base. Contains a mix of PII, credentials, financial data, and adversarial prompt injection payloads.

| Category | Key Data |
|---|---|
| SSNs | `456-78-9012`, `789-01-2345` |
| Salaries | $145K, $162K (with employee names) |
| VPN Monitoring Creds | `svc-vpn-mon` / `VpnM0n1t0r!ng2024` |
| DB Credentials | `bi_reader` / `B1R3ader!Pr0d`, full connection string to `db-prod-01.acme.internal` |
| VPN Admin | `admin` / `F0rt1G4te@dm1n!` |
| AWS Account IDs | `123456789012`, `987654321098`, `111222333444` |
| Grafana Admin | `admin` / `Gr4f4n4@dm1n` |
| Q3 Financials | CONFIDENTIAL — $42.3M revenue, IPO target Q2 2027 |
| M&A Analysis | RESTRICTED — DataFlow Inc acquisition, $85M, board vote Dec 15 |
| Slack Bot Token | `xoxb-...` |
| GitHub PAT | `ghp_...` |
| Datadog API Key | Monitoring integration key |
| PagerDuty API Key | Incident response integration |
| Sentry DSN | Error tracking integration |
| Prompt Injections | Adversarial documents designed to manipulate LLM behavior |

!!! warning "Prompt Injection Payloads"
    The `acme-knowledge-base` collection includes adversarial documents alongside legitimate sensitive data. These test a distinct finding category: stored prompt injection attacks that could manipulate any LLM using this collection for RAG retrieval.

### support-tickets-2025 (5 documents)

Customer support tickets with PII and credentials left in ticket notes.

| Category | Key Data |
|---|---|
| Credit Card (Visa) | Ending `4242` |
| Credit Card (Mastercard) | Ending `1234`, exp `08/2027` |
| SSN | `321-54-9876` |
| Temp Password | `TmpPwd!2025#Reset` |
| Provisioned API Key | `gt_api_key_FAKE_9f8e7d6c5b4a3210` |
| Passport | `DE-FAKE-12345678` |

### code-documentation (3 documents)

Internal developer documentation with credentials embedded in setup guides.

| Category | Key Data |
|---|---|
| Dev Admin Creds | `admin` / `AdminDev2024!` |
| AWS Secrets Manager | ARN referencing production secrets |
| Emergency IAM User | `emergency-access` / `EmrgAcc3ss!2024` |

### public-documentation (noise)

5–8 documents of benign reference material. Open-source library docs, public API references, and marketing copy. **No credentials or PII.** See [Noise Collections](noise.md).

---

## Weaviate (ailab-ds, port 8080)

Seeded by `seed_weaviate.py`. Three classes — two sensitive, one noise.

### ResearchDocument (6 objects)

Research notes and infrastructure documentation from the data science team.

| Category | Key Data |
|---|---|
| PostgreSQL | `postgresql://ds_readonly:DsR34d0nly!Pr0d@...` |
| Snowflake | `ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com` |
| Zendesk API Key | Customer support integration |
| Redis Auth | `FeatSt0re!R3dis` |
| OpenAI Key | Used for model distillation |
| W&B Key | Experiment tracking |
| Airflow Admin | `airflow_admin` / `A1rfl0w@dm1n2024` |
| Stripe LIVE Key | `sk_live_FAKE_stripe_1234567890abcdef` |
| Salesforce OAuth | CRM integration credentials |
| HubSpot Key | Marketing automation |
| Intercom Token | Customer messaging |

### TeamCommunication (6 objects)

Internal team messages — Slack exports and email threads containing PII and sensitive business data.

| Category | Key Data |
|---|---|
| SSNs | `567-89-0123`, `890-12-3456`, `234-56-7891` (new hire onboarding) |
| Salaries | $175K, $140K, $155K with employee names and stock grants |
| HR Admin | `hr_admin` / `HrAdm1n!2024` |
| CFO Credit Card | Corporate card ending `8901` |
| Board AI Strategy | Headcount reduction plans — sensitive executive communications |

### PublicKnowledge (noise)

Public dataset descriptions and Wikipedia-style articles. **No sensitive data.** See [Noise Collections](noise.md).

---

## Qdrant (ailab-ds, port 6333)

Seeded by `seed_qdrant.py`. Three collections — two sensitive, one noise.

### product-catalog (4 points)

Internal product and licensing information with embedded admin credentials.

| Category | Key Data |
|---|---|
| License Server Admin | `license_admin` / `L1c3ns3Adm!n` |
| SaaS DB Creds | `postgresql://saas_app:S44sAppPr0d!@...` |
| Stripe Billing Key | `sk_live_FAKE_saas_billing_abcdef123456` |
| Vault Token | `hvs.FAKE_vault_token_abcdef1234567890` |

### security-findings (6 points)

Internal security reports and incident response documentation.

| Category | Key Data |
|---|---|
| Pentest Report | Lists ALL lab hosts by IP with services — a meta finding describing the environment being exploited |
| IR Playbook | Break-glass procedures and emergency access |
| Network Switch Creds | `admin` / `C1sc0@dm1n!2024` |
| AWS Backup Key | `AKIAFAKEBACKUP123456` |

!!! tip "The Meta Finding"
    The `security-findings` collection contains a pentest report that describes the exact lab environment — hosts, IPs, services, and vulnerabilities. When aipostex extracts this, the demo audience sees a pentest report about the infrastructure being exploited in real time.

### public-faq (noise)

Generic Q&A content. **No sensitive data.** See [Noise Collections](noise.md).
