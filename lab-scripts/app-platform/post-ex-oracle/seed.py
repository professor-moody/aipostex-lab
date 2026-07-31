#!/usr/bin/env python3
"""
seed.py — Seed the Post-Ex Oracle replay_expectations table with credential
substrings drawn from the planted data inventory.

Run once during provisioning after server.py has created the database.
Usage: python3 seed.py [db_path]
"""
import sqlite3
import sys
from pathlib import Path

DB_PATH = sys.argv[1] if len(sys.argv) > 1 else "/home/appuser/projects/post-ex-oracle/oracle.db"

# Credential substrings planted across the lab (data-inventory.md)
# Format: (endpoint_prefix, expected_cred_substring, description)
REPLAY_EXPECTATIONS = [
    # AWS
    ("aws/s3", "AKIAFAKE1234EXAMPLE1", "AWS access key — Ollama system prompt, MCP config"),
    ("aws/s3", "AKIAFAKELITELLM", "LiteLLM AWS Bedrock key — LiteLLM config"),
    ("bedrock/runtime", "AKIAFAKE_A2A_DEPLOY_KEY1", "AWS deploy key — A2A task history"),
    ("bedrock/runtime", "AKIAFAKE_SSRF_METADATA_1", "SSRF metadata key — A2A fake_metadata fixture"),
    # OpenAI
    ("openai/v1", "sk-proj-FAKE", "OpenAI key prefix — LiteLLM config, MLflow artifacts"),
    # Anthropic
    ("anthropic/v1", "sk-ant-FAKE", "Anthropic key — LiteLLM config"),
    # GitHub
    ("github/api", "ghp_FAKE1234567890abcdefghijklmnopqrstuv", "GitHub PAT — MCP config claude_desktop"),
    ("github/api", "ghp_FAKE_a2a_seeded_xxxxxx", "GitHub PAT — A2A task history devops"),
    # HuggingFace
    ("huggingface/api", "hf_FAKE", "HuggingFace token — MLflow artifacts"),
    # Slack
    ("slack/webhook", "xoxb-FAKE-1234567890-abcdefghijklmnop", "Slack bot token — MCP config"),
    ("slack/webhook", "xoxb-FAKE-A2A-DEVOPS-1234567890", "Slack token — A2A task history"),
    # Jira
    ("jira/rest", "ATATT3xFfGF0_FAKE_jira_token_1234567890abcdef", "Jira API token — MCP config"),
    # PagerDuty
    ("pagerduty/incidents", "FAKE_PD_KEY_a2a_1234567890", "PagerDuty key — A2A task history"),
    # Postgres
    ("postgres/query", "McpR3ad3r!", "Postgres MCP reader password — MCP config"),
    ("postgres/query", "D3vUs3r!", "Postgres dev password — MCP cursor config"),
    ("postgres/query", "Sup3rS3cretDB!", "Postgres prod password — ChromaDB seeded data"),
    # Snowflake
    ("snowflake/session", "Sn0wfl4keDs!", "Snowflake DS password — Qdrant seeded data"),
    # Vault
    ("vault/v1", "hvs.FAKE_a2a_support_vault_token", "Vault token — A2A support task history"),
    # Azure OpenAI
    ("azure/openai", "FAKE-azure-openai-key", "Azure OpenAI key — LiteLLM config"),
    # Datadog
    ("datadog/v1", "FAKE_DD_API_KEY", "Datadog API key — Ray job env seeded data"),
    # Stripe
    ("stripe/v1", "sk_live_FAKE", "Stripe key — Weaviate seeded data"),
    # LangSmith
    ("langsmith/api", "ls__FAKE_", "LangSmith key — Weaviate seeded data"),
    # Grafana
    ("grafana/api", "Gr4f4n4@dm1n", "Grafana admin — Qdrant seeded data"),
    # Brave Search
    ("brave/api", "BSA_FAKE_brave_search_api_key_12345678", "Brave Search key — MCP cursor config"),
    # A2A internal
    ("a2a/internal", "sk-a2a-internal-FAKE-7a9b2c3d", "A2A internal token — agent card internalNotes"),
    ("a2a/internal", "ACM-FIN-FAKE-4f8a92e1", "AP approval token — A2A procurement task"),
    # DocuSign
    ("docusign/api", "DSIGN-FAKE-HR-ACME-0099", "DocuSign signing key — A2A HR task"),
]

# MLflow artifact expected hashes (placeholder — real hashes set during seed)
EXFIL_EXPECTATIONS = [
    ("mlflow/model-config", "sha256-placeholder-update-after-seed", "MLflow model config.json"),
    ("ollama/blob-prefix", "sha256-placeholder-update-after-seed", "Ollama smollm2 blob first 4KB"),
    ("ray/job-log-header", "sha256-placeholder-update-after-seed", "Ray job log file header"),
]


# Same DDL as server.py — ensures seed.py works even if server hasn't handled a request yet.
_INIT_DDL = """
    CREATE TABLE IF NOT EXISTS replay_expectations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint_prefix TEXT NOT NULL,
        credential_substring TEXT NOT NULL,
        description TEXT,
        UNIQUE(endpoint_prefix, credential_substring)
    );
    CREATE TABLE IF NOT EXISTS exfil_expectations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        expected_sha256 TEXT,
        description TEXT
    );
"""


def main():
    db = sqlite3.connect(DB_PATH)
    db.executescript(_INIT_DDL)

    for endpoint_prefix, cred_sub, description in REPLAY_EXPECTATIONS:
        db.execute("""
            INSERT OR IGNORE INTO replay_expectations
                (endpoint_prefix, credential_substring, description)
            VALUES (?, ?, ?)
        """, (endpoint_prefix, cred_sub, description))
        print(f"  [+] Seeded: {endpoint_prefix} → {cred_sub[:30]}...")

    for name, sha, description in EXFIL_EXPECTATIONS:
        db.execute("""
            INSERT OR IGNORE INTO exfil_expectations
                (name, expected_sha256, description)
            VALUES (?, ?, ?)
        """, (name, sha, description))
        print(f"  [+] Exfil expectation: {name}")

    db.commit()
    db.close()
    print(f"\n[+] Seeded {len(REPLAY_EXPECTATIONS)} credential validators and {len(EXFIL_EXPECTATIONS)} exfil expectations into {DB_PATH}")


if __name__ == "__main__":
    main()
