---
title: Troubleshooting
---

# Troubleshooting

Common issues encountered during lab deployment and their fixes.

---

## 1. No SSH response after VM creation

The VM was cloned but isn't reachable via SSH.

```bash
qm status <VMID>            # is it running?
qm start <VMID>             # start if stopped
```

!!! tip "Check cloud-init"
    SSH to the Proxmox console (`qm terminal <VMID>`) and check cloud-init:
    ```bash
    cat /var/log/cloud-init-output.log
    cloud-init status --long
    ```
    If cloud-init hasn't finished, SSH keys and network config may not be applied yet.

Verify the bridge is up:

```bash
ip link show vmbr100         # bridge exists?
brctl show vmbr100           # VMs attached?
```

---

## 2. VM has wrong IP address

The VM booted with a DHCP address or the wrong static IP.

```bash
qm set <VMID> --ipconfig0 ip=172.16.50.10/24,gw=172.16.50.1
qm reboot <VMID>
```

Wait 30 seconds for cloud-init to apply the new config, then retry SSH.

---

## 3. DNS resolution fails inside VMs

Symptom: `apt update` fails, `pip install` can't resolve hostnames.

```bash
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

!!! note
    `base-setup.sh` handles this automatically. If DNS is broken, run `base-setup.sh` first before provisioning.

For persistent configuration, edit `/etc/systemd/resolved.conf`:

```ini
[Resolve]
DNS=8.8.8.8 8.8.4.4
```

Then restart: `systemctl restart systemd-resolved`.

---

## 4. Ollama install fails on minimal cloud image

The official install script (`curl -fsSL https://ollama.com/install.sh | sh`) requires `curl` and `systemctl`, which may not be present on bare cloud images.

**Fix:** Run `base-setup.sh` first — it installs `curl`, `wget`, and other prerequisites via `apt`.

```bash
bash base-setup.sh           # on the VM
# then:
curl -fsSL https://ollama.com/install.sh | sh
```

---

## 5. pip install fails with PEP 668 error

Ubuntu 24.04 enforces [PEP 668](https://peps.python.org/pep-0668/), which prevents `pip install` into the system Python.

```
error: externally-managed-environment
```

**Fix:** Use `--break-system-packages` on every pip command:

```bash
pip install --break-system-packages jupyterlab
pip install --break-system-packages chromadb mlflow litellm
```

!!! info
    All provision scripts already include this flag. This is only relevant if you're installing packages manually.

---

## 6. Weaviate / Qdrant binary URL broken

The GitHub release URL returns 404.

**Fix:** Check the latest release pages and update the version variables in provision scripts:

- Weaviate: <https://github.com/weaviate/weaviate/releases>
- Qdrant: <https://github.com/qdrant/qdrant/releases>

Update the version in `data-sci/provision.sh`:

```bash
WEAVIATE_VERSION="1.28.4"    # check for latest
QDRANT_VERSION="1.13.2"      # check for latest
```

---

## 7. Weaviate standalone binary not available for target version

Some Weaviate releases only ship Docker images — no standalone binary.

**Alternatives (in order of preference):**

1. Use an older version that has a standalone binary
2. Install via pip: `pip install --break-system-packages weaviate-embedded`
3. Fall back to Docker for just this service (breaks the "all-native" approach but works)

!!! warning
    If using `weaviate-embedded`, the systemd unit and startup command will be different. Update `provision.sh` accordingly.

---

## 8. `chroma` executable not found

ChromaDB is installed in an isolated venv at `/opt/chromadb/venv`. The binary is at `/opt/chromadb/venv/bin/chroma`.

```bash
/opt/chromadb/venv/bin/chroma --help
```

The systemd unit references the full venv path so `$PATH` configuration is not needed for the service.

---

## 9. Ollama model pull needs internet access

`ollama pull smollm2:135m` downloads ~220 MB from `registry.ollama.ai`.

If the VM has no internet:

- Verify DNS works (see [issue #3](#3-dns-resolution-fails-inside-vms))
- Verify outbound HTTPS (port 443) is allowed
- See the [Offline / Air-Gapped Setup](../appendices/offline.md) guide for pre-caching models

!!! info "Model cache location"
    When Ollama runs as a systemd service (as the `ollama` user), models cache to:
    ```
    /usr/share/ollama/.ollama/models/
    ```
    When run as a regular user, models cache to `~/.ollama/models/`.

---

## 10. Seed scripts fail: missing client packages

The canonical fix is to use the role-level `seed.sh` entrypoints, which install or reuse the right interpreter paths for each VM.

```bash
# On ailab-ml:
sudo bash ~/lab/ml-platform/seed.sh

# On ailab-ds:
sudo bash ~/lab/data-sci/seed.sh
```

!!! tip
    `deploy-all.sh` Phase 3 and the optional Ansible wrapper both call these same `seed.sh` entrypoints automatically. ChromaDB uses `/opt/chromadb/venv/bin/python3`, MLflow and Ray use `/opt/ailab-ml/venv/bin/python3`, and the data-science seeders use `/opt/data-sci-seed/venv/bin/python3`.

---

## 11. Jupyter port conflict between VMs

Both ailab-dev and ailab-ds run Jupyter, but on different ports:

| VM | Port | Systemd Unit |
|----|------|-------------|
| ailab-dev | 8888 | `jupyter.service` |
| ailab-ds | 8889 | `jupyter-ds.service` |

If you see a port conflict, verify the config file has the correct port:

```bash
# On ailab-dev:
grep port ~/.jupyter/jupyter_lab_config.py    # should be 8888

# On ailab-ds:
grep port ~/.jupyter/jupyter_lab_config.py    # should be 8889
```

---

## 12. Service won't start (generic)

For any systemd service that fails to start:

```bash
systemctl status <service-name>
journalctl -u <service-name> --no-pager -n 50
```

!!! tip "Common causes"
    - **Binary not found:** Check `ExecStart` path in the unit file matches the actual binary location
    - **Permission denied:** Check the `User=` directive — the user must exist and have access to the working directory
    - **Port already in use:** `ss -tlnp | grep <port>` to find what's occupying the port
    - **Missing dependencies:** Python scripts may need packages not yet installed

---

## 13. ChromaDB API / collection listing issues

The lab uses ChromaDB 0.6.3, which has REST API quirks — the `/api/v1/collections` endpoint may return `coroutine object` errors. Use the Python client instead:

```bash
/opt/chromadb/venv/bin/python3 -c "import chromadb; c=chromadb.HttpClient(); print(c.list_collections())"
```

The heartbeat endpoint still works via REST:

```bash
curl http://172.16.50.20:8000/api/v1/heartbeat
```

!!! note
    In ChromaDB 0.6.x, `list_collections()` returns collection names (strings), not objects. Use `client.get_collection("name")` to get a collection object.

---

## 14. ChromaDB fails with `Unable to configure handler 'file'`

ChromaDB's uvicorn logging tries to write `chroma.log` to the working directory. If the systemd unit lacks `WorkingDirectory`, it defaults to `/` which is not writable by `mluser`.

**Fix:** Ensure the unit file includes `WorkingDirectory=/opt/chromadb`:

```bash
sudo systemctl cat chromadb | grep WorkingDirectory
# Should output: WorkingDirectory=/opt/chromadb
```

If missing, add it and restart:

```bash
sudo sed -i '/\[Service\]/a WorkingDirectory=/opt/chromadb' /etc/systemd/system/chromadb.service
sudo systemctl daemon-reload
sudo systemctl restart chromadb
```

---

## 15. Weaviate client API version mismatch

The Weaviate Python client v4 has a completely different API from v3. The seed scripts require v4.

```bash
# Correct — pin to v4:
pip install --break-system-packages 'weaviate-client>=4.9.0,<5.0.0'

# Wrong — installs v3 which has incompatible API:
pip install --break-system-packages weaviate-client==3.26.0
```

!!! warning "v3 vs v4 API differences"
    v4 uses `client.collections.create()` and `client.collections.get()`.  
    v3 uses `client.schema.create_class()` and `client.query.get()`.  
    The seed scripts will fail with `AttributeError` if the wrong version is installed.

---

## 16. LiteLLM fails with `No module named 'apscheduler'`

The proxy dependencies (including `apscheduler`) are not included in the base `litellm` package. Install with the `[proxy]` extra:

```bash
pip install --break-system-packages "litellm[proxy]==1.60.7"
```

---

## 17. Gradio crashes with Pydantic `TypeError`

Older Gradio versions (e.g., 5.14.0) conflict with newer Pydantic versions installed by other packages. The lab pins Gradio 5.49.1 which resolves the conflict.

```bash
pip install --break-system-packages gradio==5.49.1
```

---

## 18. Qdrant `recreate_collection` deprecated

Older Qdrant client versions had `recreate_collection()`. Current versions require a delete-then-create pattern.

```python
# Correct pattern (current qdrant-client):
try:
    client.delete_collection("my-collection")
except Exception:
    pass
client.create_collection(
    collection_name="my-collection",
    vectors_config=VectorParams(size=384, distance=Distance.COSINE),
)

# Deprecated (will fail on newer clients):
client.recreate_collection(...)
```

The seed scripts already use the delete + create pattern.

---

## 19. SSH `REMOTE HOST IDENTIFICATION HAS CHANGED` after VM rebuild

After destroying and recreating VMs, SSH connections fail because host keys have changed.

**Fix:** All lab scripts use `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` to bypass this. If you're connecting manually:

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null labadmin@172.16.50.20
```

Or clear stale keys from your known_hosts:

```bash
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.10
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.20
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.30
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.40
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.50
ssh-keygen -f ~/.ssh/known_hosts -R 172.16.50.99
```

---

## 20. NumPy `RuntimeError` about baseline optimizations (X86_V2)

NumPy 2.4+ requires x86_v2 CPU instructions. If Proxmox VMs use the default `kvm64` CPU type, NumPy will crash at import.

**Fix:** Set CPU type to `host` in `proxmox-setup.sh` (already done in the current scripts):

```bash
qm set <VMID> --cpu host
```

---

## 21. `jq` not found on Proxmox host

`verify-lab.sh` deep validation uses `jq` for JSON parsing. Install it:

```bash
apt install -y jq
```

---

## 22. Python venv creation fails (`ensurepip is not available`)

If `python3 -m venv` fails, the `python3-venv` package is missing.

```bash
apt install -y python3-venv
```

`base-setup.sh` includes this package automatically.
