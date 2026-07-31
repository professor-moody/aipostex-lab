# Hot-Patch: Live Updates Without A Full Redeploy

For iterating on a single mock's `server.py`, or pushing a new `aipostex` binary to the attack
box, **without** re-running [`deploy-all.sh`](automated.md). Both edit the *running* estate directly.

> ⚠ A hot-patch lives on the running VMs only. `lab-ready` / [`reset-wave.sh`](../scoring/verify-lab.md)
> restore the snapshot, so the change does **not** survive a reset unless you re-snapshot
> `lab-ready` (see [Snapshots & Teardown](snapshots.md)). That is deliberate — the reset
> guarantees a clean baseline every wave.

## Hot-Patch A Single Mock

Mock services run from `/home/mluser/projects/<name>-mock/server.py` as systemd unit
`<name>-mock` (user `mluser`) — the same copy → chown → restart pattern each `provision.sh`
applies (e.g. `lab-scripts/ml-platform/provision.sh`), narrowed to one service. The estate
`/24` is reachable only from the Proxmox host, so the file travels dev → Proxmox → VM.

1. **Edit the source of record** locally: `lab-scripts/<role>/<name>-mock/server.py`
   (`<role>` = `dev-workstation` | `ml-platform` | `data-sci` | `app-platform`).

2. **Sync to Proxmox** (the deploy origin; repo at `/root/aipostex-lab`):

    ```bash
    rsync -az --exclude '.git/' ./ root@<proxmox-host>:/root/aipostex-lab/    # add -n first to dry-run
    ```

3. **Ship to the VM and restart** (from Proxmox; reach VMs as `labadmin`, key auth — `root@<vm>`
   scp is rejected):

    ```bash
    VM=<vm-ip>; NAME=<name>; ROLE=<role>
    scp /root/aipostex-lab/lab-scripts/$ROLE/$NAME-mock/server.py labadmin@$VM:/tmp/server.py
    ssh labadmin@$VM "sudo cp /tmp/server.py /home/mluser/projects/$NAME-mock/server.py \
      && sudo chown mluser:mluser /home/mluser/projects/$NAME-mock/server.py \
      && sudo systemctl restart $NAME-mock"
    ```

4. **Verify** the restart took and the surface responds:

    ```bash
    ssh labadmin@$VM "systemctl is-active $NAME-mock && curl -sf http://localhost:<port>/<health> | head"
    ```

    Or run the full health gate: `bash lab-scripts/verify-lab.sh`.

VM IPs and ports: [VM Map](../getting-started/vm-map.md). The systemd unit name and on-VM path
for any service are in that role's `provision.sh` (grep `systemctl restart <name>-mock`).

## Update The `aipostex` Binary On The Attack Box

The attack box has **no Go and no internet** — cross-compile on dev and `scp` the binary in.

1. **Cross-compile** (linux/amd64, stamped with the commit) from the `aipostex` tool repo:

    ```bash
    GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build \
      -ldflags "-s -w -X github.com/professor-moody/aipostex/internal/config.Version=$(git rev-parse --short HEAD)" \
      -o /tmp/aipostex-linux-amd64 ./cmd/aipostex
    ```

2. **Install over one SSH** — backs up the current binary, installs the piped one, prints version:

    ```bash
    ssh labadmin@<attack-box> \
      'cp ~/aipostex ~/aipostex.bak; cat > ~/aipostex && chmod +x ~/aipostex && ~/aipostex version' \
      < /tmp/aipostex-linux-amd64
    ```

3. **Re-verify** end-to-end from the box:

    ```bash
    ssh labadmin@<attack-box> 'cd ~/lab && bash attack-box/verify-aipostex.sh --layer all'
    ```

> ⚠ `lab-ready` / `reset-wave.sh` include the attack box (qm 240). A reset reverts the binary to
> the snapshot's copy, so **re-snapshot `lab-ready` after deploying** if the new binary must
> survive resets ([Snapshots & Teardown](snapshots.md)).
