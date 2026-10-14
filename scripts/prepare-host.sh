#!/usr/bin/env bash
set -euo pipefail

die() { printf 'PREPARE ERROR: %s\n' "$*" >&2; exit 1; }

[[ $(id -u) -eq 0 ]] || die "Run as root using sudo."
command -v docker >/dev/null || die "Docker is missing."
command -v ssh-keygen >/dev/null || die "ssh-keygen is missing."

ACCESS=/opt/merly-workspace-access
DATA=/opt/merly-workspace-data
PUBLIC=/var/lib/merly-monitor-public
AUTHORIZED="$ACCESS/merly-agent.pub"
LOGIN="$ACCESS/agent-login.key"
HOSTKEY="$ACCESS/host_keys/ssh_host_ed25519_key"

install -d -m 0700 "$ACCESS" "$ACCESS/host_keys"
install -d -o 10001 -g 10001 -m 0750 "$DATA"
install -d -o 10001 -g 10001 -m 0700 "$DATA/tmp"
install -d -m 0755 "$PUBLIC"

# A failed Compose start can leave a directory at a FILE bind-mount path.
# Remove ONLY an EMPTY directory; never use rm -rf on host paths.
if [[ -d "$AUTHORIZED" && ! -L "$AUTHORIZED" ]]; then
  echo "Found directory where public-key FILE is required: $AUTHORIZED"
  rmdir -- "$AUTHORIZED" || die "Directory is not empty; inspect it manually. No files deleted."
  echo "Removed the empty placeholder directory."
fi
[[ ! -L "$AUTHORIZED" ]] || die "Refusing symlink at $AUTHORIZED"
[[ ! -e "$AUTHORIZED" || -f "$AUTHORIZED" ]] || die "Public key path is not a regular file."

if [[ ! -e "$LOGIN" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C merly-agent-workspace -f "$LOGIN"
fi
[[ -f "$LOGIN" ]] || die "Login private key is not a regular file."
if [[ ! -f "$LOGIN.pub" ]]; then
  ssh-keygen -y -f "$LOGIN" > "$LOGIN.pub"
fi
install -o root -g root -m 0644 "$LOGIN.pub" "$AUTHORIZED"

if [[ ! -e "$HOSTKEY" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$HOSTKEY"
fi
[[ -f "$HOSTKEY" && -f "$HOSTKEY.pub" ]] || die "Invalid/missing workspace host key."
chmod 0600 "$LOGIN" "$HOSTKEY"
chmod 0644 "$LOGIN.pub" "$AUTHORIZED" "$HOSTKEY.pub"
chmod 0700 "$ACCESS" "$ACCESS/host_keys"

if ! docker network inspect merly-agent-private >/dev/null 2>&1; then
  docker network create --internal --driver bridge merly-agent-private >/dev/null
fi
[[ "$(docker network inspect -f '{{.Internal}}' merly-agent-private)" == "true" ]] || die "Existing Docker network is not internal; review manually."

if [[ -f /var/lib/merly-monitor/status.json ]]; then
  python3 "$(dirname "$0")/publish-report.py"
else
  echo "No raw monitor status found; /monitor/status.json will be absent until published."
fi

[[ -f "$AUTHORIZED" ]] || die "SSH public-key bind source missing."
[[ -s "$AUTHORIZED" ]] || die "SSH public-key bind source empty."
ssh-keygen -lf "$AUTHORIZED" >/dev/null || die "Invalid SSH public key."
[[ -d "$ACCESS/host_keys" && -f "$HOSTKEY" && -d "$DATA" && -d "$PUBLIC" ]] || die "Required mount missing."

printf '\nPREPARE OK: bind sources verified; PRIVATE keys remain on VPS.\n'
printf 'Workspace SSH host key fingerprint: '
ssh-keygen -lf "$HOSTKEY.pub"
