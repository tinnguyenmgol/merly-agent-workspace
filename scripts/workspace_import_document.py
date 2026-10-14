#!/usr/bin/env python3
"""Import a recent Telegram cached spreadsheet to isolated Workspace via SSH."""
import json, os, pathlib, secrets, shlex, subprocess, sys, time
BASE=pathlib.Path("/opt/data/cache/documents")
CFG="/opt/data/ssh-workspace/config"
ALLOWED={".xlsx",".xls",".csv",".tsv"}
MAX=10*1024*1024
def main():
    hint=(sys.argv[1] if len(sys.argv)>1 else "").strip()
    if len(hint)>120 or "/" in hint or "\\" in hint: raise ValueError("Invalid filename hint")
    if not BASE.is_dir(): raise ValueError("Hermes document cache not found")
    entries=[]
    for p in BASE.iterdir():
        if p.is_symlink() or not p.is_file() or p.suffix.lower() not in ALLOWED: continue
        if hint and hint.casefold() not in p.name.casefold(): continue
        st=p.stat()
        if 0<st.st_size<=MAX and 0<=time.time()-st.st_mtime<7200:
            entries.append((st.st_mtime,p,st.st_size))
    if not entries: raise ValueError("No recent matching spreadsheet in Hermes cache; please resend file.")
    entries.sort(reverse=True)
    _,p,size=entries[0]
    name="telegram-"+secrets.token_hex(8)+p.suffix.lower()
    dest="/workspace/input/"+name
    data=p.read_bytes()
    if len(data)!=size: raise ValueError("Cached document changed during upload")
    cmd=["/usr/bin/ssh","-T","-F",CFG,"-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","workspace","umask 077; mkdir -p /workspace/input && cat > "+shlex.quote(dest)]
    r=subprocess.run(cmd,input=data,capture_output=True,timeout=55,check=False)
    if r.returncode: raise ValueError("SSH transfer failed (status "+str(r.returncode)+")")
    print("IMPORTED_TO_WORKSPACE: "+dest+" ("+str(size)+" bytes)")
if __name__=="__main__":
    try: main()
    except Exception as e:
        print("UPLOAD_ERROR: "+str(e),file=sys.stderr)
        sys.exit(1)
