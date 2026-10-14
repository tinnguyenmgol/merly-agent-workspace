#!/usr/bin/env python3
"""MCP stdio bridge: model commands execute ONLY via pinned SSH in isolated Workspace."""
import json, os, shlex, subprocess, sys
CFG="/opt/data/ssh-workspace/config"
TOOL={"name":"workspace_shell","description":"Run commands in isolated Merly Workspace as uid 10001, not inside Hermes or on VPS host. Working directory /workspace; /monitor/status.json is read-only. No production deploy, Docker socket, or sudo. Use for offline code and tests only.","inputSchema":{"type":"object","properties":{"command":{"type":"string","minLength":1,"maxLength":4000}},"required":["command"],"additionalProperties":False}}
def send(id,result=None,error=None):
    p={"jsonrpc":"2.0","id":id}
    if error is None:p["result"]=result
    else:p["error"]={"code":-32603,"message":error}
    sys.stdout.write(json.dumps(p,ensure_ascii=False)+"\n");sys.stdout.flush()
def execute(cmd):
    if not isinstance(cmd,str) or not 1<=len(cmd)<=4000:
        return {"isError":True,"content":[{"type":"text","text":"Invalid command"}]}
    if not os.path.isfile(CFG):
        return {"isError":True,"content":[{"type":"text","text":"Workspace SSH configuration unavailable"}]}
    # No local shell; arbitrary commands are run only at fixed SSH target 'workspace'.
    remote="/bin/bash -lc "+shlex.quote("cd /workspace && "+cmd)
    argv=["/usr/bin/ssh","-T","-F",CFG,"-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","-o","ConnectTimeout=8","workspace",remote]
    try:
        r=subprocess.run(argv,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=55,check=False)
        return {"isError":r.returncode!=0,"content":[{"type":"text","text":("exit="+str(r.returncode)+"\n"+r.stdout+r.stderr)[:20000]}]}
    except subprocess.TimeoutExpired:
        return {"isError":True,"content":[{"type":"text","text":"SSH command timed out"}]}
    except (OSError,ValueError) as e:
        return {"isError":True,"content":[{"type":"text","text":"SSH invocation error: "+type(e).__name__}]}
def handle(m):
    id=m.get("id")
    if id is None:return
    method=m.get("method")
    if method=="initialize":
        send(id,{"protocolVersion":(m.get("params") or {}).get("protocolVersion","2025-03-26"),"capabilities":{"tools":{"listChanged":False}},"serverInfo":{"name":"merly-workspace","version":"0.1.0"}})
    elif method=="tools/list":send(id,{"tools":[TOOL]})
    elif method=="ping":send(id,{})
    elif method=="tools/call":
        p=m.get("params") or {}
        if p.get("name")!="workspace_shell":send(id,error="Unknown tool")
        else:send(id,execute((p.get("arguments") or {}).get("command")))
    else:send(id,error="Unsupported method")
for line in sys.stdin:
    try:
        msg=json.loads(line)
        if isinstance(msg,dict):handle(msg)
    except (ValueError,TypeError) as e:
        print("Rejected MCP request: "+type(e).__name__,file=sys.stderr)
