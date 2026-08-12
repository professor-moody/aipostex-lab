# verify-lab.sh

Verifies that the lab is healthy before demos or tool validation.

## What It Checks

- Ping reachability to all 6 VMs
- SSH access to all 6 VMs
- service health for every seeded service plus the `ailab-siem` Elastic detection stack
- deep validation of seeded data plus the app / model-agent surfaces
- **62 checks total** (0 failed)

Total: **62 checks** on the full validation path.

## New Surfaces Included

- `ailab-app:8090` LangServe
- `ailab-app:8501` Streamlit
- `ailab-app:8100-8102` A2A agents
- `ailab-app:8765` Post-Ex Oracle
- `ailab-app:8180` HF TGI gateway
- `ailab-ml:8181` HF TEI mock
- `ailab-ml:8182` vLLM mock
- `ailab-ml:3333,8081,8082,8444,9000,8501` serving and platform mocks
- `ailab-ds:5432` PostgreSQL/pgvector

## Usage

```bash
bash lab-scripts/verify-lab.sh
```
