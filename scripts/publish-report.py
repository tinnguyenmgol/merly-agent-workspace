#!/usr/bin/env python3
"""Strictly allowlist monitor fields; writes atomically; run on VPS, not inside workspace."""
import json, os, pathlib, tempfile
source = pathlib.Path('/var/lib/merly-monitor/status.json')
dest = pathlib.Path('/var/lib/merly-monitor-public/status.json')
s = json.loads(source.read_text())
valid_states = {'running','missing','stopped','unhealthy'}
containers = {}
for key in ('hermes','coolify','coolify_proxy','coolify_db','coolify_redis','coolify_sentinel','merly_app'):
    item = s.get('containers',{}).get(key,{})
    containers[key] = {'state': item.get('state') if item.get('state') in valid_states else 'unknown', 'instances': int(item.get('instances',0))}
result = {
 'timestamp': str(s.get('timestamp','')),
 'cpu_percent': float(s.get('cpu_percent',0)),
 'memory': {k: float(s.get('memory',{}).get(k,0)) for k in ('used_percent','available_mb','total_mb','swap_used_mb')},
 'disk': {k: float(s.get('disk',{}).get(k,0)) for k in ('used_percent','free_gb')},
 'containers': containers,
 'alert_count': len(s.get('alerts',[])),
 'status': s.get('status') if s.get('status') in ('ok','warning','critical') else 'unknown'
}
dest.parent.mkdir(parents=True,exist_ok=True)
fd,tmp = tempfile.mkstemp(prefix='.status-',dir=str(dest.parent),text=True)
try:
    os.fchmod(fd,0o644)
    with os.fdopen(fd,'w') as f:
        json.dump(result,f,indent=2)
        f.flush(); os.fsync(f.fileno())
    os.replace(tmp,dest)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
print('Published allowlisted status:',dest)
