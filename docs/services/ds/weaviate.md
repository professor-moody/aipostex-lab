---
title: Weaviate (ailab-ds)
---

# Weaviate (ailab-ds)

## What It Is

Weaviate is an open-source vector database that supports semantic search and hybrid queries. On the data science workstation, it runs as a standalone binary with anonymous access explicitly enabled — no authentication required. Three classes store a mix of sensitive research documents, team communications, and benign public content.

---

## Installation

Installed via binary download from GitHub releases:

```bash
wget https://github.com/weaviate/weaviate/releases/download/v1.28.4/weaviate-v1.28.4-linux-amd64.tar.gz
tar xzf weaviate-v1.28.4-linux-amd64.tar.gz
mv weaviate /usr/local/bin/weaviate
chmod +x /usr/local/bin/weaviate
```

!!! warning "Release availability"
    Verify the release URL at build time. Binary releases may not be available for all versions or architectures on the Weaviate GitHub releases page.

---

## Systemd Unit

**Unit:** `weaviate.service`

```ini title="/etc/systemd/system/weaviate.service"
[Service]
User=root
ExecStart=/usr/local/bin/weaviate --host 0.0.0.0 --port 8080 --scheme http
Environment="PERSISTENCE_DATA_PATH=/opt/weaviate/data"
Environment="AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true"
Environment="QUERY_DEFAULTS_LIMIT=25"
Environment="DEFAULT_VECTORIZER_MODULE=none"
Restart=always
```

!!! danger "Misconfiguration"
    `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true` explicitly disables authentication. Combined with binding to `0.0.0.0`, all classes and objects are accessible to anyone on the network.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.30` |
| Port | `8080` |
| Bind address | `0.0.0.0` |
| Authentication | Anonymous access enabled |
| Data directory | `/opt/weaviate/data/` |
| Vectorizer | None (pre-computed vectors) |

---

## Seed Data

Three classes are seeded:

| Class | Objects | Content |
|---|---|---|
| `ResearchDocument` | 6 | Database credentials, API keys embedded in internal research notes |
| `TeamCommunication` | 6 | SSNs, salary information in team chat logs and HR communications |
| `PublicKnowledge` | varies | Benign public-facing content (noise) |

---

## What aipostex Finds

- **Unauthenticated access** — The Weaviate API requires no credentials, confirmed by the `AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true` environment variable in the systemd unit.
- **Class enumeration** — The `/v1/schema` endpoint lists all classes and their properties, revealing the data model.
- **Sensitive data extraction** — Querying `ResearchDocument` and `TeamCommunication` surfaces database credentials, API keys, SSNs, and salary data.

---

## Verification

Confirm Weaviate is running:

```bash
curl http://localhost:8080/v1/meta
```

??? example "Expected response"
    ```json
    {"hostname": "...", "version": "1.28.4", ...}
    ```

List schema classes:

```bash
curl http://localhost:8080/v1/schema
```

??? example "Expected response"
    JSON listing `ResearchDocument`, `TeamCommunication`, and `PublicKnowledge` classes with their property definitions.
