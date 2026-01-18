#!/bin/bash
# Glass Claude Installer
# curl -sSL https://raw.githubusercontent.com/xexi/glass_claude/main/install.sh | bash

set -e

readonly INSTALL_DIR="$HOME/.glass-claude"
readonly SCRIPT_PATH="$INSTALL_DIR/audit-log.sh"
readonly CONFIG_PATH="$INSTALL_DIR/config"
readonly JQ_PATH="$INSTALL_DIR/jq"
readonly SETTINGS_FILE="$HOME/.claude/settings.json"
readonly COMMANDS_DIR="$HOME/.claude/commands"
readonly AUDIT_DIR="$HOME/.claude/debug"

# jq 1.8.1 official checksums from https://github.com/jqlang/jq/releases
readonly JQ_VERSION="1.8.1"
readonly JQ_SHA256_ARM64="a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603"
readonly JQ_SHA256_AMD64="e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f"

echo "=== Glass Claude Installer ==="
echo ""

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.claude"
mkdir -p "$COMMANDS_DIR"
mkdir -p "$AUDIT_DIR"

# --- jq Installation ---
install_jq() {
    echo "Installing jq ${JQ_VERSION}..."

    ARCH=$(uname -m)
    case "$ARCH" in
        arm64|aarch64)
            JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-arm64"
            JQ_SHA256="$JQ_SHA256_ARM64"
            ;;
        x86_64|amd64)
            JQ_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-macos-amd64"
            JQ_SHA256="$JQ_SHA256_AMD64"
            ;;
        *)
            echo "ERROR: Unsupported architecture: $ARCH" >&2
            echo "Please install jq manually: brew install jq" >&2
            exit 1
            ;;
    esac

    TMP_JQ="/tmp/jq-glass-$$"

    echo "Downloading from official GitHub release..."
    curl -fsSL "$JQ_URL" -o "$TMP_JQ"

    echo "Verifying SHA256 checksum..."
    ACTUAL_SHA=$(shasum -a 256 "$TMP_JQ" | cut -d' ' -f1)

    if [ "$ACTUAL_SHA" != "$JQ_SHA256" ]; then
        echo "" >&2
        echo "FATAL: Checksum verification FAILED" >&2
        echo "Expected: $JQ_SHA256" >&2
        echo "Got:      $ACTUAL_SHA" >&2
        echo "" >&2
        echo "This could indicate tampering. Installation aborted." >&2
        rm -f "$TMP_JQ"
        exit 2
    fi

    echo "Checksum verified."
    chmod +x "$TMP_JQ"
    mv "$TMP_JQ" "$JQ_PATH"
    echo "jq installed: $JQ_PATH"
}

# Check for jq
if command -v jq &>/dev/null; then
    JQ_CMD="jq"
    echo "Found system jq: $(which jq)"
elif [ -x "$JQ_PATH" ]; then
    JQ_CMD="$JQ_PATH"
    echo "Found Glass Claude jq: $JQ_PATH"
else
    install_jq
    JQ_CMD="$JQ_PATH"
fi

echo ""

# --- Audit Script ---
echo "Creating audit-log.sh..."

cat > "$SCRIPT_PATH" << 'AUDIT_EOF'
#!/bin/bash
# Glass Claude - Audit Logger
# Logs Claude Code tool usage

set -euo pipefail

readonly AUDIT_DIR="$HOME/.claude/debug"
readonly AUDIT_LOG="$AUDIT_DIR/audit.log"
readonly ERROR_LOG="$AUDIT_DIR/error.log"
readonly CONFIG_FILE="$HOME/.glass-claude/config"
readonly JQ_PATH="$HOME/.glass-claude/jq"
readonly INTERNAL_TOOLS="TodoWrite|AskUserQuestion|EnterPlanMode|ExitPlanMode|TaskOutput"

# --- Setup ---

init_jq() {
    if command -v jq &>/dev/null; then
        echo "jq"
    elif [[ -x "$JQ_PATH" ]]; then
        echo "$JQ_PATH"
    else
        log_error "SYSTEM" "FATAL" "jq not found"
        exit 2
    fi
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && grep -q "^exclude_pwd=true" "$CONFIG_FILE" 2>/dev/null
}

# --- Logging ---

log_error() {
    local tool="$1" type="$2" message="$3"
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|${tool}|${type}|${message}" >> "$ERROR_LOG"
}

log_audit() {
    local tool="$1" target="$2"
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|${tool}|${target}" >> "$AUDIT_LOG"
}

# --- Path Helpers ---

minimize_path() {
    local path="$1"
    path="${path/#$CLAUDE_PROJECT_DIR/\{PWD\}}"
    echo "${path/#$HOME/~}"
}

is_inside_pwd() {
    local path="$1"
    [[ -n "${CLAUDE_PROJECT_DIR:-}" && "$path" == "$CLAUDE_PROJECT_DIR"* ]]
}

extract_paths() {
    grep -oE '(/[^ ]+|~[^ ]*)' <<< "$1" | head -5
}

has_external_path() {
    local cmd="$1"
    local paths
    paths=$(extract_paths "$cmd")

    [[ -z "$paths" ]] && return 0  # No paths = unknown scope = external

    while IFS= read -r p; do
        local expanded="${p/#\~/$HOME}"
        is_inside_pwd "$expanded" || return 0
    done <<< "$paths"

    return 1
}

# --- Target Extraction ---

extract_target() {
    local tool="$1" input="$2"

    case "$tool" in
        Read|Write|Edit|NotebookEdit)
            $JQ -r '.file_path // .notebook_path // empty' <<< "$input"
            ;;
        Glob)
            local path pattern
            path=$($JQ -r '.path // "."' <<< "$input")
            pattern=$($JQ -r '.pattern // empty' <<< "$input")
            echo "${path}/${pattern}"
            ;;
        Grep)
            local path pattern
            path=$($JQ -r '.path // "."' <<< "$input")
            pattern=$($JQ -r '.pattern // empty' <<< "$input")
            echo "${path} pattern:${pattern:0:50}"
            ;;
        Bash)
            $JQ -r '.command // empty' <<< "$input" | head -c 300
            ;;
        Task)
            $JQ -r '.description // empty' <<< "$input"
            ;;
        WebFetch)
            $JQ -r '.url // empty' <<< "$input" | head -c 100
            ;;
        WebSearch)
            $JQ -r '.query // empty' <<< "$input" | head -c 100
            ;;
        Skill)
            $JQ -r '.skill // empty' <<< "$input"
            ;;
        KillShell)
            $JQ -r '.shell_id // empty' <<< "$input"
            ;;
        mcp__*)
            head -c 150 <<< "$input"
            ;;
        *)
            head -c 100 <<< "$input"
            ;;
    esac
}

should_exclude() {
    local tool="$1" target="$2"

    # Never exclude web/external tools
    case "$tool" in
        Task|WebFetch|WebSearch|Skill|KillShell|mcp__*) return 1 ;;
    esac

    # Exclude if inside PWD (when config enabled)
    case "$tool" in
        Bash)
            ! has_external_path "$target"
            ;;
        *)
            is_inside_pwd "$target"
            ;;
    esac
}

# --- Main ---

main() {
    mkdir -p "$AUDIT_DIR" 2>/dev/null

    JQ=$(init_jq)
    EXCLUDE_PWD=$(load_config && echo true || echo false)

    local input tool_name tool_input tool_response
    input=$(cat)

    # Validate JSON
    if ! $JQ -e '.tool_name' <<< "$input" &>/dev/null; then
        log_error "SYSTEM" "FATAL" "Invalid JSON - tool_name missing"
        exit 2
    fi

    tool_name=$($JQ -r '.tool_name' <<< "$input")
    tool_input=$($JQ -c '.tool_input // {}' <<< "$input")
    tool_response=$($JQ -r '.tool_response // empty' <<< "$input")

    # Log errors from tool response
    if grep -qiE '(error|failed|exception|denied|refused|timeout)' <<< "$tool_response"; then
        local snippet
        snippet=$(head -c 300 <<< "$tool_response" | tr '\n' ' ')
        log_error "$tool_name" "RESULT_ERROR" "$snippet"
    fi

    # Skip internal tools
    [[ "$tool_name" =~ ^($INTERNAL_TOOLS)$ ]] && exit 0

    # Extract target
    local target
    target=$(extract_target "$tool_name" "$tool_input")
    [[ -z "$target" ]] && exit 0

    # Apply exclusion filter
    if [[ "$EXCLUDE_PWD" == "true" ]] && should_exclude "$tool_name" "$target"; then
        exit 0
    fi

    # Log it
    log_audit "$tool_name" "$(minimize_path "$target")"
}

main "$@"
AUDIT_EOF

chmod +x "$SCRIPT_PATH"
echo "Created: $SCRIPT_PATH"

echo ""

# --- Slash Command ---
echo "Creating /glass command..."

cat > "$COMMANDS_DIR/glass.md" << 'CMD_EOF'
---
description: Configure Glass Claude logging mode
---

Read ~/.glass-claude/config to check current mode, then present options:

**Glass Claude Configuration**

1. **Log everything** - All Claude actions are logged
2. **Exclude PWD** - Only log actions outside current directory

Current mode: [show current based on config file, default is "Log everything"]

Ask: "Select mode (1 or 2):"

When user selects:
- **1**: Write `exclude_pwd=false` to ~/.glass-claude/config
- **2**: Write `exclude_pwd=true` to ~/.glass-claude/config

Confirm the change with a brief message.
CMD_EOF

echo "Created: $COMMANDS_DIR/glass.md"

echo ""

# --- Configure Hook ---
echo "Configuring Claude Code hook..."

HOOK_JSON=$(cat << EOF
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "$SCRIPT_PATH"
          }
        ]
      }
    ]
  }
}
EOF
)

if [ ! -f "$SETTINGS_FILE" ] || [ ! -s "$SETTINGS_FILE" ] || [ "$(cat "$SETTINGS_FILE" 2>/dev/null)" = "{}" ]; then
    echo "$HOOK_JSON" > "$SETTINGS_FILE"
    echo "Created: $SETTINGS_FILE"
else
    # Settings exist - check if we can merge with jq
    if echo "$(cat "$SETTINGS_FILE")" | "$JQ_CMD" -e '.hooks.PostToolUse' &>/dev/null; then
        echo ""
        echo "WARNING: PostToolUse hook already exists in $SETTINGS_FILE"
        echo "Please manually add Glass Claude hook or merge configurations."
    else
        # Merge hooks into existing settings
        MERGED=$("$JQ_CMD" --argjson hook "$HOOK_JSON" '. * $hook' "$SETTINGS_FILE")
        echo "$MERGED" > "$SETTINGS_FILE"
        echo "Updated: $SETTINGS_FILE"
    fi
fi

echo ""
echo "=== Installation Complete ==="
echo ""
echo "  Audit logs:   $AUDIT_DIR/"
echo "  Configure:    Type /glass in Claude Code"
echo ""
