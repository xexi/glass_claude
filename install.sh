#!/bin/bash
# Glass Claude Installer
# curl -sSL https://raw.githubusercontent.com/xexi/glass_claude/main/install.sh | bash
#
# Installs audit logging for Claude Code with checksum-verified dependencies.

set -e

INSTALL_DIR="$HOME/.glass-claude"
SCRIPT_PATH="$INSTALL_DIR/audit-log.sh"
JQ_PATH="$INSTALL_DIR/jq"
SETTINGS_FILE="$HOME/.claude/settings.json"
AUDIT_DIR="$HOME/.claude/debug"

# jq 1.8.1 official checksums from https://github.com/jqlang/jq/releases
JQ_VERSION="1.8.1"
JQ_SHA256_ARM64="a9fe3ea2f86dfc72f6728417521ec9067b343277152b114f4e98d8cb0e263603"
JQ_SHA256_AMD64="e80dbe0d2a2597e3c11c404f03337b981d74b4a8504b70586c354b7697a7c27f"

echo "=== Glass Claude Installer ==="
echo ""

# Create directories
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/.claude"
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
# Logs Claude Code tool usage outside project directory

AUDIT_DIR="$HOME/.claude/debug"
AUDIT_LOG="$AUDIT_DIR/audit.log"
ERROR_LOG="$AUDIT_DIR/error.log"
JQ_PATH="$HOME/.glass-claude/jq"

# Use system jq or bundled jq
if command -v jq &>/dev/null; then
    JQ="jq"
elif [ -x "$JQ_PATH" ]; then
    JQ="$JQ_PATH"
else
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|jq not found" >> "$ERROR_LOG"
    exit 2
fi

# --- Spec Validation ---
# CLAUDE_PROJECT_DIR is set by Claude Code - if missing, spec may have changed
if [ -z "$CLAUDE_PROJECT_DIR" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|CLAUDE_PROJECT_DIR not set - Claude Code spec may have changed" >> "$ERROR_LOG"
    echo "GLASS_CLAUDE: CLAUDE_PROJECT_DIR not set. Auditing disabled until fixed." >&2
    exit 2
fi

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
HOME_DIR="$HOME"

mkdir -p "$AUDIT_DIR" 2>/dev/null

# --- Helper Functions ---
is_inside_project() {
    local path="$1"
    [ -n "$PROJECT_DIR" ] && [[ "$path" == "$PROJECT_DIR"* ]]
}

minimize_path() {
    local path="$1"
    path="${path/#$PROJECT_DIR/\{PROJECT\}}"
    echo "${path/#$HOME_DIR/~}"
}

extract_paths() {
    echo "$1" | grep -oE '(/[^ ]+|~[^ ]*)' | head -5
}

# --- Read and Validate Input ---
INPUT=$(cat)

# Validate expected JSON structure
if ! echo "$INPUT" | "$JQ" -e '.tool_name' &>/dev/null; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%S)|SYSTEM|FATAL|Invalid JSON - tool_name missing" >> "$ERROR_LOG"
    exit 2
fi

TOOL_NAME=$("$JQ" -r '.tool_name' <<< "$INPUT")
TOOL_INPUT=$("$JQ" -c '.tool_input // {}' <<< "$INPUT")
TOOL_RESPONSE=$("$JQ" -r '.tool_response // empty' <<< "$INPUT")

# --- Error Logging ---
# Check tool_response for errors
if echo "$TOOL_RESPONSE" | grep -qiE '(error|failed|exception|denied|refused|timeout)'; then
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
    SNIPPET=$(echo "$TOOL_RESPONSE" | head -c 300 | tr '\n' ' ')
    echo "${TIMESTAMP}|${TOOL_NAME}|RESULT_ERROR|${SNIPPET}" >> "$ERROR_LOG"
fi

# --- Skip Internal Tools ---
case "$TOOL_NAME" in
    TodoWrite|AskUserQuestion|EnterPlanMode|ExitPlanMode|TaskOutput)
        exit 0
        ;;
esac

# --- Determine Target and Log Decision ---
TARGET=""
SHOULD_LOG=false

case "$TOOL_NAME" in
    Read|Write|Edit|NotebookEdit)
        TARGET=$("$JQ" -r '.file_path // .notebook_path // empty' <<< "$TOOL_INPUT")
        if [ -n "$TARGET" ] && ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET=$(minimize_path "$TARGET")
        fi
        ;;

    Glob)
        TARGET=$("$JQ" -r '.path // "."' <<< "$TOOL_INPUT")
        PATTERN=$("$JQ" -r '.pattern // empty' <<< "$TOOL_INPUT")
        if ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET")/$PATTERN"
        fi
        ;;

    Grep)
        TARGET=$("$JQ" -r '.path // "."' <<< "$TOOL_INPUT")
        PATTERN=$("$JQ" -r '.pattern // empty' <<< "$TOOL_INPUT")
        if ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET") pattern:${PATTERN:0:50}"
        fi
        ;;

    Bash)
        CMD=$("$JQ" -r '.command // empty' <<< "$TOOL_INPUT" | head -c 300)
        PATHS=$(extract_paths "$CMD")

        if [ -z "$PATHS" ]; then
            SHOULD_LOG=true
        else
            for P in $PATHS; do
                EXPANDED="${P/#\~/$HOME_DIR}"
                if ! is_inside_project "$EXPANDED"; then
                    SHOULD_LOG=true
                    break
                fi
            done
        fi

        if $SHOULD_LOG; then
            TARGET=$(minimize_path "$CMD")
        fi
        ;;

    Task)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.description // empty' <<< "$TOOL_INPUT")
        ;;

    WebFetch)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.url // empty' <<< "$TOOL_INPUT" | head -c 100)
        ;;

    WebSearch)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.query // empty' <<< "$TOOL_INPUT" | head -c 100)
        ;;

    Skill)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.skill // empty' <<< "$TOOL_INPUT")
        ;;

    KillShell)
        SHOULD_LOG=true
        TARGET=$("$JQ" -r '.shell_id // empty' <<< "$TOOL_INPUT")
        ;;

    mcp__*)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | head -c 150)
        ;;

    *)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | head -c 100)
        ;;
esac

# --- Write Audit Log ---
if $SHOULD_LOG && [ -n "$TARGET" ]; then
    TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S)
    echo "${TIMESTAMP}|${TOOL_NAME}|${TARGET}" >> "$AUDIT_LOG"
fi

exit 0
AUDIT_EOF

chmod +x "$SCRIPT_PATH"
echo "Created: $SCRIPT_PATH"

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
echo "  Audit script: $SCRIPT_PATH"
echo "  Hook config:  $SETTINGS_FILE"
echo "  Audit logs:   $AUDIT_DIR/"
echo ""
echo "Run 'claude' in any project. Audit logs appear in ~/.claude/debug/"
echo ""
