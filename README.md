# MERLY Agent Workspace V1 — REVIEW / TRIAL ONLY

Isolated Ubuntu 24.04 SSH workspace for Hermes. **Not production-tested. Do not auto-deploy.**

## Installation

1. Review and run `sudo bash scripts/prepare-host.sh` once on the VPS. Creates an isolated Docker network, SSH keys (private keys remain on host), bind directories, and a filtered monitor sample.
2. Create a **new** Git-sourced Docker Compose resource in Coolify pointing to `/compose.yaml`. Keep the existing Hermes resource unchanged. Deploy manually only after host preparation.
3. Run `sudo bash scripts/check-host.sh` and perform SSH/login, filesystem, host-key and network isolation tests **before** enabling any terminal/file tools for Hermes.

## Scope and access

- Workspace SSH uses `merly-agent` (UID 10001), SSH public-key authentication, port 2222, no host port publishing.
- Hermes will eventually need a reviewed SSH backend, a pinned host key and a private Docker-network attachment. **Do not give Hermes host SSH, Docker socket or sudo.**
- The container can read `/monitor/status.json` from the filtered, read-only host directory.
- `/workspace` is writable and persistent; it has **no hard disk quota**. Configure capacity monitoring or a proper quota before long-running tasks.
- `no-new-privileges`, capability restrictions and `read_only` may interfere with SSH login. Build, run and test the actual container first; do not silently remove hardening.
- Private Docker network is not a full firewall. Verify access to host/gateway and sensitive production targets with explicit, authorized tests.
- `scripts/publish-report.py` publishes only a **single sample**. Collection/scheduling of updates remains to be configured; stale timestamps must not be treated as healthy.
- The provided healthcheck only verifies a TCP listener, **not successful SSH authentication**.
- Never commit private keys, tokens, Docker socket or production secrets.

## Local static checks

```bash
bash -n scripts/*.sh
python3 -m py_compile scripts/publish-report.py
docker compose -f compose.yaml config
```

## Rollback

`scripts/rollback.sh` provides a non-destructive manual rollback procedure. This repository does not modify or remove Hermes/Coolify production resources.
