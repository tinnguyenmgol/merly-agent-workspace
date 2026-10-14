#!/usr/bin/env bash
set -euo pipefail
[[ $(id -u) == 0 ]] || { echo 'Run with sudo'; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
dst=/opt/merly-hermes/data
[[ -f "$dst/config.yaml" && -f "$dst/workspace_mcp.py" ]] || { echo 'Hermes files missing'; exit 1; }
python3 -m py_compile "$here/workspace_mcp.py" "$here/workspace_import_document.py"
install -m 644 "$here/workspace_mcp.py" "$dst/workspace_mcp.py"
install -m 644 "$here/workspace_import_document.py" "$dst/workspace_import_document.py"
python3 - <<'PY'
from pathlib import Path
from datetime import datetime
import yaml,os,shutil,tempfile
p=Path("/opt/merly-hermes/data/config.yaml")
d=yaml.safe_load(p.read_text())
m=d.get("mcp_servers",{}).get("workspace")
if not isinstance(m,dict): raise SystemExit("Workspace MCP not registered")
tools=m.setdefault("tools",{})
incl=tools.setdefault("include",[])
if not isinstance(incl,list): raise SystemExit("MCP include list incompatible")
if "workspace_import_document" not in incl: incl.append("workspace_import_document")
b=p.with_name("config.yaml.before-import-"+datetime.now().strftime("%Y%m%d%H%M%S"))
shutil.copy2(p,b)
fd,tmp=tempfile.mkstemp(dir=p.parent,prefix=".config-import-")
with os.fdopen(fd,"w") as f: yaml.safe_dump(d,f,allow_unicode=True,sort_keys=False)
st=p.stat()
os.chmod(tmp,st.st_mode&0o777)
os.chown(tmp,st.st_uid,st.st_gid)
os.replace(tmp,p)
PY
echo 'IMPORT_TOOL_READY: Send /reload-mcp then Approve Once in Telegram.'
echo 'NOTE: Telegram file must have been downloaded into Hermes cache/documents before import.'
