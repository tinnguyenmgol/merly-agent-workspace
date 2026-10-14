#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root'; exit 1; }
command -v docker >/dev/null
command -v ssh-keygen >/dev/null
install -d -m 0700 /opt/merly-workspace-access /opt/merly-workspace-access/host_keys
install -d -o 10001 -g 10001 -m 0750 /opt/merly-workspace-data
install -d -o 10001 -g 10001 -m 0700 /opt/merly-workspace-data/tmp
install -d -m 0755 /var/lib/merly-monitor-public
if [[ ! -e /opt/merly-workspace-access/agent-login.key ]]; then
  ssh-keygen -q -t ed25519 -N '' -C merly-agent-workspace -f /opt/merly-workspace-access/agent-login.key
fi
install -m 0644 /opt/merly-workspace-access/agent-login.key.pub /opt/merly-workspace-access/merly-agent.pub
if [[ ! -e /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key
fi
chmod 0600 /opt/merly-workspace-access/agent-login.key /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key
chmod 0644 /opt/merly-workspace-access/merly-agent.pub /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key.pub
if ! docker network inspect merly-agent-private >/dev/null 2>&1; then
  docker network create --internal --driver bridge merly-agent-private >/dev/null
fi
if [[ -f /var/lib/merly-monitor/status.json ]]; then
  python3 "$(dirname "$0")/publish-report.py"
else
  echo 'No raw monitor report yet; /monitor/status.json will be absent until published.'
fi
printf '\nPREPARE OK. Login PRIVATE key remains on VPS, do not commit or print it.\n'
ssh-keygen -lf /opt/merly-workspace-access/host_keys/ssh_host_ed25519_key.pub
