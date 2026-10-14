#!/usr/bin/env bash
# SSH connectivity/authentication preflight. Does NOT modify Hermes or Coolify.
set -euo pipefail
die() { printf 'SSH TEST FAIL: %s\n' "$*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || die "Run using sudo on the VPS."
for bin in docker ssh ssh-keygen awk mktemp; do command -v "$bin" >/dev/null || die "Missing $bin"; done
access=/opt/merly-workspace-access
login="$access/agent-login.key"
hostpub="$access/host_keys/ssh_host_ed25519_key.pub"
[[ -f "$login" && -f "$hostpub" ]] || die "Run prepare-host.sh first."
ids=$(docker ps -q --filter 'label=com.docker.compose.service=workspace')
[[ $(printf '%s\n' "$ids" | grep -c . || true) == 1 ]] || die "Expected exactly one workspace container."
cid="$ids"
ip=$(docker inspect -f '{{with index .NetworkSettings.Networks "merly-agent-private"}}{{.IPAddress}}{{end}}' "$cid")
[[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Workspace not attached to merly-agent-private with IPv4."
tempdir=$(mktemp -d /tmp/merly-ssh-preflight.XXXXXXXX) || die "Cannot create temp directory."
trap 'rm -rf -- "$tempdir"' EXIT
chmod 0700 "$tempdir"
awk '{print "merly-workspace " $1 " " $2}' "$hostpub" > "$tempdir/known_hosts"
chmod 0600 "$tempdir/known_hosts"
[[ -s "$tempdir/known_hosts" ]] || die "Cannot load pinned SSH host key."

make_config() {
  cat > "$1" <<EOF
Host workspace
  HostName $ip
  Port 2222
  User $2
  IdentityFile $3
  HostKeyAlias merly-workspace
  UserKnownHostsFile $tempdir/known_hosts
  StrictHostKeyChecking yes
  BatchMode yes
  ConnectTimeout 8
  ConnectionAttempts 1
  IdentitiesOnly yes
  IdentityAgent none
  ForwardAgent no
  PreferredAuthentications publickey
  PasswordAuthentication no
  KbdInteractiveAuthentication no
EOF
  chmod 0600 "$1"
}

make_config "$tempdir/good" merly-agent "$login"
echo "=== Expected workspace host-key fingerprint ==="
ssh-keygen -lf "$hostpub"
echo "=== Checking authenticated login ==="
uid=$(ssh -F "$tempdir/good" -T workspace 'id -u') || die "SSH login failed. See SSH error above."
[[ "$uid" == 10001 ]] || die "Unexpected SSH UID: $uid"
echo "PASS: SSH login as UID 10001"

ssh -F "$tempdir/good" -T workspace 'set -eu; test -r /monitor/status.json; printf test > /workspace/.ssh-preflight-test; test -s /workspace/.ssh-preflight-test; rm /workspace/.ssh-preflight-test; ! touch /monitor/.ssh-write-test 2>/dev/null; ! touch /etc/.ssh-write-test 2>/dev/null' \
  || die "SSH filesystem permission test failed."
echo "PASS: workspace writes; monitor and system directories reject writes"

ssh-keygen -q -t ed25519 -N '' -f "$tempdir/invalid" >/dev/null
make_config "$tempdir/wrong" merly-agent "$tempdir/invalid"
if ssh -F "$tempdir/wrong" -T workspace true >/dev/null 2>&1; then
  die "Invalid SSH key unexpectedly allowed login."
fi
echo "PASS: invalid login key rejected"
make_config "$tempdir/root" root "$login"
if ssh -F "$tempdir/root" -T workspace true >/dev/null 2>&1; then
  die "Root SSH login unexpectedly allowed."
fi
echo "PASS: root SSH login rejected"
echo "SSH TEST PASS (remaining: Hermes network connection, egress and disk limits)."
