# Automated Deployment

`deploy-all.sh` is the canonical deployment path. It takes the 5 target VMs from freshly cloned OS images to a fully provisioned lab in one command.

## Phases

| Phase | What it does |
|---|---|
| 1 | Base OS setup on `ailab-dev`, `ailab-ml`, `ailab-ds`, `ailab-app`, `ailab-k8s` |
| 2 | Provision all role services via native systemd installs |
| 3 | Seed data on the applicable hosts |
| 4 | Run `verify-lab.sh` |

## Expected Service Distribution

| Host | Expected running lab services |
|---|---|
| `ailab-dev` | 5 |
| `ailab-ml` | 14 |
| `ailab-ds` | 5 |
| `ailab-app` | 7 |

## Verification Targets

`verify-lab.sh` now checks:

- 6 VM ping checks
- 6 VM SSH checks
- 29 service health checks
- deep validation for seeded data and new app/mock surfaces

That gives **62 total checks** when the full deep-validation path is included.

## Optional Ansible Wrapper

If you want inventory-driven orchestration without changing the underlying role scripts:

```bash
bash lab-scripts/deploy-ansible.sh --phase all
```

This remains optional. See [Deployment Evolution](evolution.md).
