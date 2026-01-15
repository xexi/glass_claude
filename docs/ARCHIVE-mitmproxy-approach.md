# ARCHIVED: mitmproxy Traffic Interception Approach

> **Status**: Archived on 2026-01-15
> **Reason**: Project pivoted to sandbox + audit logging approach (simpler, no external tools)

## Original Intention

Glass Claude initially aimed to inspect Claude Code's outbound API traffic using **mitmproxy** as an HTTPS intercepting proxy. The goal was to see exactly what data Claude Code sends to `api.anthropic.com` before TLS encryption.

### Why This Worked

Claude Code does NOT use certificate pinning, allowing standard proxy interception via:
- `HTTPS_PROXY` environment variable
- `NODE_EXTRA_CA_CERTS` for custom CA trust

### Components (Now Removed)

| File | Purpose |
|------|---------|
| `capture_requests.py` | mitmproxy addon - saved API requests as JSON |
| `start-capture.sh` | Launched mitmproxy with the addon |
| `run-with-proxy.sh` | Ran Claude with proxy env vars configured |
| `setup-mitmproxy.md` | Setup and usage documentation |

## How It Worked

```
Terminal 1: ./scripts/start-capture.sh --web
Terminal 2: ./scripts/run-with-proxy.sh

Claude Code → mitmproxy (port 8080) → api.anthropic.com
                    ↓
            captures/YYYY-MM-DD/*.json
```

### capture_requests.py Summary

- Filtered requests to `api.anthropic.com` POST `/v1/messages`
- Saved JSON body with metadata: `{captured_at, method, url, request}`
- Output: `captures/YYYY-MM-DD/001_HHMMSS_messages.json`

### Environment Variables Used

```bash
HTTPS_PROXY=http://localhost:8080
HTTP_PROXY=http://localhost:8080
NODE_EXTRA_CA_CERTS=~/.mitmproxy/mitmproxy-ca-cert.pem
```

## Why We Changed

The mitmproxy approach required:
- External tool installation (mitmproxy)
- CA certificate setup
- Running two terminal sessions
- Manual proxy configuration

The new **audit logging approach** is simpler:
- Uses Claude Code's built-in hooks (PostToolUse)
- No external dependencies
- Automatic via `.claude/settings.json`
- Integrates with sandbox for security

## Current Approach

See main README.md for the current audit-based monitoring using:
- `scripts/audit-log.sh` - PostToolUse hook
- `captures/audit.log` - Tool usage outside project
- `captures/error.log` - Error tracking

## Reference: Original Scripts

<details>
<summary>capture_requests.py (click to expand)</summary>

```python
"""mitmproxy addon to capture Claude API request JSON."""
import json
from datetime import datetime
from pathlib import Path
from mitmproxy import http, ctx

CAPTURE_DIR = Path(__file__).parent.parent / "captures"
TARGET_HOSTS = ["api.anthropic.com"]
TARGET_PATHS = ["/v1/messages"]

class ClaudeRequestCapture:
    def __init__(self):
        self.counter = 0
        self.session_date = datetime.now().strftime("%Y-%m-%d")
        self.session_dir = CAPTURE_DIR / self.session_date
        self.session_dir.mkdir(parents=True, exist_ok=True)

    def request(self, flow: http.HTTPFlow) -> None:
        if flow.request.host not in TARGET_HOSTS:
            return
        if not any(flow.request.path.startswith(p) for p in TARGET_PATHS):
            return
        if flow.request.method != "POST":
            return

        try:
            body = json.loads(flow.request.get_text())
            self.counter += 1
            timestamp = datetime.now().strftime("%H%M%S")
            endpoint = flow.request.path.split("/")[-1]
            filename = f"{self.counter:03d}_{timestamp}_{endpoint}.json"

            output = {
                "captured_at": datetime.now().isoformat(),
                "method": flow.request.method,
                "url": flow.request.pretty_url,
                "request": body
            }

            with open(self.session_dir / filename, "w") as f:
                json.dump(output, f, indent=2)
        except Exception as e:
            ctx.log.error(f"Error: {e}")

addons = [ClaudeRequestCapture()]
```

</details>

<details>
<summary>start-capture.sh (click to expand)</summary>

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_SCRIPT="$SCRIPT_DIR/capture_requests.py"
PROXY_PORT="${PROXY_PORT:-8080}"

if [[ "$1" == "--web" ]]; then
    exec mitmweb -s "$CAPTURE_SCRIPT" --listen-port "$PROXY_PORT"
else
    exec mitmproxy -s "$CAPTURE_SCRIPT" --listen-port "$PROXY_PORT"
fi
```

</details>

<details>
<summary>run-with-proxy.sh (click to expand)</summary>

```bash
#!/bin/bash
PROXY_PORT="${PROXY_PORT:-8080}"
PROXY_HOST="${PROXY_HOST:-localhost}"
MITMPROXY_CA="${MITMPROXY_CA:-$HOME/.mitmproxy/mitmproxy-ca-cert.pem}"

export HTTPS_PROXY="http://$PROXY_HOST:$PROXY_PORT"
export HTTP_PROXY="http://$PROXY_HOST:$PROXY_PORT"
export NODE_EXTRA_CA_CERTS="$MITMPROXY_CA"

exec claude "$@"
```

</details>
