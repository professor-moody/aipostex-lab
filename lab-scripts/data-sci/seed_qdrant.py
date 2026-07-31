#!/usr/bin/env python3
"""
seed_qdrant.py — Populate Qdrant with fake data for aipostex testing.

Run after Qdrant is running on the data-sci VM:
    /opt/data-sci-seed/venv/bin/python3 seed_qdrant.py [host] [port]

Creates 3 collections with 150+ total points containing:
    - Product data with internal pricing/margin details
    - Security audit findings with credentials and vulnerabilities
    - Incident response playbooks with access credentials

All data is FAKE but realistic-looking.
"""

import sys
import time
import random

try:
    from qdrant_client import QdrantClient
    from qdrant_client.models import Distance, VectorParams, PointStruct
except ImportError:
    print("[!] qdrant-client not installed. Run: /opt/data-sci-seed/venv/bin/python3 -m pip install qdrant-client")
    sys.exit(1)

HOST = sys.argv[1] if len(sys.argv) > 1 else "localhost"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 6333

print(f"[*] Connecting to Qdrant at {HOST}:{PORT}...")

client = None
for attempt in range(15):
    try:
        client = QdrantClient(host=HOST, port=PORT, timeout=10)
        info = client.get_collections()
        print(f"[+] Connected to Qdrant")
        break
    except Exception as e:
        print(f"    Waiting for Qdrant... attempt {attempt+1}/15 ({e})")
        time.sleep(3)
        client = None

if client is None:
    print("[!] Failed to connect to Qdrant after 15 attempts")
    sys.exit(1)


def fake_vector(dim=384):
    """Generate a random unit vector (simulates an embedding)."""
    vec = [random.gauss(0, 1) for _ in range(dim)]
    norm = sum(x*x for x in vec) ** 0.5
    return [x / norm for x in vec]


# ═══════════════════════════════════════════════════════════
# Collection 1: product-catalog — Product data with internal details
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'product-catalog' collection...")

try:
    client.delete_collection("product-catalog")
except Exception:
    pass

client.create_collection(
    collection_name="product-catalog",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE)
)

product_points = [
    PointStruct(
        id=1,
        vector=fake_vector(),
        payload={
            "name": "ACME Analytics Pro",
            "sku": "ACME-AP-ENT-001",
            "public_price": "$45,000/yr",
            "cost_to_serve": "$8,200/yr",
            "gross_margin": "81.8%",
            "description": (
                "Enterprise analytics platform with real-time dashboards. "
                "Deployed on customer's VPC or our managed infrastructure. "
                "License server: license.acme.internal:8443 "
                "(admin: license_admin / L1c3ns3Adm!n). "
                "Telemetry endpoint: telemetry.acme.corp/v2/ingest "
                "(API key: tel_api_FAKE_1234567890)."
            ),
            "internal_notes": "Minimum deal size $30K. Below $30K refer to SMB tier. Floor price approved by Marcus Johnson.",
            "category": "enterprise"
        }
    ),
    PointStruct(
        id=2,
        vector=fake_vector(),
        payload={
            "name": "ACME Analytics Starter",
            "sku": "ACME-AS-SMB-001",
            "public_price": "$500/mo",
            "cost_to_serve": "$45/mo",
            "gross_margin": "91%",
            "description": (
                "Self-service analytics for small businesses. "
                "Multi-tenant SaaS deployment on AWS. "
                "Tenant isolation via row-level security in PostgreSQL. "
                "Connection: postgresql://saas_app:S44sAppPr0d!@saas-db.acme.internal:5432/acme_saas. "
                "Stripe billing integration: sk_live_FAKE_saas_billing_abcdef123456."
            ),
            "internal_notes": "High margin product. Push aggressively in SMB segment. Consider 20% discount for annual prepay.",
            "category": "smb"
        }
    ),
    PointStruct(
        id=3,
        vector=fake_vector(),
        payload={
            "name": "ACME ML Pipeline",
            "sku": "ACME-ML-ENT-001",
            "public_price": "$85,000/yr",
            "cost_to_serve": "$22,000/yr",
            "gross_margin": "74.1%",
            "description": (
                "End-to-end ML pipeline management. Includes model training, "
                "deployment, monitoring, and A/B testing. "
                "Runs on customer's Kubernetes or our managed EKS cluster. "
                "Container registry credentials for managed deployments: "
                "AWS ECR (123456789012.dkr.ecr.us-east-1.amazonaws.com), "
                "pull secret: ecr_pull_FAKE_token_abcdef1234567890."
            ),
            "internal_notes": "Competitive with Databricks MLflow managed. Key differentiator: easier K8s integration.",
            "category": "enterprise"
        }
    ),
    PointStruct(
        id=4,
        vector=fake_vector(),
        payload={
            "name": "ACME Data Connector Pack",
            "sku": "ACME-DC-ADD-001",
            "public_price": "$12,000/yr add-on",
            "cost_to_serve": "$1,800/yr",
            "gross_margin": "85%",
            "description": (
                "Pre-built connectors for 50+ data sources. "
                "Includes Salesforce, HubSpot, Stripe, Snowflake, BigQuery. "
                "OAuth credentials for managed connectors stored in Vault: "
                "vault.acme.internal:8200 (token: hvs.FAKE_vault_token_abcdef1234567890). "
                "Connector health dashboard: https://connectors.acme.internal/status."
            ),
            "internal_notes": "Bundled free with Enterprise deals >$60K. Otherwise sold as add-on.",
            "category": "add-on"
        }
    ),
]

client.upsert(collection_name="product-catalog", points=product_points)
print(f"    [+] product-catalog: {len(product_points)} points loaded")


# ═══════════════════════════════════════════════════════════
# Collection 2: security-findings — Audit results and IR playbooks
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'security-findings' collection...")

try:
    client.delete_collection("security-findings")
except Exception:
    pass

client.create_collection(
    collection_name="security-findings",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE)
)

security_points = [
    PointStruct(
        id=1,
        vector=fake_vector(),
        payload={
            "title": "Pentest Finding: Unauthenticated AI Services on VLAN 50",
            "severity": "CRITICAL",
            "content": (
                "External pentest (conducted by CyberSec Partners, Nov 2025) identified "
                "multiple AI services on the ML VLAN (172.16.50.0/24) with no authentication: "
                "- Ollama API at 172.16.50.10:11434 (3 models, custom system prompts with credentials). "
                "- ChromaDB at 172.16.50.20:8000 (3 collections, 20 docs with PII and financial data). "
                "- Weaviate at 172.16.50.30:8080 (anonymous access enabled). "
                "- Qdrant at 172.16.50.30:6333 (no API key configured). "
                "- Jupyter notebooks at 172.16.50.10:8888 and 172.16.50.30:8889 (no token). "
                "- Custom MCP server at 172.16.50.10:3000 (command injection, SSRF, path traversal). "
                "Recommendation: Implement authentication on all services, segment from corporate network. "
                "Risk: Any employee on the network can extract PII, credentials, and financial data. "
                "Remediation deadline: January 15, 2026 (per CTO David Kim)."
            ),
            "status": "OPEN",
            "assigned_to": "security-team@acme.corp"
        }
    ),
    PointStruct(
        id=2,
        vector=fake_vector(),
        payload={
            "title": "Incident Response Playbook: API Key Compromise",
            "severity": "HIGH",
            "content": (
                "If an API key leak is detected: "
                "1) Rotate the key immediately via the provider's dashboard. "
                "2) Check usage logs for unauthorized activity. "
                "3) Notify security-team@acme.corp and update JIRA-SEC board. "
                "Emergency key rotation contacts: "
                "- OpenAI: Managed via platform.openai.com, org admin: david.kim@acme.corp. "
                "- AWS: Rotate via IAM console, break-glass admin: aws-root@acme.corp / "
                "  MFA seed in CEO's physical safe (SF office, room 401). "
                "- Stripe: Dashboard admin: finance-ops@acme.corp. Revoke via API: "
                "  curl -u sk_live_FAKE_admin_revoke_key: -X DELETE https://api.stripe.com/v1/api_keys/{id}. "
                "- GitHub: Org admin: lisa.park@acme.corp. Revoke PATs via Settings > Developer Settings. "
                "Escalation: If customer data exposed, notify privacy@acme.corp within 1 hour "
                "(GDPR 72-hour notification window starts from detection)."
            ),
            "status": "ACTIVE",
            "assigned_to": "sre-team@acme.corp"
        }
    ),
    PointStruct(
        id=3,
        vector=fake_vector(),
        payload={
            "title": "Vulnerability Scan Results: Shadow IT Discovery Q4 2025",
            "severity": "HIGH",
            "content": (
                "Quarterly shadow IT scan results: "
                "- 3 unauthorized Ollama instances (2 on dev workstations, 1 on data sci server). "
                "- 4 vector databases deployed without security review. "
                "- 2 Jupyter notebooks accessible without authentication. "
                "- 1 MCP server with remote code execution vulnerability. "
                "- 12 .env files containing AI provider API keys on developer machines. "
                "- 5 MCP configuration files with embedded database credentials. "
                "Total estimated exposure: $2.4M (based on data classification of accessible records). "
                "Comparison: Q3 2025 scan found 1 Ollama, 1 ChromaDB — growth rate is alarming. "
                "Proposed policy: All AI infrastructure must be registered in ServiceNow CMDB "
                "and approved by security team before deployment. "
                "Policy draft: gdrive/security/ai-infrastructure-policy-v1.docx."
            ),
            "status": "IN_REVIEW",
            "assigned_to": "ciso@acme.corp"
        }
    ),
    PointStruct(
        id=4,
        vector=fake_vector(),
        payload={
            "title": "Third-Party Risk Assessment: OpenAI Data Processing",
            "severity": "MEDIUM",
            "content": (
                "Assessment of OpenAI as data processor for ACME Corp. "
                "Current usage: Customer support chatbot, internal document summarization. "
                "Data types sent to OpenAI API: Customer support queries (may contain PII), "
                "internal documents (CONFIDENTIAL classification). "
                "DPA signed: Yes (March 2025). SOC2 Type II: Verified. "
                "Concern: No opt-out from training on API data until Enterprise tier. "
                "Current spend: $8,400/mo (growing 15% MoM). "
                "API keys in use: 3 (chatbot-prod, internal-tools, dev-sandbox). "
                "Key rotation schedule: Quarterly (next rotation: Jan 1, 2026). "
                "Alternative evaluation: Self-hosted Llama 3 via Ollama (see llm-cost-optimization project). "
                "Recommendation: Migrate to Enterprise tier ($0.03/1K tokens) or self-hosted by Q2 2026."
            ),
            "status": "ACTIVE",
            "assigned_to": "security-team@acme.corp"
        }
    ),
    PointStruct(
        id=5,
        vector=fake_vector(),
        payload={
            "title": "Backup and Recovery: AI Infrastructure Disaster Recovery Plan",
            "severity": "MEDIUM",
            "content": (
                "DR procedures for AI infrastructure: "
                "1) ChromaDB backups: Nightly snapshot to S3 (s3://acme-backups/chromadb/). "
                "   Backup script: /opt/scripts/backup-chromadb.sh (runs as cron, user: backup_svc). "
                "   S3 access key: AKIAFAKEBACKUP123456 / FAKE+BackupSecret/abcdef1234567890. "
                "2) Ollama models: Model files stored in S3 (s3://acme-ml-models/ollama/). "
                "   Custom Modelfiles in git: github.com/acme-corp/ml-configs (private repo). "
                "3) Weaviate: No backup configured (RISK — data loss possible). "
                "4) Qdrant: No backup configured (RISK). "
                "RTO target: 4 hours. RPO target: 24 hours. "
                "DR test schedule: Quarterly (last test: Sept 2025, next: Dec 2025). "
                "DR coordinator: sre-team@acme.corp. Escalation: david.kim@acme.corp (CTO)."
            ),
            "status": "ACTIVE",
            "assigned_to": "sre-team@acme.corp"
        }
    ),
    PointStruct(
        id=6,
        vector=fake_vector(),
        payload={
            "title": "Network Segmentation Audit: AI/ML VLAN",
            "severity": "HIGH",
            "content": (
                "Audit of VLAN 50 (172.16.50.0/24) — designated ML VLAN. "
                "Finding: VLAN has unrestricted access from corporate WiFi (VLAN 10) "
                "and developer workstations (VLAN 20). No ACLs in place. "
                "Any authenticated corporate user can reach all AI services. "
                "Firewall rule request submitted: FW-REQ-2025-1847. "
                "Proposed ACLs: "
                "- Allow 172.16.20.0/24 (dev) -> 172.16.50.0/24:11434 (Ollama) "
                "- Allow 172.16.20.0/24 (dev) -> 172.16.50.0/24:8888-8889 (Jupyter) "
                "- Deny 172.16.10.0/24 (WiFi) -> 172.16.50.0/24 (all) "
                "- Deny 172.16.30.0/24 (guest) -> 172.16.50.0/24 (all) "
                "Current status: PENDING (network team backlog, ETA 3 weeks). "
                "Switch credentials for VLAN config: admin / C1sc0@dm1n!2024 (core-sw-01.acme.internal)."
            ),
            "status": "OPEN",
            "assigned_to": "network-team@acme.corp"
        }
    ),
]

client.upsert(collection_name="security-findings", points=security_points)
print(f"    [+] security-findings: {len(security_points)} sensitive points loaded")


def generate_filler_findings(start_id=7, count=144):
    """Generate benign security scan filler points for pagination testing."""
    vuln_types = [
        ("Cross-Site Scripting (XSS)", "HIGH", "Reflected XSS via search parameter"),
        ("Cross-Site Request Forgery", "MEDIUM", "Missing CSRF token on form submission"),
        ("Open Redirect", "LOW", "Unvalidated redirect in login callback"),
        ("Information Disclosure", "MEDIUM", "Server version exposed in HTTP headers"),
        ("Missing Security Headers", "LOW", "X-Frame-Options header not set"),
        ("TLS Configuration", "MEDIUM", "TLS 1.0 still enabled on load balancer"),
        ("Cookie Security", "LOW", "Session cookie missing Secure flag"),
        ("Directory Listing", "MEDIUM", "Directory listing enabled on static assets"),
        ("Rate Limiting", "LOW", "No rate limiting on API authentication endpoint"),
        ("DNS Misconfiguration", "LOW", "SPF record too permissive"),
        ("Outdated Dependency", "MEDIUM", "jQuery 2.x in use, upgrade to 3.7+"),
        ("CORS Misconfiguration", "MEDIUM", "Wildcard Access-Control-Allow-Origin"),
    ]
    hosts = [
        "web-prod-01.acme.internal", "web-prod-02.acme.internal",
        "api-gateway.acme.internal", "cdn-origin.acme.internal",
        "staging.acme.internal", "admin-portal.acme.internal",
    ]
    statuses = ["OPEN", "IN_REVIEW", "REMEDIATED", "ACCEPTED_RISK"]
    assignees = [
        "security-team@acme.corp", "sre-team@acme.corp",
        "network-team@acme.corp", "platform-team@acme.corp",
    ]
    points = []
    for i in range(count):
        title_base, severity, desc = vuln_types[i % len(vuln_types)]
        host = hosts[i % len(hosts)]
        scan_id = 1000 + i
        points.append(PointStruct(
            id=start_id + i,
            vector=fake_vector(),
            payload={
                "title": f"Scan #{scan_id}: {title_base} on {host}",
                "severity": severity,
                "content": (
                    f"Automated scan finding #{scan_id}. {desc} detected on {host}. "
                    f"Scanner: Nessus Professional 10.{i % 8}. Scan profile: full-audit. "
                    f"First detected: 2025-{1 + i % 12:02d}-{1 + i % 28:02d}. "
                    f"CVSS base score: {3.0 + (i % 70) / 10.0:.1f}. "
                    f"Remediation: Apply vendor patch or configuration change per "
                    f"internal remediation SOP section {4 + i % 8}.{i % 5}."
                ),
                "status": statuses[i % len(statuses)],
                "assigned_to": assignees[i % len(assignees)],
            },
        ))
    return points


print("[*] Inserting filler security-findings for pagination testing...")
filler_findings = generate_filler_findings(start_id=7, count=144)
client.upsert(collection_name="security-findings", points=filler_findings)
print(f"    [+] security-findings: {len(filler_findings)} filler points loaded (pagination)")


# ═══════════════════════════════════════════════════════════
# Collection 3: public-faq — NOISE (no sensitive data)
# ═══════════════════════════════════════════════════════════

print("[*] Creating 'public-faq' collection (noise)...")

try:
    client.delete_collection("public-faq")
except Exception:
    pass
client.create_collection(
    collection_name="public-faq",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE),
)

faq_points = [
    PointStruct(
        id=101,
        vector=fake_vector(),
        payload={
            "question": "What programming languages does your API support?",
            "answer": "Our API supports Python, JavaScript, Go, Ruby, and Java. "
                      "SDKs are available on GitHub. See docs.example.com/sdks for details.",
            "category": "general"
        }
    ),
    PointStruct(
        id=102,
        vector=fake_vector(),
        payload={
            "question": "What is your uptime SLA?",
            "answer": "We guarantee 99.95% uptime for Enterprise plans and 99.9% for "
                      "Business plans. Current status is available at status.example.com.",
            "category": "general"
        }
    ),
    PointStruct(
        id=103,
        vector=fake_vector(),
        payload={
            "question": "How do I reset my password?",
            "answer": "Click 'Forgot Password' on the login page. Enter your email address "
                      "and follow the link sent to you. Passwords must be at least 12 characters.",
            "category": "account"
        }
    ),
    PointStruct(
        id=104,
        vector=fake_vector(),
        payload={
            "question": "Do you offer a free trial?",
            "answer": "Yes, all plans include a 14-day free trial with full access to all "
                      "features. No credit card required. Sign up at app.example.com/trial.",
            "category": "billing"
        }
    ),
]

client.upsert(collection_name="public-faq", points=faq_points)
print(f"    [+] public-faq: {len(faq_points)} points loaded (noise)")


# ═══════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════

print()
print("[+] ═══════════════════════════════════════════════")
print("[+] Qdrant seeding complete!")
print(f"[+] Host: {HOST}:{PORT}")
print("[+] ═══════════════════════════════════════════════")
print()

collections = client.get_collections().collections
for col in collections:
    info = client.get_collection(col.name)
    print(f"    Collection: {col.name}")
    print(f"      Points: {info.points_count}")
    print(f"      Vector dim: {info.config.params.vectors.size}")
    print()

print("[+] Sensitive data planted for aipostex detection:")
print("    - Connection strings: postgresql://, redis://, snowflake://")
print("    - API keys: Stripe live, Vault token, ECR pull secret, telemetry keys")
print("    - Admin credentials: license server, Airflow, switch, Grafana")
print("    - AWS keys: AKIAFAKEBACKUP123456")
print("    - Internal IP addresses and hostnames throughout")
print("    - Pentest findings referencing all lab hosts by IP")
print("    - Network switch credentials (Cisco)")
print("    - Break-glass / emergency access procedures")
print("    - Noise: public-faq collection (4 benign points)")
