#!/usr/bin/env python3
"""Gremlets MCP server: lets Claude Code itself talk to the Gremlets on your desktop.

Claude decides when to use these tools: say a short line through the Gremlet working on this project, celebrate
when something lands, lay out its plan as a plank bridge, or ask you to take a look. Everything goes to the Gremlets
app on 127.0.0.1 only.

Install (once):  claude mcp add -s user gremlets -- /usr/bin/python3 ~/DesktopPets/scripts/gremlets-mcp.py
Standard library only (Python 3.9+). Speaks MCP over stdio (JSON-RPC 2.0, one message per line).
"""
import json
import os
import sys
import urllib.parse
import urllib.request

PORT = os.environ.get("GREMLETS_PORT", "47920")
PROJECT = os.path.basename(os.getcwd().rstrip("/")) or "Claude"

TOOLS = [
    {
        "name": "gremlets_say",
        "description": "Say a short line (under 80 characters) through the Gremlet working on this project, as a speech "
                       "bubble on the user's desktop. Use sparingly for moments worth a smile: a milestone, a tricky "
                       "bug found, a heads-up. Not for routine progress.",
        "inputSchema": {"type": "object", "properties": {"text": {"type": "string", "maxLength": 80}}, "required": ["text"]},
    },
    {
        "name": "gremlets_celebrate",
        "description": "The Gremlets celebrate on the user's desktop (a dance and sparkles), with an optional short "
                       "reason. Use when something significant lands: tests go green after a struggle, a feature ships.",
        "inputSchema": {"type": "object", "properties": {"reason": {"type": "string", "maxLength": 60}}},
    },
    {
        "name": "gremlets_plan",
        "description": "Show your plan as a plank bridge on the user's terminal: one plank per step, solid when done. "
                       "Call it when you lay out a multi-step plan and again as steps finish. Optionally name the step "
                       "you're starting (shown briefly).",
        "inputSchema": {"type": "object", "properties": {
            "total": {"type": "integer", "minimum": 0, "maximum": 30},
            "done": {"type": "integer", "minimum": 0},
            "current": {"type": "string", "maxLength": 60},
        }, "required": ["total", "done"]},
    },
    {
        "name": "gremlets_request_review",
        "description": "Ask the user to come and look: the Gremlet hangs a lantern on the tree and waves with a short "
                       "message. Use when you need the user's eyes on something before continuing.",
        "inputSchema": {"type": "object", "properties": {"message": {"type": "string", "maxLength": 80}}, "required": ["message"]},
    },
    {
        "name": "gremlets_status",
        "description": "What the Gremlets on the user's desktop are up to right now (who is out, what they're doing).",
        "inputSchema": {"type": "object", "properties": {}},
    },
]


def call_app(action, params):
    q = dict(params, action=action, project=PROJECT)
    url = f"http://127.0.0.1:{PORT}/mcp?" + urllib.parse.urlencode(q)
    req = urllib.request.Request(url, method="POST", headers={"X-Gremlets": "1"})
    try:
        with urllib.request.urlopen(req, timeout=3) as r:
            return r.read().decode("utf-8", "replace")
    except Exception as e:  # the app isn't running, or said no
        return json.dumps({"ok": False, "error": f"Gremlets app not reachable: {e}"})


def handle(msg):
    method, mid = msg.get("method"), msg.get("id")
    if method == "initialize":
        return {"jsonrpc": "2.0", "id": mid, "result": {
            "protocolVersion": msg.get("params", {}).get("protocolVersion", "2024-11-05"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "gremlets", "version": "1.0"},
        }}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}}
    if method == "tools/call":
        p = msg.get("params", {})
        name, args = p.get("name", ""), p.get("arguments") or {}
        action = name.replace("gremlets_", "", 1)
        if action not in ("say", "celebrate", "plan", "request_review", "status"):
            return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32602, "message": f"unknown tool {name}"}}
        params = {k: str(v) for k, v in args.items() if v is not None}
        out = call_app(action, params)
        ok = '"ok":true' in out.replace(" ", "")
        return {"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": out}], "isError": not ok}}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": mid, "result": {}}
    if mid is None:
        return None  # a notification (e.g. notifications/initialized)
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": f"method not found: {method}"}}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        reply = handle(msg)
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
