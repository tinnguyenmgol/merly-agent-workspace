#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo 'Run as root'; exit 1; }
echo '== Container candidates =='
docker ps --filter 'label=com.docker.compose.service=workspace' --format '{{.ID}} {{.Names}} {{.Status}}'
ids=$(docker ps -q --filter 'label=com.docker.compose.service=workspace')
count=$(printf '%s\n' "$ids" | grep -c . || true)
[[ "$count" -eq 1 ]] || { echo "Expected one running workspace, found: $count"; exit 1; }
cid=$ids
printf '\n== Isolation ==\n'
docker inspect "$cid" --format 'Privileged={{.HostConfig.Privileged}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} NetworkMode={{.HostConfig.NetworkMode}} Memory={{.HostConfig.Memory}} NanoCPUs={{.HostConfig.NanoCpus}} PidsLimit={{.HostConfig.PidsLimit}} Ports={{json .HostConfig.PortBindings}}'
docker inspect "$cid" --format '{{range .Mounts}}{{.Destination}} RW={{.RW}} Source={{.Source}}{{println}}{{end}}'
printf '\n== Functional checks ==\n'
docker exec "$cid" /bin/sh -c '/usr/sbin/sshd -t && python3 -m pytest --version'
docker exec "$cid" /bin/sh -c 'test -r /monitor/status.json && echo monitor-readable || echo monitor-not-yet-published'
printf '\n== SSH test via docker private network ==\n'
echo 'SSH needs Hermes connected to merly-agent-private; do not publish 2222 to host.'
echo 'Before approval, perform authorized-key login and negative filesystem/network tests.'
