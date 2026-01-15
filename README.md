# Glass Claude

Audit logging for Claude Code — see what Claude does outside your project.

## Why?

When Claude Code runs, it can access files, run commands, search the web, and more. This tool logs those operations so you can:

- **Review** what Claude accessed outside your project
- **Detect** unexpected external access
- **Comply** with security policies

## Features

- Logs **all tools** by default (opt-out, not opt-in)
- **Safe haven**: operations inside your project are not logged
- **Tamper-resistant**: logs stored in `~/.claude/audit/` (outside project)
- **Data minimization**: paths shortened to `~` or `{PROJECT}`
- **Error tracking**: separate log for all errors
- **Zero dependencies**: uses Claude Code's built-in hooks

## Installation

### 1. Copy files to your project

```bash
# Clone or download this repo
git clone https://github.com/youruser/glass_claude.git

# Copy to your project
cp -r glass_claude/scripts your-project/
mkdir -p your-project/.claude
```

### 2. Create settings.local.json

Create `.claude/settings.local.json` with your absolute path:

```bash
cd your-project

# Get your absolute path
pwd
# Example output: /Users/you/projects/your-project
```

Then create the file:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/you/projects/your-project/scripts/audit-log.sh"
          }
        ]
      }
    ]
  }
}
```

**Why settings.local.json?**
- Contains your machine-specific absolute path
- Gitignored (not shared with team)
- Keeps settings.json clean for shared config

### 3. Run Claude Code

```bash
claude
```

Logs automatically appear in `~/.claude/audit/`.

## Viewing Logs

```bash
# View audit log
cat ~/.claude/audit/audit.log

# View errors
cat ~/.claude/audit/error.log

# Watch in real-time
tail -f ~/.claude/audit/audit.log
```

## Log Format

### audit.log

```
TIMESTAMP|TOOL|TARGET
2026-01-15T04:30:00|Read|~/other-project/secret.txt
2026-01-15T04:30:05|Bash|brew install something
2026-01-15T04:30:10|WebSearch|how to do something
```

### error.log

```
TIMESTAMP|TOOL|TYPE|MESSAGE
2026-01-15T04:30:00|Read|ERROR|ENOENT: no such file
2026-01-15T04:30:05|Bash|RESULT_ERROR|Permission denied
```

## What Gets Logged

| Tool | When Logged |
|------|-------------|
| Read / Write / Edit | Outside project |
| Glob / Grep | Search outside project |
| Bash | All commands* |
| Task | Always |
| WebFetch / WebSearch | Always |
| Skill | Always |
| KillShell | Always |
| MCP tools (mcp__*) | Always |
| Unknown tools | Always |

*\*Bash commands operating only on project paths are skipped*

## What's NOT Logged

| Category | Examples |
|----------|----------|
| Project operations | Read/Write inside your project |
| Internal tools | TodoWrite, AskUserQuestion |
| Project-only Bash | `cat ./README.md` |

## How It Works

```
┌─────────────────────────────────────────┐
│  Claude Code executes a tool            │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  PostToolUse hook triggers              │
│  → audit-log.sh receives JSON           │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Script checks:                         │
│  • Is it an internal tool? → Skip       │
│  • Is target inside project? → Skip     │
│  • Otherwise → Log it                   │
└─────────────────┬───────────────────────┘
                  ▼
┌─────────────────────────────────────────┐
│  Append to ~/.claude/audit/audit.log    │
└─────────────────────────────────────────┘
```

## Use with Sandbox

Glass Claude works great with Claude Code's sandbox (`/sandbox`):

| Layer | Purpose |
|-------|---------|
| **Sandbox** | Restricts what Claude *can* do |
| **Glass Claude** | Logs what Claude *did* do |

Together they provide defense-in-depth: prevention + detection.

## File Structure

```
your-project/
├── .claude/
│   ├── settings.json        ← Shared config (optional)
│   └── settings.local.json  ← Hook + personal (gitignored)
├── scripts/
│   └── audit-log.sh         ← Audit script
└── ... your code ...

~/.claude/audit/              ← Logs (outside project)
├── audit.log
└── error.log
```

## Configuration Tips

### Add personal preferences

You can add other settings to your `settings.local.json`:

```json
{
  "hooks": {
    "PostToolUse": [...]
  },
  "permissions": {
    "allow": ["WebSearch"]
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": false
  }
}
```

### Shared vs Personal

| File | Purpose | Git |
|------|---------|-----|
| `settings.json` | Team/shared config | Commit |
| `settings.local.json` | Hooks + personal prefs | Gitignore |

**Note**: `settings.json` is empty `{}` in this repo. Hook configuration goes in `settings.local.json` because paths are machine-specific.

For full settings reference, see: https://docs.anthropic.com/en/docs/claude-code/settings

## License

MIT
