---
title: ChromaDB (ailab-ml)
---

# ChromaDB (ailab-ml)

## What It Is

ChromaDB is an open-source vector database designed for AI applications. On the ML platform, it stores document embeddings across multiple collections — some containing sensitive data like SSNs, credit card numbers, and credentials. The API is unauthenticated and bound to all interfaces, making every collection enumerable and searchable by anyone on the network.

---

## Installation

ChromaDB is installed in an isolated virtual environment to prevent dependency conflicts with MLflow, LiteLLM, and Ray (which share incompatible versions of FastAPI and Pydantic):

```bash
python3 -m venv /opt/chromadb/venv
/opt/chromadb/venv/bin/pip install chromadb==0.6.3
chown -R mluser:mluser /opt/chromadb
```

---

## Systemd Unit

**Unit:** `chromadb.service`

```ini title="/etc/systemd/system/chromadb.service"
[Service]
User=mluser
WorkingDirectory=/opt/chromadb
ExecStart=/opt/chromadb/venv/bin/chroma run --host 0.0.0.0 --port 8000 --path /opt/chromadb/data
Restart=always
```

`WorkingDirectory` is required so that ChromaDB's internal log handler can write `chroma.log` to a writable location.

!!! danger "Misconfiguration"
    The API is bound to `0.0.0.0` with no authentication. Any host on the network can enumerate collections, list documents, and search embeddings.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.20` |
| Port | `8000` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Data directory | `/opt/chromadb/data/` |
| SQLite database | `/opt/chromadb/data/chroma.sqlite3` |

---

## Seed Data

Four collections are seeded:

| Collection | Documents | Content |
|---|---|---|
| `acme-knowledge-base` | 12 | SSNs, credentials, financial data embedded in corporate knowledge articles |
| `support-tickets-2025` | 5 | Credit card numbers, SSNs mixed into support ticket transcripts |
| `code-documentation` | 3 | Admin credentials embedded in internal code documentation |
| `public-documentation` | varies | Benign public-facing content (noise) |

### Adversarial Prompt Injection

Three additional documents are seeded across collections containing adversarial prompt injection payloads. These test whether aipostex (or any RAG pipeline querying ChromaDB) can detect and flag prompt injection content embedded alongside legitimate data.

---

## What aipostex Finds

- **Unauthenticated API** — The ChromaDB REST API requires no credentials. Collections are fully enumerable.
- **Collection enumeration** — All four collections are discoverable, revealing the scope of stored data.
- **Sensitive data search** — Querying across collections surfaces SSNs, credit card numbers, credentials, and financial data embedded in document content and metadata.

---

## Verification

Confirm ChromaDB is running:

```bash
curl http://localhost:8000/api/v1/heartbeat
```

??? example "Expected response"
    ```json
    {"nanosecond heartbeat": ...}
    ```

List all collections (use the Python client — the REST collections endpoint is unreliable in 0.6.x):

```bash
/opt/chromadb/venv/bin/python3 -c "import chromadb; c=chromadb.HttpClient(); print(c.list_collections())"
```

??? example "Expected response"
    A list containing `acme-knowledge-base`, `support-tickets-2025`, `code-documentation`, and `public-documentation`.
