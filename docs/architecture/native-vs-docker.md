# Why Native Installs (No Docker)

Every service in the lab runs as a native install managed by systemd. No Docker, no containers, no `docker-compose.yml`. This is a deliberate design decision driven by three reasons.

---

## 1. Docker Hides Files from aipostex's Scanner

aipostex's file discovery module scans real filesystem paths to find AI artifacts: model weights at `~/.ollama/models/`, Jupyter config at `~/.jupyter/jupyter_lab_config.py`, MCP server configs at `~/.config/Claude/claude_desktop_config.json`, API keys in `.env` files scattered across project directories.

When Ollama runs inside a Docker container, its models live in a Docker volume — not at `~/.ollama/models/` on the host filesystem. When Jupyter runs in a container, its config lives inside the container's filesystem — not at `~/.jupyter/`. When ChromaDB runs in Docker, its SQLite database lives in a named volume — not at `/opt/chromadb/data/chroma.sqlite3`.

aipostex needs to find these files where they actually live on disk. Docker volumes are opaque to host-level filesystem scanning. Native installs put everything exactly where aipostex expects to find it.

!!! example "What Docker hides"
    | Artifact | Native path (scannable) | Docker path (invisible to host scan) |
    |----------|------------------------|--------------------------------------|
    | Ollama models | `/usr/share/ollama/.ollama/models/` | `ollama_data:/root/.ollama/models/` |
    | Jupyter config | `~/.jupyter/jupyter_lab_config.py` | Inside container at `/home/jovyan/.jupyter/` |
    | ChromaDB data | `/opt/chromadb/data/chroma.sqlite3` | `chromadb_data:/chroma/chroma/` |
    | LiteLLM config | `/opt/litellm/config.yaml` | Bind-mounted or baked into image |
    | `.env` files | `~/projects/chatbot-prototype/.env` | Not applicable (host-side, but referenced by container) |

---

## 2. Developers Don't Docker-ize Shadow AI

The whole premise of the lab is simulating **shadow AI sprawl** — developers independently deploying AI tools without coordination or security review. Real developers doing this don't write Dockerfiles.

A developer who wants to try Ollama runs:

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

They don't write a `docker-compose.yml` with volume mounts and port mappings. They install it, run `ollama pull llama3`, and start prompting.

A developer who wants Jupyter runs:

```bash
pip install jupyterlab
jupyter lab --ip 0.0.0.0 --no-browser
```

They don't pull `jupyter/scipy-notebook` from Docker Hub. They `pip install` it and run it.

MCP servers run via `npx`. Gradio apps run via `python app.py`. ChromaDB gets `pip install chromadb && chroma run`. These are all single commands that developers execute on their workstations or shared servers — no container orchestration involved.

!!! tip "The realism test"
    If the lab looks like it was set up by an infrastructure team running containers, it fails the realism test. The lab should look like it was set up by **three different people who each independently decided to play with AI tools** — because that's what shadow AI sprawl actually looks like.

---

## 3. Proxmox Snapshots Handle Reset

Docker's value proposition for labs usually includes easy teardown and rebuild: `docker compose down -v && docker compose up -d`. But Proxmox snapshots provide the same capability at the VM level — and they're cleaner.

```bash
# Snapshot after full provisioning
bash lab-snapshots.sh create lab-ready "Full deploy with all seed data"

# Restore to pristine state after a demo
bash lab-snapshots.sh restore lab-ready    # ~5 seconds
```

`qm rollback` restores the entire VM state — filesystem, running processes, systemd units, everything — in about 5 seconds. There's no equivalent in Docker that's this fast and this complete. `docker compose down -v && up` has to stop containers, remove volumes, recreate containers, wait for health checks, and re-seed data. A Proxmox snapshot rollback is atomic.

!!! note "Snapshot workflow"
    The recommended workflow is: provision the lab, verify with `verify-lab.sh`, snapshot, run your demo, roll back. Each cycle takes seconds, not minutes.

---

## The Principle

!!! abstract "Design principle"
    The lab should look like it was set up by three different people who each independently decided to play with AI tools, not by an infrastructure team running containers.

This principle drives every provisioning decision:

- Ollama is installed via `curl | sh` because that's what developers do
- Jupyter is installed via `pip` because that's what data scientists do
- MCP servers run as plain Python scripts because that's what prototype code looks like
- Weaviate and Qdrant are standalone binaries because the data science team downloaded them from GitHub releases
- Everything runs as systemd services because that's how you persist a process on a Linux server without thinking too hard about it
- There is no `docker-compose.yml`, no `Dockerfile`, no container registry — because shadow AI doesn't have those

The result is a lab that mirrors the messy, uncoordinated, unapproved AI infrastructure that aipostex is built to discover.
