#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "Run as root"; exit 1; }
ids=$(docker ps -q --filter 'label=com.docker.compose.service=workspace')
count=$(printf '%s\n' "$ids" | grep -c . || true)
[[ "$count" == 1 ]] || { echo "Expected exactly one running workspace; found $count"; exit 1; }
cid="$ids"
echo "=== Workspace container: $cid ==="
docker ps --filter "id=$cid" --format 'table {{.Names}}\t{{.Status}}'
echo "=== Actual Docker isolation ==="
docker inspect "$cid" --format 'Privileged={{.HostConfig.Privileged}} ReadonlyRootfs={{.HostConfig.ReadonlyRootfs}} Memory={{.HostConfig.Memory}} NanoCPUs={{.HostConfig.NanoCpus}} Pids={{.HostConfig.PidsLimit}} Ports={{json .HostConfig.PortBindings}}'
docker inspect "$cid" --format '{{range .Mounts}}{{.Destination}} RW={{.RW}} Source={{.Source}}{{println}}{{end}}'
for path in /monitor /etc/ssh/host_keys /etc/ssh/authorized_keys/merly-agent; do
  rw=$(docker inspect "$cid" --format '{{range .Mounts}}{{if eq .Destination "'"$path"'"}}{{.RW}}{{end}}{{end}}')
  [[ "$rw" == false ]] || { echo "FAIL: sensitive mount $path must be read-only (found $rw)"; exit 1; }
done
docker inspect "$cid" --format '{{json .HostConfig.PortBindings}}' | grep -Eq '^(null|\{\})$' || { echo "FAIL: host port exposed"; exit 1; }
echo "=== SSH daemon config syntax ==="
docker exec "$cid" /usr/sbin/sshd -t
echo "=== Non-root runtime test ==="
docker exec -u 10001:10001 -w /workspace "$cid" /bin/sh -ec '
  test "$(id -u)" = 10001
  test -r /monitor/status.json
  python3 -m pytest --version
  printf "workspace test\n" > /workspace/.merly-preflight.txt
  test -s /workspace/.merly-preflight.txt
  rm /workspace/.merly-preflight.txt
  ! touch /monitor/.merly-preflight-write-test 2>/dev/null
  ! touch /etc/.merly-preflight-write-test 2>/dev/null
  echo "Non-root workspace read/write and read-only monitor: PASS"
'
echo "PRECHECK PASS (SSH login, network and disk-quota checks still pending)"
