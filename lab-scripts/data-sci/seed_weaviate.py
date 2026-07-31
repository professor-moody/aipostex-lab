#!/usr/bin/env python3
"""
seed_weaviate.py — Populate Weaviate with fake data science team data for aipostex testing.

Run after Weaviate is running on the data-sci VM:
    /opt/data-sci-seed/venv/bin/python3 seed_weaviate.py [host] [port]

Creates 3 classes (2 sensitive + 1 noise) with 160+ total objects containing:
    - Research notes with internal infrastructure references
    - Model experiment logs with API keys and endpoints
    - Internal communications with PII and credentials
    - Data pipeline configs with connection strings

All data is FAKE but realistic-looking.

Uses weaviate-client v4 API.
"""

import sys
import time

try:
    import weaviate
    from weaviate.classes.config import Property, DataType
except ImportError:
    print("[!] weaviate-client not installed. Run: /opt/data-sci-seed/venv/bin/python3 -m pip install 'weaviate-client>=4.9.0,<5.0.0'")
    sys.exit(1)

HOST = sys.argv[1] if len(sys.argv) > 1 else "localhost"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080

print(f"[*] Connecting to Weaviate at {HOST}:{PORT}...")

client = None
for attempt in range(15):
    try:
        client = weaviate.connect_to_local(host=HOST, port=PORT)
        if client.is_ready():
            print("[+] Connected to Weaviate (ready)")
            break
    except Exception as e:
        print(f"    Waiting for Weaviate... attempt {attempt+1}/15 ({e})")
        time.sleep(3)
        client = None

if client is None or not client.is_ready():
    print("[!] Failed to connect to Weaviate after 15 attempts")
    sys.exit(1)

meta = client.get_meta()
print(f"    Version: {meta.get('version', 'unknown')}")


# ═══════════════════════════════════════════════════════════
# Class 1: ResearchDocument — Data science team's internal notes
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'ResearchDocument' class...")

if client.collections.exists("ResearchDocument"):
    client.collections.delete("ResearchDocument")

research = client.collections.create(
    name="ResearchDocument",
    description="Internal data science research documents and notes",
    properties=[
        Property(name="title", data_type=DataType.TEXT),
        Property(name="content", data_type=DataType.TEXT),
        Property(name="author", data_type=DataType.TEXT),
        Property(name="classification", data_type=DataType.TEXT),
        Property(name="project", data_type=DataType.TEXT),
    ],
)

research_docs = [
    {
        "title": "Customer Churn Prediction Model — Training Data Sources",
        "content": (
            "The churn prediction model uses three data sources: "
            "1) Customer transaction history from the production PostgreSQL database "
            "(connection: postgresql://ds_readonly:DsR34d0nly!Pr0d@db-prod-01.acme.internal:5432/acme_prod). "
            "2) Support ticket sentiment data extracted from Zendesk via API "
            "(API key: zd_api_FAKE_abcdef1234567890). "
            "3) Product usage telemetry from the Segment data warehouse "
            "(connection: snowflake://ds_team:Sn0wfl4keDs!@acme.snowflakecomputing.com/ANALYTICS/RAW). "
            "Current model achieves 0.87 AUC on holdout set. "
            "Feature importance: login_frequency (0.23), ticket_count_30d (0.18), "
            "days_since_last_feature_use (0.15)."
        ),
        "author": "jane.doe@acme.corp",
        "classification": "INTERNAL",
        "project": "churn-prediction"
    },
    {
        "title": "Fraud Detection Pipeline — Architecture Notes",
        "content": (
            "Real-time fraud scoring pipeline deployed on Kubernetes (eks-prod-01). "
            "Input: transaction events from Kafka (kafka-prod.acme.internal:9092, topic: raw-transactions). "
            "Model served via Seldon Core (seldon.acme.internal:8080). "
            "Scoring threshold: 0.75 (auto-block), 0.50-0.75 (manual review queue). "
            "Redis cache for feature store: redis://feature-store.acme.internal:6379/2 "
            "(auth: FeatSt0re!R3dis). "
            "Monitoring: Grafana dashboard at grafana.acme.internal/d/fraud-scoring. "
            "PagerDuty service: pd-fraud-scoring (integration key: FAKE_PD_FRAUD_abc123). "
            "Monthly false positive rate: 2.3%. Estimated annual fraud prevented: $4.2M."
        ),
        "author": "bob.wilson@acme.corp",
        "classification": "CONFIDENTIAL",
        "project": "fraud-detection"
    },
    {
        "title": "LLM Fine-Tuning Experiment — GPT-4o Distillation Results",
        "content": (
            "Experiment: Distill GPT-4o responses into a smaller model for cost reduction. "
            "Training data: 50K prompt-response pairs generated from production traffic. "
            "OpenAI API key used for data generation: sk-proj-FAKE-distill-key-abcdef1234567890. "
            "Estimated API cost for dataset creation: $3,200. "
            "Student model: Llama-3-8B fine-tuned on 4x A100 (AWS p4d.24xlarge, $32.77/hr). "
            "Results: Student achieves 91% quality parity with GPT-4o at 1/20th the cost. "
            "Model artifacts stored in S3: s3://acme-ml-models/distill-llama3-8b-v2/. "
            "Weights & Biases project: https://wandb.ai/acme-ds/llm-distillation "
            "(API key: FAKE_wandb_key_distill_abcdef)."
        ),
        "author": "jane.doe@acme.corp",
        "classification": "CONFIDENTIAL",
        "project": "llm-cost-optimization"
    },
    {
        "title": "Data Pipeline — ETL Job Credentials and Schedules",
        "content": (
            "Nightly ETL jobs run via Airflow at airflow.acme.internal:8080 "
            "(admin credentials: airflow_admin / A1rfl0w@dm1n2024). "
            "Source systems and credentials: "
            "- Salesforce: sf_integration_user / SfInt3gr4t10n! (OAuth client_id: 3MVG9fake1234). "
            "- HubSpot: API key hs_api_FAKE_1234567890abcdef. "
            "- Stripe: sk_live_FAKE_stripe_1234567890abcdef (PRODUCTION KEY — handle with care). "
            "- Intercom: intercom_token_FAKE_abcdef1234567890. "
            "All credentials should be migrated to HashiCorp Vault (vault.acme.internal:8200) "
            "per security team directive JIRA-SEC-2847. Migration deadline: Q1 2026."
        ),
        "author": "data-engineering@acme.corp",
        "classification": "RESTRICTED",
        "project": "data-platform"
    },
    {
        "title": "Recommendation Engine — A/B Test Results Q3 2025",
        "content": (
            "A/B test comparing collaborative filtering vs. hybrid embedding approach. "
            "Test ran Sept 1-30 on 15% of production traffic. "
            "Results: Hybrid model increased click-through by 23% and revenue per session by 8.5%. "
            "Statistical significance: p < 0.001. "
            "Revenue impact estimate: +$2.1M annually at full rollout. "
            "Decision: Ship hybrid model to 100% by Oct 15. "
            "Embedding model served from internal Ollama instance (172.16.50.30:11434). "
            "Vector similarity search via Qdrant (172.16.50.30:6333, collection: product-embeddings)."
        ),
        "author": "ml-team@acme.corp",
        "classification": "INTERNAL",
        "project": "recommendations"
    },
    {
        "title": "Compliance Review — ML Model Inventory for SOC2 Audit",
        "content": (
            "Models in production requiring SOC2 documentation: "
            "1) Churn Prediction (owner: jane.doe@acme.corp) — uses PII, approved by privacy review. "
            "2) Fraud Scoring (owner: bob.wilson@acme.corp) — uses financial data, PCI-DSS scope. "
            "3) Recommendation Engine (owner: ml-team@acme.corp) — uses behavioral data. "
            "4) Document Summarizer (owner: eng-tools@acme.corp) — sends data to OpenAI API. "
            "   Concern: Customer documents may be sent to external LLM. "
            "   Risk rating: HIGH. Remediation: Deploy self-hosted model by Q1 2026. "
            "Auditor contact: Mark Stevens (mark.s@deloitte.com). "
            "Audit window: January 15-26, 2026. "
            "Data retention evidence required for all models. "
            "Encryption-at-rest evidence: KMS key arn:aws:kms:us-east-1:123456789012:key/audit-key-id."
        ),
        "author": "security-team@acme.corp",
        "classification": "CONFIDENTIAL",
        "project": "compliance"
    },
]

for doc in research_docs:
    research.data.insert(doc)
print(f"    [+] ResearchDocument: {len(research_docs)} sensitive objects loaded")


def generate_filler_research_docs(count=144):
    """Generate benign research documents for pagination testing."""
    projects = [
        "churn-prediction", "fraud-detection", "recommendations",
        "llm-cost-optimization", "data-platform", "compliance",
    ]
    authors = [
        "jane.doe@acme.corp", "bob.wilson@acme.corp",
        "ml-team@acme.corp", "data-engineering@acme.corp",
    ]
    classifications = ["INTERNAL", "CONFIDENTIAL", "INTERNAL"]
    templates = [
        (
            "Weekly Status Update — {project} Sprint {n}",
            "Sprint {n} summary for the {project} project. Completed {done} story points "
            "out of {total} planned. Velocity trending {trend} compared to last sprint. "
            "Key deliverables: model evaluation pipeline, data quality checks, feature "
            "engineering for v{ver}. Blockers: waiting on data access approval from IT. "
            "Next sprint focus: hyperparameter tuning and cross-validation framework."
        ),
        (
            "Experiment Log — {project} Iteration {n}",
            "Iteration {n} of the {project} experiment. Changed learning rate to {lr} "
            "and batch size to {bs}. Training completed in {hrs} hours on {gpu} GPU(s). "
            "Validation loss: {loss}. Compared to baseline: {delta}% improvement. "
            "Memory usage peaked at {mem}GB. Next step: try gradient accumulation "
            "with {accum} micro-batches to reduce memory footprint."
        ),
        (
            "Meeting Notes — {project} Design Review #{n}",
            "Design review #{n} for {project}. Attendees: engineering, product, QA. "
            "Discussed architectural options for the inference pipeline. Option A: "
            "synchronous REST API with {lat}ms p99 latency target. Option B: "
            "async queue-based with Kafka consumer. Decision deferred to next review. "
            "Action item: benchmark both approaches with production-like traffic patterns."
        ),
        (
            "Data Quality Report — {project} Dataset v{n}",
            "Dataset version {n} for {project}. Total records: {records}. "
            "Missing values: {missing}% (within acceptable threshold of 5%). "
            "Duplicate detection: {dupes} records flagged and deduplicated. "
            "Feature distribution analysis shows {skew} skew in primary features. "
            "Recommended pre-processing: standard scaling for numerical, one-hot for categorical."
        ),
        (
            "Performance Benchmark — {project} Model v{n}",
            "Benchmark results for model v{n} in {project}. Inference latency: "
            "p50={p50}ms, p95={p95}ms, p99={p99}ms. Throughput: {tps} requests/sec. "
            "CPU utilization: {cpu}% under load. Memory: {mem}GB resident. "
            "Comparison with previous version: {delta}% latency improvement. "
            "Meets SLA requirements for production deployment."
        ),
        (
            "Literature Review — {project} Related Work #{n}",
            "Literature review #{n} for {project}. Surveyed {papers} papers from "
            "NeurIPS, ICML, and AAAI proceedings. Key findings: attention-based "
            "architectures outperform RNN baselines by {margin}% on benchmark tasks. "
            "Promising approach: mixture-of-experts with {experts} expert modules. "
            "Applicable techniques for our use case: knowledge distillation, "
            "quantization-aware training, and structured pruning."
        ),
    ]
    docs = []
    for i in range(count):
        tmpl_title, tmpl_content = templates[i % len(templates)]
        proj = projects[i % len(projects)]
        n = (i // len(templates)) + 1
        fmt = dict(
            project=proj, n=n, done=8 + i % 12, total=15 + i % 10,
            trend="upward" if i % 3 else "stable", ver=f"{1 + i % 4}.{i % 10}",
            lr=f"0.{1 + i % 9:03d}", bs=16 * (1 + i % 4), hrs=2 + i % 8,
            gpu=1 + i % 4, loss=f"0.{200 + i % 300}", delta=1 + i % 15,
            mem=2 + i % 14, accum=2 + i % 6, lat=20 + i % 80,
            records=10000 + i * 500, missing=f"0.{1 + i % 9}",
            dupes=10 + i % 50, skew="moderate" if i % 2 else "slight",
            p50=5 + i % 20, p95=15 + i % 40, p99=30 + i % 70,
            tps=100 + i * 10, cpu=30 + i % 50, papers=5 + i % 20,
            margin=2 + i % 10, experts=4 + i % 8,
        )
        title = tmpl_title.format(**fmt)
        content = tmpl_content.format(**fmt)
        docs.append({
            "title": title,
            "content": content,
            "author": authors[i % len(authors)],
            "classification": classifications[i % len(classifications)],
            "project": proj,
        })
    return docs


print("[*] Inserting filler ResearchDocument objects for pagination testing...")
filler_docs = generate_filler_research_docs(144)
with research.batch.fixed_size(batch_size=50) as batch:
    for doc in filler_docs:
        batch.add_object(doc)
print(f"    [+] ResearchDocument: {len(filler_docs)} filler objects loaded (pagination)")


# ═══════════════════════════════════════════════════════════
# Class 2: TeamCommunication — Internal messages and memos
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'TeamCommunication' class...")

if client.collections.exists("TeamCommunication"):
    client.collections.delete("TeamCommunication")

comms_col = client.collections.create(
    name="TeamCommunication",
    description="Internal team communications and memos",
    properties=[
        Property(name="subject", data_type=DataType.TEXT),
        Property(name="content", data_type=DataType.TEXT),
        Property(name="sender", data_type=DataType.TEXT),
        Property(name="channel", data_type=DataType.TEXT),
        Property(name="sensitivity", data_type=DataType.TEXT),
    ],
)

comms = [
    {
        "subject": "Urgent: Exposed Ollama Instance on Dev Network",
        "content": (
            "Team — security scan found an Ollama instance on 172.16.50.10:11434 "
            "that's accessible from the entire office network. It has custom models "
            "with what looks like production credentials in the system prompts. "
            "I've asked the dev who set it up (Mike from Platform team) to restrict "
            "access but he says he needs it for his Claude Desktop integration. "
            "Can we get a firewall rule in place by EOD? "
            "Also the ML team's ChromaDB at 172.16.50.20:8000 has no auth either. "
            "I'm opening JIRA-SEC-2912 and JIRA-SEC-2913 for tracking."
        ),
        "sender": "security-analyst@acme.corp",
        "channel": "#security-alerts",
        "sensitivity": "INTERNAL"
    },
    {
        "subject": "RE: Budget Approval for GPU Cluster",
        "content": (
            "Approved. $180K for 8x H100 cluster (on-prem, Q1 2026 delivery). "
            "Vendor: Lambda Labs, PO #PO-2025-8847. "
            "Finance contact for invoicing: ap@acme.corp (Net 30 terms). "
            "Corporate card for deposit: ending 8901, cardholder Sarah Chen. "
            "Installation: Server room B, rack 14. Power: 2x 30A circuits. "
            "Network: Connect to ML VLAN (VLAN 50, 172.16.50.0/24). "
            "Note: This is specifically for the fine-tuning initiative. "
            "Do not use for general dev workloads — we need to track ROI separately."
        ),
        "sender": "sarah.chen@acme.corp",
        "channel": "email",
        "sensitivity": "CONFIDENTIAL"
    },
    {
        "subject": "New Hire Onboarding — Data Science Team",
        "content": (
            "Welcome packets for three new DS hires starting Jan 6, 2026: "
            "1) Alex Rivera — Senior ML Engineer. SSN: 567-89-0123 (for payroll setup). "
            "   Starting salary: $175,000. Stock grant: 15,000 RSUs (4yr vest). "
            "2) Priya Patel — Data Scientist II. SSN: 890-12-3456. "
            "   Starting salary: $140,000. Stock grant: 10,000 RSUs. "
            "3) Marcus Lee — ML Ops Engineer. SSN: 234-56-7891. "
            "   Starting salary: $155,000. Stock grant: 12,000 RSUs. "
            "HR system access: hr-portal.acme.internal (admin: hr_admin / HrAdm1n!2024). "
            "All three need AWS console access (IAM), GitHub org invite, and Slack."
        ),
        "sender": "hr-onboarding@acme.corp",
        "channel": "email",
        "sensitivity": "CONFIDENTIAL"
    },
    {
        "subject": "Incident Post-Mortem: Model Serving Outage (Nov 2)",
        "content": (
            "Root cause: Seldon Core deployment exceeded memory limits when the "
            "recommendation model loaded a new checkpoint (2.3GB vs 1.5GB allocated). "
            "OOM killer terminated the pod, no replica was available (single-replica deployment). "
            "Impact: Recommendation API returned 503 for 47 minutes. "
            "Estimated revenue impact: $12,000 (based on avg revenue/hr during outage window). "
            "Action items: "
            "1) Increase memory limit to 4GB (done). "
            "2) Add second replica (in progress, JIRA-ML-1204). "
            "3) Set up canary deployment for model updates (JIRA-ML-1205). "
            "4) Add PagerDuty alert for memory > 80% (done, using key FAKE_PD_ML_xyz789). "
            "Next review: Dec 1, 2025."
        ),
        "sender": "sre-team@acme.corp",
        "channel": "#incident-postmortem",
        "sensitivity": "INTERNAL"
    },
    {
        "subject": "Vendor Evaluation: Vector Database Migration",
        "content": (
            "Evaluating Pinecone vs Weaviate vs Qdrant for production vector search. "
            "Current setup: ChromaDB on 172.16.50.20 (no auth, no replication, single node). "
            "This is NOT production-grade and was only meant for prototyping. "
            "Pinecone trial: API key pcsk_EVAL_trial_abcdef1234567890. "
            "Weaviate Cloud trial: wcs_EVAL_key_1234567890abcdef. "
            "Qdrant Cloud trial: qdrant_EVAL_apikey_abcdef123456. "
            "Recommendation: Qdrant self-hosted for cost, Pinecone for managed simplicity. "
            "Budget: $2,400/mo for managed, $800/mo for self-hosted (3-node cluster). "
            "Decision needed by Dec 15. Stakeholders: David Kim (CTO), Lisa Park (VP Eng)."
        ),
        "sender": "bob.wilson@acme.corp",
        "channel": "#ml-platform",
        "sensitivity": "INTERNAL"
    },
    {
        "subject": "CONFIDENTIAL: Board Deck — AI Strategy 2026",
        "content": (
            "Draft board presentation on AI strategy: "
            "1) Self-hosted LLM initiative: Replace OpenAI dependency with fine-tuned Llama. "
            "   Projected savings: $1.2M/yr in API costs. "
            "   Investment required: $180K hardware + $350K headcount (2 ML engineers). "
            "2) AI-powered customer support: Automate 40% of Tier 1 tickets. "
            "   Expected headcount reduction: 8-12 support agents (savings: $800K-1.2M/yr). "
            "   SENSITIVITY NOTE: Do not share headcount reduction numbers externally. "
            "3) Competitive intelligence: Competitors using AI — TechRival Inc (raised $50M "
            "   for AI features), DataPeer Corp (acquired AI startup for $30M). "
            "Board meeting: January 28, 2026. "
            "Presenter: Michael Torres (CEO). Slide deck: gdrive/board/ai-strategy-2026-draft.pptx"
        ),
        "sender": "michael.torres@acme.corp",
        "channel": "email",
        "sensitivity": "RESTRICTED"
    },
]

for doc in comms:
    comms_col.data.insert(doc)
print(f"    [+] TeamCommunication: {len(comms)} objects loaded")


# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════
# Class 3: PublicKnowledge — NOISE (no sensitive data)
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'PublicKnowledge' class (noise)...")

if client.collections.exists("PublicKnowledge"):
    client.collections.delete("PublicKnowledge")

public_col = client.collections.create(
    name="PublicKnowledge",
    description="Public reference material and dataset descriptions",
    properties=[
        Property(name="title", data_type=DataType.TEXT),
        Property(name="content", data_type=DataType.TEXT),
        Property(name="source", data_type=DataType.TEXT),
        Property(name="category", data_type=DataType.TEXT),
    ],
)

public_docs = [
    {
        "title": "Introduction to Transformer Architecture",
        "content": (
            "The transformer architecture was introduced in 'Attention Is All You Need' (2017). "
            "It relies on self-attention mechanisms instead of recurrence. Key components include "
            "multi-head attention, positional encoding, and feed-forward layers. Transformers are "
            "the foundation for models like BERT, GPT, and T5."
        ),
        "source": "ml-textbook",
        "category": "reference"
    },
    {
        "title": "Common Machine Learning Evaluation Metrics",
        "content": (
            "Classification metrics: accuracy, precision, recall, F1-score, AUC-ROC. "
            "Regression metrics: MSE, RMSE, MAE, R-squared. "
            "Ranking metrics: MRR, NDCG, MAP. "
            "Always report metrics on a held-out test set to avoid overfitting."
        ),
        "source": "ml-textbook",
        "category": "reference"
    },
    {
        "title": "UCI Machine Learning Repository — Popular Datasets",
        "content": (
            "The UCI ML Repository hosts over 600 datasets. Popular ones include: "
            "Iris (150 samples, 4 features), Wine (178 samples, 13 features), "
            "Adult Census (48,842 samples), Boston Housing (506 samples). "
            "All datasets are publicly available at archive.ics.uci.edu/ml."
        ),
        "source": "public-datasets",
        "category": "datasets"
    },
    {
        "title": "Python Virtual Environments Best Practices",
        "content": (
            "Use virtual environments to isolate project dependencies. "
            "Options: venv (built-in), virtualenv, conda, poetry. "
            "Create: python -m venv .venv. Activate: source .venv/bin/activate. "
            "Always pin dependencies with pip freeze > requirements.txt."
        ),
        "source": "python-guide",
        "category": "best-practices"
    },
]

for doc in public_docs:
    public_col.data.insert(doc)
print(f"    [+] PublicKnowledge: {len(public_docs)} objects loaded (noise)")


# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════

print()
print("[+] ═══════════════════════════════════════════════")
print("[+] Weaviate seeding complete!")
print(f"[+] Host: {HOST}:{PORT}")
print("[+] ═══════════════════════════════════════════════")
print()

for col_name in ["ResearchDocument", "TeamCommunication", "PublicKnowledge"]:
    col = client.collections.get(col_name)
    count = col.aggregate.over_all(total_count=True).total_count
    print(f"    Class: {col_name}")
    print(f"      Objects: {count}")
    print()

client.close()

print("[+] Sensitive data planted for aipostex detection:")
print("    - SSNs: 567-89-0123, 890-12-3456, 234-56-7891")
print("    - Credit card: ending 8901")
print("    - Salaries: $175K, $140K, $155K (with names)")
print("    - Connection strings: postgresql://, redis://, snowflake://")
print("    - API keys: Stripe live key, Zendesk, HubSpot, Intercom, W&B, PagerDuty")
print("    - Airflow admin credentials")
print("    - Internal infrastructure IPs and hostnames")
print("    - M&A / board strategy data")
print("    - HR system admin credentials")
