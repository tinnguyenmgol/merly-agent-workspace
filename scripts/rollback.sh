#!/usr/bin/env bash
set -euo pipefail
cat <<'MSG'
ROLLBACK (manual and non-destructive):
1. In Coolify, STOP only the new merly-agent-workspace resource.
2. Undo any separately approved Hermes SSH config/network changes.
3. Leave /opt/merly-workspace-data and /opt/merly-workspace-access untouched for investigation.
NEVER run 'docker compose down -v', docker prune, or delete production volumes.
MSG
