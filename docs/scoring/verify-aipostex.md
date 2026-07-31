# verify-aipostex.sh

Layered end-to-end verification harness that runs real `aipostex` commands against the live lab.

## Layers

| Layer | Purpose |
|---|---|
| `preflight` | Service/data readiness without the binary |
| `smoke` | Reachability across the default AI/ML service surface |
| `operator` | Read-only discovery, benign command execution, and non-mutating evidence collection |
| `active` | Explicit gated-exploit layer for `--force-exploit` workflows and bounded mutation checks |
| `contract` | Read-only workflow/evidence/stage-landed metadata and JSONL validation |
| `destructive` | Opt-in snapshot-gated mutation tests with automated rollback |

## Environment

| Variable | Effect |
|---|---|
| `AIPOSTEX_SKIP_ASSESS=1` | Skip `assess network` (fingerprint + detect templates, `--skip-exploit`). Operator and contract layers skip assess assertions when the artifact is absent. Use on slow links or when you only need `discover network` parity. |

## Notable Additions

- `discover network --mode detect`
- `assess network --mode detect --skip-exploit` (same targets/ports as discover, unless skipped via `AIPOSTEX_SKIP_ASSESS=1`)
- `scan targets` smoke against dev Ollama (`--mode detect`)
- `vectordb … search-sensitive` on ChromaDB, Weaviate, and Qdrant (bounded `--limit 100`)
- `jupyter notebooks --mine-secrets` (cell credential mining)
- LangServe, Streamlit, HF TGI, HF TEI, and vLLM discovery coverage
- MCP stdio transport coverage
- explicit `active` coverage for:
  - `discover network --mode full --force-exploit`
  - `ollama exfiltrate`
  - `jupyter start-kernel`
  - `jupyter reverse-shell-proof`
  - `jupyter pip-proof`
  - `ray pip-inject`
  - `ray cluster-info`
  - `mlflow tamper-proof`

## Usage

```bash
bash lab-scripts/attack-box/verify-aipostex.sh
bash lab-scripts/attack-box/verify-aipostex.sh --layer operator
bash lab-scripts/attack-box/verify-aipostex.sh --layer active
```
