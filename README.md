# Glass Claude

**Beta** — Audit logging for Claude Code. See what Claude does. macOS only.

## Installation

```bash
curl -sSL https://raw.githubusercontent.com/xexi/glass_claude/main/install.sh | bash
```

That's it. Works globally.

## What It Does

Claude Code can access files, run commands, search the web, and more. Glass Claude logs these operations so you can:

- **Review** what Claude accessed
- **Detect** unexpected access
- **Comply** with security policies

## What Gets Logged

| Tool | Logged |
|------|--------|
| Read / Write / Edit | Yes |
| Glob / Grep | Yes |
| Bash | Yes |
| Task | Yes |
| WebFetch / WebSearch | Yes |
| MCP tools (mcp__*) | Yes |

**Not logged:** Internal tools (TodoWrite, AskUserQuestion, EnterPlanMode, ExitPlanMode, TaskOutput) — these don't access files or external resources.

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
2026-01-15T04:30:05|SYSTEM|FATAL|jq not found
```

## Configuration

Type `/glass` in Claude Code to configure:

```
> /glass

Glass Claude Configuration

1. Log everything (current)
2. Exclude PWD - only log actions outside current directory

Select mode (1 or 2):
```

## How It Works

```
Claude Code executes a tool
         ↓
PostToolUse hook triggers → audit-log.sh receives JSON
         ↓
Script checks: Internal tool? → Skip
         ↓
Config says exclude_pwd? → Skip if inside PWD
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

Included `.claude/settings.json` blocks secrets, credentials, and dangerous commands. Copy to `~/.claude/` for global use.

**Bypass when needed:**
- One-time: Allow when prompted
- Session: `/allowed-tools` to manage session permissions
- Project: Add to `allow` array in `.claude/settings.json`

## Files

After installation:

```
~/.glass-claude/
├── audit-log.sh      ← Audit script
├── config            ← Configuration (created by /glass)
└── jq                ← JSON parser (if not system-installed)

~/.claude/
├── settings.json     ← Hook configuration
├── commands/
│   └── glass.md      ← /glass command
└── debug/
    ├── audit.log     ← Tool usage log
    └── error.log     ← Errors
```

## Uninstall

```bash
rm -rf ~/.glass-claude
rm ~/.claude/commands/glass.md
# Remove "hooks" section from ~/.claude/settings.json
```

## License

MIT
