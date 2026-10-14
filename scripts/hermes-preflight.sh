#!/usr/bin/env bash
# Read-only preflight for connecting running Hermes -> Merly SSH workspace.
# Does not modify any container, file, Docker network, or Coolify resource.
set -euo pipefail
die() { echo "HERMES PREFLIGHT FAIL: $*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || die "Please run with sudo."
command -v docker >/dev/null || die "Docker unavailable."
command -v python3 >/dev/null || die "Python3 unavailable."

hermes_lines=$(docker ps --format '{{.ID}} {{.Names}}' | awk '$2 ~ /^hermes-/ {print $1}')
workspace_lines=$(docker ps --format '{{.ID}} {{.Names}}' | awk '$2 ~ /^workspace-/ {print $1}')
[[ $(printf '%s\n' "$hermes_lines" | grep -c . || true) -eq 1 ]] || die "Expected one running Hermes."
[[ $(printf '%s\n' "$workspace_lines" | grep -c . || true) -eq 1 ]] || die "Expected one running workspace."
hermes="$hermes_lines"
workspace="$workspace_lines"
echo "=== Running containers ==="
docker ps --filter "id=$hermes" --filter "id=$workspace" --format '{{.Names}} {{.Status}}'
echo "=== Hermes non-sensitive runtime information ==="
docker exec "$hermes" sh -c 'printf "USER_ID="; id -u; printf "GROUP_ID="; id -g; printf "HOME=%s\n" "$HOME"; printf "SSH_CLIENT="; command -v ssh || true; printf "DATA_MOUNT="; if test -d /opt/data; then echo yes; else echo no; fi'
echo "=== Hermes Docker networks ==="
docker inspect "$hermes" --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}'
echo
echo "=== Workspace Docker networks ==="
docker inspect "$workspace" --format '{{range $name, $net := .NetworkSettings.Networks}}{{$name}} {{end}}'
echo
echo "=== Shared network status ==="
attached=$(docker inspect "$hermes" --format '{{if index .NetworkSettings.Networks "merly-agent-private"}}yes{{else}}no{{end}}')
echo "Hermes already on merly-agent-private: $attached"
echo "=== SSH key material checks: file presence only ==="
for path in /opt/merly-workspace-access/agent-login.key /opt/merly-workspace-access/merly-agent.pub /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key.pub; do
  [[ -f "$path" ]] || die "Missing key file: $path"
  echo "Present: $path"
done
echo "=== Hermes data mount and config: paths and key names ONLY ==="
docker inspect "$hermes" --format '{{range .Mounts}}{{if eq .Destination "/opt/data"}}DataMount={{.Source}} RW={{.RW}}{{end}}{{end}}'
python3 - <<'PY'
from pathlib import Path
try:
 import yaml
except ImportError:
 print("PyYAML is absent on HOST; config inspection skipped.")
 raise SystemExit(0)
p = Path('/opt/merly-hermes/data/config.yaml')
if not p.is_file():
 print("Config path missing; verify actual HERMES_HOME before changing anything.")
 raise SystemExit(0)
v=yaml.safe_load(p.read_text()) or {}
print("terminal.backend:", (v.get('terminal') or {}).get('backend','not set'))
print("platform_toolsets.telegram:", (v.get('platform_toolsets') or {}).get('telegram','not set'))
print("gateway.allow_all_users:", (v.get('gateway') or {}).get('allow_all_users','not set'))
PY
echo "PREFLIGHT COMPLETE (read-only). Do not copy private keys or secrets to Telegram."
