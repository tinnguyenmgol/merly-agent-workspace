#!/usr/bin/env python3
"""Enable only Merly's isolated Workspace MCP for Telegram, after a live SSH preflight."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime

import yaml

DATA = Path("/opt/merly-hermes/data")
CFG = DATA / "config.yaml"
BRIDGE = DATA / "workspace_mcp.py"

def fail(message):
    raise SystemExit("ACTIVATION BLOCKED: " + message)

if os.geteuid() != 0:
    fail("Run with sudo.")
if not CFG.is_file() or not BRIDGE.is_file():
    fail("Hermes config or workspace_mcp.py missing.")
if not (DATA / "ssh-workspace" / "config").is_file():
    fail("SSH setup was not found; do not enable tools.")

docker = subprocess.run(
    ["docker", "ps", "--format", "{{.ID}} {{.Names}}"],
    capture_output=True, text=True, check=True, timeout=10
)
matches = [
    line.split()[0] for line in docker.stdout.splitlines()
    if len(line.split()) == 2 and line.split()[1].startswith("hermes-")
]
if len(matches) != 1:
    fail("Expected exactly one running Hermes container.")
cid = matches[0]

probe = subprocess.run(
    ["docker", "exec", cid, "sh", "-c", "command -v python3 || command -v python"],
    capture_output=True, text=True, check=True, timeout=10
)
python_bin = probe.stdout.strip().splitlines()[-1]
if not python_bin.startswith("/"):
    fail("Python executable path could not be determined.")

messages = [
    {
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": "2025-03-26",
            "capabilities": {},
            "clientInfo": {"name": "merly-preflight", "version": "1.0"}
        }
    },
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
    {
        "jsonrpc": "2.0", "id": 3, "method": "tools/call",
        "params": {"name": "workspace_shell", "arguments": {"command": "id -u"}}
    }
]
payload = "".join(json.dumps(x) + "\n" for x in messages)
try:
    test = subprocess.run(
        ["docker", "exec", "-i", cid, python_bin, "-u", "/opt/data/workspace_mcp.py"],
        input=payload, capture_output=True, text=True, timeout=35
    )
except subprocess.TimeoutExpired:
    fail("MCP handshake/SSH call timed out. Configuration unchanged.")
if test.returncode:
    fail("MCP process failed: " + test.stderr[:250])
try:
    results = {x["id"]: x for x in map(json.loads, test.stdout.splitlines()) if "id" in x}
    assert 1 in results and "result" in results[1]
    assert 2 in results
    tools = results[2]["result"]["tools"]
    assert any(x.get("name") == "workspace_shell" for x in tools)
    result = results[3]["result"]
    assert not result.get("isError", False)
    texts = [part.get("text", "") for part in result["content"] if part.get("type") == "text"]
    assert any("exit=0" in t and "10001" in t for t in texts)
except (KeyError, TypeError, ValueError, AssertionError) as e:
    fail("MCP tool did not confirm UID=10001; config unchanged. " + str(e))
print("MCP PREFLIGHT PASS: Workspace command returned UID 10001.")

raw = yaml.safe_load(CFG.read_text()) or {}
if not isinstance(raw, dict):
    fail("Hermes config is not a YAML mapping.")
servers = raw.setdefault("mcp_servers", {})
if not isinstance(servers, dict):
    fail("mcp_servers is not a mapping.")
if "workspace" in servers:
    fail("An MCP server named 'workspace' already exists; review before overwriting.")
platform = raw.setdefault("platform_toolsets", {})
if not isinstance(platform, dict):
    fail("platform_toolsets is not a mapping.")
telegram = platform.get("telegram")
if not isinstance(telegram, list):
    fail("Telegram toolsets are not a list; refusing to overwrite.")
if (raw.get("terminal") or {}).get("backend", "local") != "local":
    fail("Terminal backend is no longer local; review before activation.")
if (raw.get("gateway") or {}).get("allow_all_users") is not False:
    fail("Gateway access restriction is not confirmed.")

servers["workspace"] = {
    "command": python_bin,
    "args": ["-u", "/opt/data/workspace_mcp.py"],
    "enabled": True,
    "timeout": 75,
    "connect_timeout": 20,
    "tools": {"include": ["workspace_shell"], "resources": False, "prompts": False},
    "sampling": {"enabled": False}
}
if "mcp-workspace" not in telegram:
    telegram.append("mcp-workspace")

backup = CFG.with_name("config.yaml.before-workspace-mcp-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
shutil.copy2(CFG, backup)
fd, tmp = tempfile.mkstemp(prefix=".config.workspace.", dir=str(CFG.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        yaml.safe_dump(raw, f, allow_unicode=True, sort_keys=False)
        f.flush()
        os.fsync(f.fileno())
    original = CFG.stat()
    os.chmod(tmp, original.st_mode & 0o7777)
    os.chown(tmp, original.st_uid, original.st_gid)
    os.replace(tmp, CFG)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise
print("MCP CONFIGURED: mcp-workspace added to Telegram without enabling local terminal.")
print("Backup:", backup)
print("NEXT: send /reload-mcp to the Telegram bot, then /new, then test workspace file creation.")
