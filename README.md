# Glass Claude

Audit logging for Claude Code — see what Claude does outside your project. **macOS only.**

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/xexi/glass_claude/main/install.sh | bash
```

That's it. Works globally for all projects.

## What It Does

When Claude Code runs, it can access files, run commands, search the web, and more. Glass Claude logs operations **outside your project** so you can:

- **Review** what Claude accessed beyond your codebase
- **Detect** unexpected external access
- **Comply** with security policies

## What Gets Logged

| Tool | When Logged |
|------|-------------|
| Read / Write / Edit | Outside project |
| Glob / Grep | Search outside project |
| Bash | Commands with external paths |
| Task | Always |
| WebFetch / WebSearch | Always |
| MCP tools (mcp__*) | Always |
| Unknown tools | Always |

**Not logged:** Operations inside your project, internal tools (TodoWrite, etc.)

## Viewing Logs

```bash
# View audit log
cat ~/.claude/debug/audit.log

# View errors
cat ~/.claude/debug/error.log

# Watch in real-time
tail -f ~/.claude/debug/audit.log
```

## Log Format

**audit.log:**
```
TIMESTAMP|TOOL|TARGET
2026-01-15T04:30:00|Read|~/other-project/secret.txt
2026-01-15T04:30:05|Bash|brew install something
2026-01-15T04:30:10|WebSearch|how to do something
```

**error.log:**
```
TIMESTAMP|TOOL|TYPE|MESSAGE
2026-01-15T04:30:00|Read|RESULT_ERROR|Permission denied
2026-01-15T04:30:05|SYSTEM|FATAL|CLAUDE_PROJECT_DIR not set
```

## How It Works

```
Claude Code executes a tool
         ↓
PostToolUse hook triggers → audit-log.sh receives JSON
         ↓
Script checks:
  • Is target inside project? → Skip
  • Is it an internal tool? → Skip
  • Otherwise → Log it
         ↓
Append to ~/.claude/debug/audit.log
```

## Use with Sandbox

Glass Claude pairs well with Claude Code's sandbox (`/sandbox`):

| Layer | Purpose |
|-------|---------|
| **Sandbox** | Restricts what Claude *can* do |
| **Glass Claude** | Logs what Claude *did* do |

Together: prevention + detection.

## Hardened Security Settings

Included `.claude/settings.json` blocks secrets, credentials, and dangerous commands. Copy to your project or `~/.claude/` for global use.

**Bypass when needed:**
- One-time: Allow when prompted
- Session: `/allowed-tools` to manage session permissions
- Project: Add to `allow` array in `.claude/settings.json`

## Files

After installation:

```
~/.glass-claude/
├── audit-log.sh      ← Audit script
└── jq                ← JSON parser (if not system-installed)

~/.claude/
├── settings.json     ← Hook configuration
└── audit/
    ├── audit.log     ← Tool usage log
    └── error.log     ← Errors and spec changes
```

## Spec Validation

Glass Claude validates the Claude Code hook spec on every run. If the spec changes (e.g., `CLAUDE_PROJECT_DIR` is removed), auditing stops and logs a FATAL error. This prevents silent failures.

## Uninstall

```bash
rm -rf ~/.glass-claude
# Remove "hooks" section from ~/.claude/settings.json
```

## License

MIT
