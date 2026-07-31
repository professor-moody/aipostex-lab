---
title: Qdrant (ailab-ds)
---

# Qdrant (ailab-ds)

## What It Is

Qdrant is a vector similarity search engine with a REST API. On the data science workstation, it runs as a standalone binary with no authentication. Three collections store point data — including a `security-findings` collection that is meta: it contains a pentest report about the lab environment itself, listing hosts, services, and network switch credentials.

---

## Installation

Installed via binary download from GitHub releases:

```bash
wget https://github.com/qdrant/qdrant/releases/download/v1.13.2/qdrant-x86_64-unknown-linux-gnu.tar.gz
tar xzf qdrant-x86_64-unknown-linux-gnu.tar.gz
mv qdrant /usr/local/bin/qdrant
chmod +x /usr/local/bin/qdrant
```

!!! warning "Release availability"
    Verify the release URL at build time. Binary releases may not be available for all versions or architectures on the Qdrant GitHub releases page.

---

## Systemd Unit

**Unit:** `qdrant.service`

```ini title="/etc/systemd/system/qdrant.service"
[Service]
WorkingDirectory=/opt/qdrant
ExecStart=/usr/local/bin/qdrant --config-path /opt/qdrant/config.yaml
Restart=always
```

The YAML config at `/opt/qdrant/config.yaml` sets the storage path and network binding:

```yaml title="/opt/qdrant/config.yaml"
storage:
  storage_path: /opt/qdrant/storage
  snapshots_path: /opt/qdrant/snapshots
service:
  host: 0.0.0.0
  http_port: 6333
  grpc_port: 6334
```

!!! danger "Misconfiguration"
    No authentication configured. The REST API is bound to `0.0.0.0`, making all collections and points accessible to anyone on the network.

---

## Port & Config

| Parameter | Value |
|---|---|
| Host | `172.16.50.30` |
| Port | `6333` |
| Bind address | `0.0.0.0` |
| Authentication | None |
| Storage directory | `/opt/qdrant/storage/` |

---

## Seed Data

Three collections are seeded:

| Collection | Points | Content |
|---|---|---|
| `product-catalog` | 4 | License server admin credentials, HashiCorp Vault token, Stripe API key |
| `security-findings` | 6 | Pentest report listing all lab hosts and services, IR playbook, network switch credentials |
| `public-faq` | varies | Benign FAQ content (noise) |

### The Meta Collection

The `security-findings` collection is deliberately self-referential: it contains a penetration test report about the lab environment itself. Points include:

- **Pentest report** — Lists lab hosts (`172.16.50.10`, `.20`, `.30`), their services, and open ports
- **Incident response playbook** — IR procedures referencing internal infrastructure
- **Network switch credentials** — Management credentials for network equipment

This means an attacker who discovers Qdrant and enumerates `security-findings` gets a roadmap of the entire lab.

---

## What aipostex Finds

- **Collection enumeration** — The `/collections` endpoint lists all collections without authentication.
- **Sensitive data extraction** — Scrolling or searching points in `product-catalog` surfaces license admin creds, Vault tokens, and Stripe keys.
- **Self-referential pentest data** — The `security-findings` collection contains infrastructure details about the lab itself, effectively providing reconnaissance data to anyone who finds it.

---

## Verification

Confirm Qdrant is running and list collections:

```bash
curl http://localhost:6333/collections
```

??? example "Expected response"
    ```json
    {"result": {"collections": [{"name": "product-catalog"}, {"name": "security-findings"}, {"name": "public-faq"}]}, ...}
    ```

Retrieve points from a collection:

```bash
curl http://localhost:6333/collections/security-findings/points/scroll
```

??? example "Expected response"
    JSON with points containing pentest report data, IR playbook content, and network switch credentials.
