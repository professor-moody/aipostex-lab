#!/usr/bin/env python3
"""
seed_pgvector.py — Populate PostgreSQL/pgvector with fake data for aipostex testing.

Run after PostgreSQL + pgvector are running on the data-sci VM:
    /opt/data-sci-seed/venv/bin/python3 seed_pgvector.py [host] [port]

Creates 4 tables in the "labdb" database:
    - employee_embeddings  (vector column + PII: names, SSNs, salaries)
    - document_chunks      (vector column + credentials, API keys, connection strings)
    - model_registry       (vector column + internal infra details, tokens)
    - audit_log            (NO vector column — plain text with credentials)

All data is FAKE but realistic-looking.
"""

import sys
import time

try:
    import psycopg2
except ImportError:
    print("[!] psycopg2 not installed. Run: pip install psycopg2-binary")
    sys.exit(1)

HOST = sys.argv[1] if len(sys.argv) > 1 else "localhost"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 5432
DATABASE = "labdb"

print(f"[*] Connecting to PostgreSQL at {HOST}:{PORT}/{DATABASE}...")

conn = None
for attempt in range(15):
    try:
        conn = psycopg2.connect(
            host=HOST, port=PORT, dbname=DATABASE,
            user="postgres", password="",
            connect_timeout=10,
        )
        conn.autocommit = True
        print("[+] Connected to PostgreSQL")
        break
    except Exception as e:
        print(f"    Waiting for PostgreSQL... attempt {attempt+1}/15 ({e})")
        time.sleep(3)
        conn = None

if conn is None:
    print("[!] Failed to connect to PostgreSQL after 15 attempts")
    sys.exit(1)

cur = conn.cursor()

# ── Verify pgvector extension ───────────────────────────────
cur.execute("SELECT 1 FROM pg_extension WHERE extname = 'vector'")
if cur.fetchone() is None:
    print("[!] pgvector extension not installed — creating it")
    cur.execute("CREATE EXTENSION IF NOT EXISTS vector")

print("[+] pgvector extension confirmed")


# ── Table 1: employee_embeddings (vector + PII) ────────────
print("[*] Creating employee_embeddings table...")
cur.execute("DROP TABLE IF EXISTS employee_embeddings CASCADE")
cur.execute("""
    CREATE TABLE employee_embeddings (
        id SERIAL PRIMARY KEY,
        full_name TEXT NOT NULL,
        email TEXT,
        department TEXT,
        ssn TEXT,
        salary TEXT,
        notes TEXT,
        embedding vector(384)
    )
""")

employees = [
    {
        "full_name": "Sarah Chen",
        "email": "sarah.chen@acme.corp",
        "department": "Engineering",
        "ssn": "123-45-6789",
        "salary": "$195,000",
        "notes": (
            "Senior ML engineer. Has access to production GPU cluster "
            "(ssh key: ~/.ssh/gpu-prod-key). Primary contact for model "
            "deployment pipeline. Emergency access code: ENG-8847-PROD."
        ),
    },
    {
        "full_name": "Marcus Johnson",
        "email": "marcus.johnson@acme.corp",
        "department": "Data Science",
        "ssn": "987-65-4321",
        "salary": "$182,000",
        "notes": (
            "Lead data scientist. Manages the feature store and has admin "
            "access to Snowflake (sf_admin / Sn0wAdm!n2024). Also maintains "
            "the Airflow DAGs for nightly model retraining."
        ),
    },
    {
        "full_name": "Lisa Park",
        "email": "lisa.park@acme.corp",
        "department": "Security",
        "ssn": "456-12-7890",
        "salary": "$210,000",
        "notes": (
            "CISO. Vault root token: hvs.FAKE_ciso_root_token_abcd1234. "
            "Has break-glass access to all production environments. "
            "PagerDuty escalation: FAKE_PD_CISO_ESCALATE_xyz123."
        ),
    },
    {
        "full_name": "Dev Patel",
        "email": "dev.patel@acme.corp",
        "department": "Platform",
        "ssn": "321-98-7654",
        "salary": "$175,000",
        "notes": (
            "Platform engineer. Manages Kubernetes clusters. "
            "AWS access: AKIAFAKEPGVEC12345678 / FAKE+PgvecSecret/abcdefghijk1234567890. "
            "Docker registry: registry.acme.internal (admin / Dock3rAdm!n)."
        ),
    },
    {
        "full_name": "Rachel Kim",
        "email": "rachel.kim@acme.corp",
        "department": "Finance",
        "ssn": "654-32-1098",
        "salary": "$165,000",
        "notes": (
            "Finance director. Has access to Stripe dashboard: "
            "sk_live_FAKE_pgvec_stripe_key_abcdef123456. "
            "QuickBooks API: qb_api_FAKE_finance_token_1234567890."
        ),
    },
]

for emp in employees:
    cur.execute(
        """INSERT INTO employee_embeddings
           (full_name, email, department, ssn, salary, notes)
           VALUES (%s, %s, %s, %s, %s, %s)""",
        (emp["full_name"], emp["email"], emp["department"],
         emp["ssn"], emp["salary"], emp["notes"]),
    )
print(f"[+] Inserted {len(employees)} employee records")


# ── Table 2: document_chunks (vector + credentials) ────────
print("[*] Creating document_chunks table...")
cur.execute("DROP TABLE IF EXISTS document_chunks CASCADE")
cur.execute("""
    CREATE TABLE document_chunks (
        id SERIAL PRIMARY KEY,
        doc_title TEXT NOT NULL,
        chunk_text TEXT NOT NULL,
        source_path TEXT,
        classification TEXT DEFAULT 'INTERNAL',
        embedding vector(384)
    )
""")

documents = [
    {
        "doc_title": "Production Database Runbook",
        "chunk_text": (
            "Primary PostgreSQL connection: "
            "postgresql://acme_app:Pr0dAppDB!2024@db-primary.acme.internal:5432/acme_prod. "
            "Read replica: postgresql://acme_ro:R3adR3pl1ca!@db-replica.acme.internal:5432/acme_prod. "
            "Failover procedure: Run `/opt/scripts/failover.sh` with sudo on jump-box.acme.internal."
        ),
        "source_path": "runbooks/database-operations.md",
        "classification": "CONFIDENTIAL",
    },
    {
        "doc_title": "ML Pipeline Configuration",
        "chunk_text": (
            "Feature store connection: redis://feature-store.acme.internal:6379 "
            "(auth: F34tureSt0re!R3dis2024). "
            "Model registry: mlflow.acme.internal:5000 (no auth required from VPN). "
            "Training data bucket: s3://acme-ml-training-data-prod "
            "(IAM role: arn:aws:iam::123456789012:role/ml-training-role)."
        ),
        "source_path": "pipelines/ml-config.yaml",
        "classification": "INTERNAL",
    },
    {
        "doc_title": "Vendor Integration Secrets",
        "chunk_text": (
            "SendGrid API key: SG.FAKE_pgvec_sendgrid_key.abcdef1234567890abcdef. "
            "Twilio SID: AC_FAKE_pgvec_twilio_sid_1234567890, "
            "Auth token: tw_FAKE_pgvec_auth_token_abcdef. "
            "Datadog API key: FAKE_DD_PGVEC_API_abcdef1234567890."
        ),
        "source_path": "integrations/vendor-keys.env",
        "classification": "RESTRICTED",
    },
    {
        "doc_title": "Kubernetes Cluster Access",
        "chunk_text": (
            "Production cluster: k8s-prod.acme.internal:6443. "
            "Service account token: eyJhbGciOiJSUzI1NiJ9.FAKE_K8S_TOKEN_pgvec_payload.signature. "
            "Namespace: acme-ml-serving. "
            "Registry pull secret: registry.acme.internal/v2/ "
            "(robot$acme-puller / R0b0tPull3r!2024)."
        ),
        "source_path": "infra/k8s-access.md",
        "classification": "CONFIDENTIAL",
    },
    {
        "doc_title": "Incident Response Playbook — Data Breach",
        "chunk_text": (
            "Page on-call: PagerDuty integration key: FAKE_PD_BREACH_RESPONSE_key123. "
            "Slack incident channel bot token: xoxb-FAKE-pgvec-slack-bot-token-1234567890. "
            "Legal hold contact: legal-hold@acme.corp (encryption key ID: 0xDEADBEEF). "
            "Evidence collection S3 bucket: s3://acme-ir-evidence-staging."
        ),
        "source_path": "security/ir-playbook-breach.md",
        "classification": "RESTRICTED",
    },
    {
        "doc_title": "Third-Party API Rate Limits",
        "chunk_text": (
            "OpenAI: sk-proj-FAKE-pgvec-openai-key-abcdef1234567890 (rate: 10k RPM). "
            "Anthropic: sk-ant-FAKE-pgvec-anthropic-key-abcdef1234567890 (rate: 5k RPM). "
            "Cohere: co-FAKE-pgvec-cohere-key-abcdef1234567890 (rate: 2k RPM). "
            "All keys rotate quarterly — next rotation 2025-Q3."
        ),
        "source_path": "integrations/llm-provider-limits.md",
        "classification": "INTERNAL",
    },
]

for doc in documents:
    cur.execute(
        """INSERT INTO document_chunks
           (doc_title, chunk_text, source_path, classification)
           VALUES (%s, %s, %s, %s)""",
        (doc["doc_title"], doc["chunk_text"], doc["source_path"],
         doc["classification"]),
    )
print(f"[+] Inserted {len(documents)} document chunks")


# ── Table 3: model_registry (vector + infra tokens) ────────
print("[*] Creating model_registry table...")
cur.execute("DROP TABLE IF EXISTS model_registry CASCADE")
cur.execute("""
    CREATE TABLE model_registry (
        id SERIAL PRIMARY KEY,
        model_name TEXT NOT NULL,
        version TEXT,
        description TEXT,
        serving_endpoint TEXT,
        config_notes TEXT,
        embedding vector(384)
    )
""")

models = [
    {
        "model_name": "acme-churn-predictor",
        "version": "3.2.1",
        "description": "Customer churn prediction using XGBoost",
        "serving_endpoint": "http://model-serve.acme.internal:8080/v1/churn",
        "config_notes": (
            "Training data: s3://acme-ml-data/churn/v3/ "
            "(AWS key: AKIAFAKEMODEL12345678). "
            "Monitoring: Grafana dashboard at grafana.acme.internal:3000 "
            "(admin / Gr4f4n4Ml@dm1n)."
        ),
    },
    {
        "model_name": "acme-fraud-detector",
        "version": "2.0.0",
        "description": "Real-time fraud detection ensemble",
        "serving_endpoint": "http://model-serve.acme.internal:8080/v1/fraud",
        "config_notes": (
            "Requires feature store warmup. Redis cluster: "
            "redis-cluster.acme.internal:6379 (auth: Fr4udF34tures!2024). "
            "Alert webhook: https://hooks.slack.com/services/T0ACME/B0FRAUD/xyzFraudAlertToken."
        ),
    },
    {
        "model_name": "acme-embeddings-v2",
        "version": "2.1.0",
        "description": "Internal text embedding model (sentence-transformers)",
        "serving_endpoint": "http://model-serve.acme.internal:8080/v1/embed",
        "config_notes": (
            "ONNX runtime optimized. Model weights: "
            "s3://acme-ml-models/embeddings-v2/onnx/ "
            "(read-only IAM: arn:aws:iam::123456789012:role/model-reader). "
            "Weights & Biases project: acme-embeddings "
            "(API key: FAKE_wandb_pgvec_embed_key_abcdef)."
        ),
    },
]

for model in models:
    cur.execute(
        """INSERT INTO model_registry
           (model_name, version, description, serving_endpoint, config_notes)
           VALUES (%s, %s, %s, %s, %s)""",
        (model["model_name"], model["version"], model["description"],
         model["serving_endpoint"], model["config_notes"]),
    )
print(f"[+] Inserted {len(models)} model registry entries")


# ── Table 4: audit_log (NO vector column — plain credential leak) ──
print("[*] Creating audit_log table...")
cur.execute("DROP TABLE IF EXISTS audit_log CASCADE")
cur.execute("""
    CREATE TABLE audit_log (
        id SERIAL PRIMARY KEY,
        timestamp TIMESTAMPTZ DEFAULT now(),
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        resource TEXT,
        details TEXT
    )
""")

audit_entries = [
    {
        "actor": "deploy-bot@acme.corp",
        "action": "secret-rotation",
        "resource": "prod-database",
        "details": (
            "Rotated database credentials. Old: acme_app/OldPr0dP4ss!2023. "
            "New: acme_app/Pr0dAppDB!2024. Applied to db-primary and db-replica."
        ),
    },
    {
        "actor": "sarah.chen@acme.corp",
        "action": "model-deploy",
        "resource": "acme-churn-predictor:3.2.1",
        "details": (
            "Deployed churn model v3.2.1 to production. "
            "Used deploy token: ghp_FAKE_pgvec_deploy_token_1234567890abcdef. "
            "Helm chart: acme-ml/churn-predictor:3.2.1."
        ),
    },
    {
        "actor": "jenkins@acme.corp",
        "action": "pipeline-run",
        "resource": "nightly-retrain",
        "details": (
            "Nightly retrain pipeline completed. "
            "S3 sync key: AKIAFAKEJENKINS12345678 / FAKE+JenkinsS3/abcdefghijk1234567890. "
            "Artifacts uploaded to s3://acme-ml-artifacts/nightly/2025-01-15/."
        ),
    },
    {
        "actor": "admin@acme.corp",
        "action": "emergency-access",
        "resource": "vault-root",
        "details": (
            "Break-glass access used. Root token: hvs.FAKE_break_glass_root_abcdef1234. "
            "Reason: Certificate rotation during P1 incident INC-4477. "
            "Access revoked after 45 minutes."
        ),
    },
]

for entry in audit_entries:
    cur.execute(
        """INSERT INTO audit_log
           (actor, action, resource, details)
           VALUES (%s, %s, %s, %s)""",
        (entry["actor"], entry["action"], entry["resource"], entry["details"]),
    )
print(f"[+] Inserted {len(audit_entries)} audit log entries")


# ── Summary ─────────────────────────────────────────────────
cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")
tables = [row[0] for row in cur.fetchall()]
print(f"\n[+] pgvector seeding complete — {len(tables)} public tables: {', '.join(tables)}")

cur.close()
conn.close()
