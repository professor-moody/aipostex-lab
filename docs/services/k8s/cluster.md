---
title: Kubernetes Node (ailab-k8s)
---

# Kubernetes Node — ailab-k8s (172.16.50.50)

The estate's cluster surface: a **real vuln + secure k3s pair** on one VM, demonstrating "the
cluster IS the model registry." The vulnerable API on `:6443` is the offensive target; the secured
API on `:6444` is the honest negative control.

- **Provisioned by:** `lab-scripts/k8s-node/provision.sh` (idempotent; re-applied on reset-wave).
- **Image:** `rancher/k3s:v1.31.5-k3s1`, run as two containers (`k8s-vuln`, `k8s-secure`).
- **aipostex module:** `aipostex k8s --target https://172.16.50.50:<port> --insecure …`

## Why two containers on one VM

Two native k3s servers can't coexist on one host — they collide on flannel VXLAN, kubelet, and CNI
CIDR. So the pair runs as **two containers**, each in its own network namespace, mapped to distinct
host ports:

| Port | Container | Config | Behavior |
|------|-----------|--------|----------|
| `:6443` | `k8s-vuln` | `--kube-apiserver-arg=anonymous-auth=true` + over-permissioned anon RBAC | Anonymous enum, secret read, `pods/exec` all **succeed** |
| `:6444` | `k8s-secure` | default (anonymous-auth off) | Anonymous requests get **401** — nothing is stealable |

This is the exact config `sandbox prove k8s` validates, promoted onto a real estate node so demo
Act 6 records against `172.16.50.50` rather than an operator laptop.

## The vulnerability — anonymous RBAC gone wrong

`manifests/vuln/10-anon-rbac.yaml` binds an over-scoped `ClusterRole` (`anon-ml-reader`) to
`system:anonymous`. Intended as read-only ML observability, it was mis-scoped:

- `get`/`list` on **namespaces, pods, secrets, configmaps, services**, `deployments`/`replicasets`,
  the `serving.kserve.io/inferenceservices` CRD, and discovery endpoints — cluster-wide.
- **Mis-scoped**: `create`/`get` on `pods/exec` — anonymous can open an exec stream into a running
  pod (the "copy-paste from a debug role" mistake).

## Seeded workloads (the loot)

| Namespace | Object | Contents |
|-----------|--------|----------|
| `ml-prod` | Secret `model-registry-creds` | `HF_TOKEN` (prod registry), `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, `S3_MODEL_BUCKET=s3://acme-ml-model-registry-prod` |
| `ml-prod` | Deployment `llama-inference` | Runs under SA `pipeline-runner`, `automountServiceAccountToken: true` (the exec-stealable token) |
| `ml-prod` | ServiceAccount `pipeline-runner` | Bound to `ml-pipeline-writer` — **`create/update/delete` on secrets, configmaps, pods, serviceaccounts, deployments cluster-wide** |
| `ml-prod` | ConfigMap `inference-config` | `MODEL_NAME=meta-llama/Llama-3.1-8B-Instruct`, registry endpoint |
| `ml-system` | Secret `pipeline-deploy-key` | Second team's `DEPLOY_TOKEN` (GitLab PAT) + `GIT_SSH_KEY` — the cross-namespace pivot |

All values are planted `FAKE*` fixtures (see the [Sensitive Data Inventory](../../reference/data-inventory.md)).

## The attack — anon read → exec → cluster-write

1. **`secret-read`** — anonymous, reads `ml-prod/model-registry-creds`; `--all-namespaces` reaches
   `ml-system/pipeline-deploy-key` too.
   ```bash
   aipostex k8s --target https://172.16.50.50:6443 --insecure secret-read --all-namespaces --force-exploit
   ```
2. **`sa-loot`** — exec into the `llama-inference` pod (the anon `pods/exec` grant), steal the
   mounted `pipeline-runner` token, and prove it can `create/update/delete` cluster-wide → **model
   registry supply-chain tampering**.
   ```bash
   aipostex k8s --target https://172.16.50.50:6443 --insecure sa-loot --namespace ml-prod --force-exploit
   ```
3. **`pod-exec`** — direct `uid=0` shell in a running pod (the RCE primitive behind `sa-loot`).

The stolen token is emitted **un-redacted by design** so the operator can continue by hand in plain
`kubectl` (become the identity, `get secrets -A`, reach the second team's CI deploy key). See the
[Post-Exploitation Operator Guide](../../post-exploitation/manual.md#1-kubernetes-from-a-stolen-token-to-the-whole-cluster)
for the native continuation.

## Landed grading

| Verb | Landed | Stage | Why |
|------|--------|-------|-----|
| `secret-read` (`:6443`) | read-confirmed | access | Real secret bytes read anonymously |
| `sa-loot` / `pod-exec` (`:6443`) | execution-confirmed / takeover-capable | own | `uid=0` pod shell + a cluster-write SA token proven via `auth can-i` |
| `rbac-probe` (`:6444`) | reachable (not weak) | recon | Anonymous returns 401 — the honest negative control |

## Cleanup

`sa-loot`'s cluster-write proof (and any dropped workload) **dirties the cluster**. Run
`reset-wave.sh` afterward — the k8s pair re-applies its seed manifests on reboot, so rollback is
clean.

## See also

- [Demo Walkthrough](../../demo/walkthrough.md) · the k8s beat is demo Act 6
- [Operator Field Guide — k8s supply-chain path](../../reference/field-manual.md)
- [Post-Exploitation Operator Guide](../../post-exploitation/manual.md)
