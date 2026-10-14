#!/usr/bin/env bash
# Install Merly VPS monitor as a host-side systemd timer; no Docker/Hermes changes.
set -euo pipefail
fail() { printf 'MONITOR INSTALL BLOCKED: %s\n' "$*" >&2; exit 1; }
[[ $(id -u) -eq 0 ]] || fail 'Run with sudo/root.'
command -v systemctl >/dev/null || fail 'systemd not found.'
command -v python3 >/dev/null || fail 'python3 not found.'
command -v timeout >/dev/null || fail 'timeout not found.'

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
COLLECT=/opt/merly-monitor/collect.py
PUBLISH=/opt/merly-monitor/publish-report.py
RUNNER=/usr/local/sbin/merly-monitor-refresh
SERVICE=/etc/systemd/system/merly-monitor-refresh.service
TIMER=/etc/systemd/system/merly-monitor-refresh.timer

[[ -f "$COLLECT" ]] || fail "$COLLECT not found; existing collector required."
[[ -f "$SCRIPTDIR/publish-report.py" ]] || fail 'publish-report.py missing in Git repo.'
[[ -d /var/lib/merly-monitor-public ]] || fail 'Public monitor folder not prepared.'
for f in "$RUNNER" "$SERVICE" "$TIMER"; do
  if [[ -e "$f" ]]; then
    [[ -f "$f" && ! -L "$f" ]] || fail "Unexpected path type: $f"
    grep -qF '# MERLY-MONITOR-MANAGED' "$f" || fail "Unmanaged file exists: $f"
  fi
done
# The host collector itself is preserved, not overwritten.
if [[ -e "$PUBLISH" ]]; then
  [[ -f "$PUBLISH" && ! -L "$PUBLISH" ]] || fail 'Unexpected publisher path.'
  cmp -s "$SCRIPTDIR/publish-report.py" "$PUBLISH" || fail 'Publisher already exists with different content; refusing overwrite.'
fi
install -D -m 0644 "$SCRIPTDIR/publish-report.py" "$PUBLISH"
install -d -m 0755 /usr/local/sbin

cat > "$RUNNER" <<'RUN'
#!/usr/bin/env bash
# MERLY-MONITOR-MANAGED
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
# Collect first; never publish old data after collection failure.
timeout --signal=TERM --kill-after=5s 60s /usr/bin/python3 /opt/merly-monitor/collect.py
/usr/bin/python3 - <<'PY'
import json
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo
path = Path('/var/lib/merly-monitor/status.json')
if not path.is_file():
    raise SystemExit('MONITOR ERROR: collector did not produce status.json')
raw = json.loads(path.read_text(encoding='utf-8'))
value = raw.get('timestamp')
if isinstance(value, (int, float)):
    stamp = datetime.fromtimestamp(value, tz=timezone.utc)
elif isinstance(value, str) and value.strip():
    stamp = datetime.fromisoformat(value.strip().replace('Z', '+00:00'))
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=ZoneInfo('Asia/Ho_Chi_Minh'))
else:
    raise SystemExit('MONITOR ERROR: invalid timestamp')
age = (datetime.now(timezone.utc) - stamp.astimezone(timezone.utc)).total_seconds()
if not (-120 <= age <= 120):
    raise SystemExit('MONITOR ERROR: old/future timestamp (age=%.0fs); refusing to publish' % age)
print('MONITOR COLLECTED: sample age %.0fs' % age)
PY
/usr/bin/python3 /opt/merly-monitor/publish-report.py
RUN
chmod 0755 "$RUNNER"

cat > "$SERVICE" <<'SERVICE_UNIT'
# MERLY-MONITOR-MANAGED
[Unit]
Description=Merly VPS Monitor - collect and publish filtered status
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
User=root
Group=root
WorkingDirectory=/opt/merly-monitor
Environment=TZ=Asia/Ho_Chi_Minh
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/usr/local/sbin/merly-monitor-refresh
TimeoutStartSec=90s
UMask=0022
NoNewPrivileges=true
SERVICE_UNIT

cat > "$TIMER" <<'TIMER_UNIT'
# MERLY-MONITOR-MANAGED
[Unit]
Description=Refresh Merly VPS Monitor every 5 minutes

[Timer]
OnCalendar=*-*-* *:0/5:00
Persistent=true
AccuracySec=30s
Unit=merly-monitor-refresh.service

[Install]
WantedBy=timers.target
TIMER_UNIT

systemctl daemon-reload
# Verify actual collection/publication BEFORE enabling scheduled runs.
if ! systemctl start merly-monitor-refresh.service; then
  echo 'MONITOR TEST FAILED: timer NOT enabled. Recent diagnostic:' >&2
  journalctl -u merly-monitor-refresh.service --no-pager -n 12 >&2 || true
  exit 1
fi
[[ -s /var/lib/merly-monitor-public/status.json ]] || fail 'Public status missing after collection.'
systemctl enable --now merly-monitor-refresh.timer >/dev/null
systemctl is-active --quiet merly-monitor-refresh.timer || fail 'Timer is not active.'
echo 'MONITOR_AUTO_UPDATE_OK: fresh sample published; 5-minute systemd timer active.'
echo 'Next: ask Hermes via Telegram to read /monitor/status.json with workspace_shell.'
