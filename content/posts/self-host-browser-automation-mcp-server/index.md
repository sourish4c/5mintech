---
title: "Self-Host a Browser Automation MCP Server: A Complete Guide (2026)"
description: "A production-tested guide to self-hosting a browser automation MCP server with browser-use and mcp-proxy, shared across AI agents over HTTP/SSE."
slug: "self-host-browser-automation-mcp-server"
date: 2026-09-09T14:39:13.636318+05:30
draft: false
featureimage: "featured.png"
categories:
  - "Self-Hosting"
  - "AI"
tags:
  - "MCP"
  - "browser-use"
  - "browser-automation"
  - "self-hosted"
  - "AI-agents"
  - "tutorial"
---
AI assistants are powerful, but they live in a text world. Give them a browser and they can navigate websites, fill forms, click buttons, take screenshots, and extract content — just like a human. 

<!--more-->

The [Model Context Protocol (MCP)](https://modelcontextprotocol.io) is the standard that makes this possible, the [browser-use](https://github.com/browser-use/browser-use) library drives the browser, and [mcp-proxy](https://github.com/sparfenyuk/mcp-proxy) turns it into a network service. Together they make a **browser automation MCP server** one of the most useful things you can self-host. This guide walks through a production-tested setup where a single browser automation service is shared by every AI agent on your network over HTTP/SSE. For more self-hosted AI tooling ideas, see the [MCP posts](/tags/mcp/) on this blog. No SaaS fees, no per-agent browser instances, no browsing data leaving your machines.

---

## Why self-host a browser MCP server?

- **Free** — the software is open source; you only pay for the LLM calls that power the AI-driven tools
- **Shared** — every agent (Claude Desktop, Cursor, your editor's MCP client, and any other MCP client) connects to the *same* service instead of each spawning its own browser
- **Private** — headless Chromium runs on your hardware; browsing stays inside your network
- **Flexible** — plug in any LLM provider you like, including self-hosted gateways

---

## Architecture

The diagram below shows the data flow: each MCP client connects over HTTP/SSE to `mcp-proxy`, which spawns a dedicated `browser-use --mcp` process. That process controls a headless Chromium instance through the Chrome DevTools Protocol.

```
AI agents on your network
        │
        │  HTTP/SSE  (http://<server>:8080/sse)
        ▼
mcp-proxy  (port 8080, systemd service)
        │  stdio  (spawns a process per SSE session)
        ▼
browser-use --mcp  (Python, 16 MCP tools)
        │  CDP (Chrome DevTools Protocol)
        ▼
Chromium  (headless, --no-sandbox)
        │  HTTP
        ▼
Target website
```

### Components

The four moving parts below turn a plain browser into a shared MCP endpoint:


| Component        | Purpose                                                                                                                                 |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **mcp-proxy**    | Bridges SSE (HTTP) to stdio. Spawns a fresh `browser-use --mcp` process per SSE session, so multiple agents can connect simultaneously. |
| **browser-use**  | Open-source browser automation library. Exposes 16 MCP tools over stdio.                                                                |
| **Chromium**     | Headless browser driven via Playwright/CDP.                                                                                             |
| **LLM endpoint** | OpenAI-compatible API (any provider or self-hosted gateway). Only used by the AI-powered extract/agent tools.                           |


### Why not Docker?

Docker is the usual first instinct, but Chromium inside containers often hits sandbox and CDP timeout issues. Running directly on the VM avoids these entirely — Chromium has full access to system resources and needs no sandbox workarounds beyond `--no-sandbox`. A systemd service gives you the same restart-on-failure and boot-time startup guarantees.

---

## Prerequisites

- A Linux server or VM — 2 vCPUs and 3–4 GB RAM recommended (a headless browser is memory-hungry)
- Python 3.11+
- An OpenAI-compatible LLM endpoint + API key — only required for the AI-driven tools, not for direct browser control

---

## Step 1 — Create the project

```bash
mkdir -p ~/browser-use-mcp
cd ~/browser-use-mcp
python3 -m venv venv
source venv/bin/activate
```

## Step 2 — Install dependencies

Pin exact versions in a `requirements.txt` so the undocumented `--mcp` entry point and the Step 5 patch keep working:

```text
browser-use[cli]==0.2.0
playwright==1.50.0
mcp-proxy==0.12.0
```

Then install and fetch Chromium:

```bash
pip install -r requirements.txt
playwright install chromium
```

Two things to know:

- The `[cli]`​ extra is **required** — it provides the `browser-use --mcp` command that exposes the MCP server over stdio.
- The `--mcp`​ flag is **undocumented** — it doesn't appear in `--help`​. It's a hidden feature that may change in future releases. Pin your `browser-use` version if you want stability.

## Step 3 — Configure browser-use

Create a config file at `~/.config/browseruse/config.json`:

```json
{
  "browser": {
    "headless": true,
    "chromium_sandbox": false,
    "extra_args": ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"]
  },
  "llm": {
    "model": "<your-model>",
    "temperature": 0.7
  },
  "agent": {
    "max_steps": 50,
    "vision": true
  }
}
```

(Exact keys vary by browser-use version — check the project docs. The important parts: headless Chromium, sandbox disabled, and `--no-sandbox --disable-dev-shm-usage --disable-gpu` flags.)

## Step 4 — Set environment variables

Create `~/browser-use-mcp/.env` and lock it down so only your user can read it:

```bash
touch ~/browser-use-mcp/.env
chmod 600 ~/browser-use-mcp/.env
```

```bash
# Your LLM provider key (OpenAI-compatible)
OPENAI_API_KEY=REDACTED_SECRET
# Optional: custom/self-hosted LLM endpoint
OPENAI_BASE_URL=https://your-llm-gateway.example.com/v1
BROWSER_USE_LLM_MODEL=your-model-name
BROWSER_USE_HEADLESS=true
BROWSER_USE_DISABLE_SECURITY=true
```

`BROWSER_USE_DISABLE_SECURITY=true` relaxes Chromium's same-origin policy — required for automation but make sure the service stays on a trusted network (more on that in Security).

## Step 5 — Patch for custom LLM endpoints (only if you use one)

If your LLM endpoint isn't OpenAI's own API, browser-use may not read `OPENAI_BASE_URL` from the config file (its model entry has no base URL field). The fix is a two-line patch:

1. Find `browser_use/mcp/server.py`​ inside your venv (`venv/lib/python*/site-packages/browser_use/mcp/server.py`)
2. Locate where the LLM model is constructed (search for the lines that build the chat model)
3. Append `or os.getenv("OPENAI_BASE_URL")` to the model name resolution, then make sure the env var is loaded

Keep a backup (`cp server.py server.py.bak`​) and **re-apply the patch after every browser-use upgrade**.

## Step 6 — Create the systemd service

`/etc/systemd/system/browser-use-mcp.service`:

```ini
[Unit]
Description=Browser-use MCP server
After=network.target

[Service]
User=your-username
WorkingDirectory=/home/your-username/browser-use-mcp
EnvironmentFile=/home/your-username/browser-use-mcp/.env
ExecStart=/home/your-username/browser-use-mcp/venv/bin/mcp-proxy --host 0.0.0.0 --port 8080 --allow-origin=* --pass-environment -- browser-use --mcp
Restart=on-failure
RestartSec=5
# Limit memory so a runaway browser process can't take the whole machine down
MemoryMax=2G
# Optional: harden with a dedicated user
# User=browseruse

[Install]
WantedBy=multi-user.target
```

Start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now browser-use-mcp
sudo systemctl status browser-use-mcp
```

## Step 7 — Verify it works

```bash
# Check the SSE handshake — should stream an endpoint event
curl -N -H "Accept: text/event-stream" http://<your-host>:8080/sse
```

You should see `event: endpoint`​ followed by `data: /message?session_id=...`. That means the server is accepting MCP sessions.

---

## Step 8 — Wire up your AI clients

### Your MCP client

Add to your project's `mcp.json` or global config:

```json
{
  "mcp": {
    "browser-use": {
      "type": "remote",
      "url": "http://<your-host>:8080/sse",
      "enabled": true
    }
  }
}
```

Restart your MCP client, then try:  *"Navigate to example.com and tell me what the page is about."*

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "browser-use": {
      "url": "http://<your-host>:8080/sse"
    }
  }
}
```

### Cursor / Windsurf

`~/.cursor/mcp.json` (or the equivalent config for your editor):

```json
{
  "mcpServers": {
    "browser-use": {
      "url": "http://<your-host>:8080/sse"
    }
  }
}
```

### Python (mcp SDK)

```python
import asyncio
from mcp import ClientSession
from mcp.client.sse import sse_client

async def main():
    async with sse_client("http://<your-host>:8080/sse") as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            print([t.name for t in tools.tools])
            result = await session.call_tool(
                "browser_navigate", {"url": "https://example.com"}
            )
            print(result.content[0].text)

asyncio.run(main())
```

### curl (manual SSE)

```bash
# Get session endpoint
curl -s -N http://<your-host>:8080/sse
# Returns: event: endpoint
#          data: /message?session_id=...

# POST messages to the returned endpoint
curl -X POST "http://<your-host>:8080/message?session_id=<session>" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

---

## Available MCP tools (16)

browser-use exposes 16 MCP tools. They fall into three groups: direct browser control, LLM-powered extraction/agent tasks, and session cleanup. The direct-control tools are free to call; only the LLM-powered ones consume tokens.

### Direct browser control (no LLM needed)

These tools give you deterministic, programmatic control of the browser and cost no tokens:


| Tool                 | Description                                               |
| -------------------- | --------------------------------------------------------- |
| `browser_navigate`   | Navigate to a URL                                         |
| `browser_click`      | Click element by index or coordinates                     |
| `browser_type`       | Type text into an element                                 |
| `browser_get_state`  | Get current page state (URL, title, interactive elements) |
| `browser_get_html`   | Get page HTML                                             |
| `browser_screenshot` | Take a screenshot                                         |
| `browser_scroll`     | Scroll up/down                                            |
| `browser_go_back`    | Go back in history                                        |
| `browser_list_tabs`  | List open tabs                                            |
| `browser_switch_tab` | Switch to a tab                                           |
| `browser_close_tab`  | Close a tab                                               |


### LLM-powered tools

These tools hand control to the configured LLM, which is where token costs appear:


| Tool                           | Description                                     |
| ------------------------------ | ----------------------------------------------- |
| `browser_extract_content`      | Extract content from current page using the LLM |
| `retry_with_browser_use_agent` | Run an autonomous agent task with the LLM       |


### Session management

Use these to inspect and clean up running browser sessions, which helps keep memory usage bounded:


| Tool                    | Description                  |
| ----------------------- | ---------------------------- |
| `browser_list_sessions` | List active browser sessions |
| `browser_close_session` | Close a specific session     |
| `browser_close_all`     | Close all sessions           |


---

## Management commands

```bash
sudo systemctl status browser-use-mcp   # check status
sudo systemctl restart browser-use-mcp  # restart
sudo journalctl -u browser-use-mcp -f   # follow logs
sudo systemctl stop browser-use-mcp     # stop
sudo systemctl start browser-use-mcp    # start
```

Because every SSE session spawns a fresh browser process, remember to close sessions when you're done (either through your MCP client or by calling `browser_close_session` / `browser_close_all`). If sessions leak, `MemoryMax=2G` will cap the damage, but you should still restart the service or set up a periodic cleanup timer.

---

## Security &amp; operational notes

> ⚠️ **Security warning:** The default setup is intentionally simple, which also makes it dangerous on anything except a *strictly* trusted network. `--allow-origin=*` lets any device on the network connect, `BROWSER_USE_DISABLE_SECURITY=true` disables Chromium's same-origin protections, and there is no authentication. An attacker on the same LAN (a guest device, an IoT gadget, or a compromised machine) can drive a real browser and potentially exfiltrate cookies or session tokens from sites it visits. **Treat a reverse proxy with authentication as mandatory, not optional**, even inside a "trusted" LAN. Caddy, Nginx, or Traefik with basic auth or SSO are common choices.

- **No auth by default** — `--allow-origin=*`​ and no credentials mean *anything on your network* can drive the browser. Do not rely on the LAN being safe.
- **​`BROWSER_USE_DISABLE_SECURITY=true`​**​ **is required for automation** but relaxes Chromium's same-origin policy. That is another reason to put an authenticating reverse proxy in front of the service and never expose it to the internet directly.
- **One browser per session** — each SSE connection spawns a fresh `browser-use --mcp` process. Multiple agents can run concurrently.
- **Only AI tools cost money** — direct navigation, clicking, and screenshots are free. Only `browser_extract_content`​ and `retry_with_browser_use_agent` consume LLM tokens.
- **Re-apply the patch after upgrades** — see Step 5.
- **Rotate keys defensively** — if you ever suspect a screenshot leaked an API key, rotate it (browser-use doesn't log keys, but cheap insurance).

---

## Cost model

The only recurring cost is the LLM provider. Everything else is open source or already-running hardware:


| Component         | Cost                       |
| ----------------- | -------------------------- |
| browser-use       | Free (open source)         |
| Chromium          | Free                       |
| mcp-proxy         | Free (open source)         |
| Server/VM         | Already running (OpEx = 0) |
| **LLM API calls** | **Only cost**              |


Pick a cheap model for extraction tasks — most providers have fast, low-cost tiers that are perfectly adequate for content extraction and page summarization.

---

## FAQ

**Is mcp-proxy free?** Yes. The version used in this guide ([sparfenyuk/mcp-proxy](https://github.com/sparfenyuk/mcp-proxy)) is open source and installed with pip.

**Does this need Docker?** No. This guide intentionally runs on the host VM to avoid Chromium sandbox and CDP timeout issues inside containers. A systemd service provides restart-on-failure behavior.

**Can multiple AI agents use the same browser server at once?** Yes. Every SSE connection spawns a separate `browser-use --mcp` process, so agents can connect concurrently.

**Do direct browser tools cost LLM tokens?** No. Navigation, clicks, screenshots, and DOM access are free. Only `browser_extract_content` and `retry_with_browser_use_agent` call the configured LLM.

**What if `browser-use --mcp` stops working after an upgrade?** Pin an exact `browser-use` version in `requirements.txt`, and re-apply the Step 5 `OPENAI_BASE_URL` patch after every upgrade until the project supports custom endpoints natively.

## Summary

You now have a single, shared browser automation service that any MCP-capable agent on your network can use. It's free except for LLM calls, private by design, and resilient thanks to systemd. Start with direct browser tools, then layer in the LLM-powered extraction once the basics feel solid.