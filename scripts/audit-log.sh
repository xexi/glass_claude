#!/bin/bash
# Claude Code Audit Logger
# Logs ALL tools by default, skips only internal-only tools
# Audit logs stored in ~/.claude/audit/ (outside any project)
# Data minimization: uses relative paths, strips home directory

# Setup paths - audit log OUTSIDE project for tamper resistance
AUDIT_DIR="$HOME/.claude/audit"
AUDIT_LOG="${AUDIT_DIR}/audit.log"
ERROR_LOG="${AUDIT_DIR}/error.log"
HOME_DIR="$HOME"

# Determine project dir (for path comparison)
SCRIPT_DIR="$(dirname "$0")"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)" || PROJECT_DIR=""

# Create audit directory
mkdir -p "$AUDIT_DIR" 2>/dev/null

# Helper: check if path is inside project root
is_inside_project() {
    local path="$1"
    [ -n "$PROJECT_DIR" ] && [[ "$path" == "$PROJECT_DIR"* ]]
}

# Helper: minimize path for logging (strip home, use relative)
minimize_path() {
    local path="$1"
    if [ -n "$PROJECT_DIR" ]; then
        path=$(echo "$path" | sed "s|^$PROJECT_DIR|{PROJECT}|")
    fi
    echo "$path" | sed "s|^$HOME_DIR|~|"
}

# Helper: extract absolute paths from a command string
extract_paths_from_command() {
    local cmd="$1"
    echo "$cmd" | grep -oE '(/[^ ]+|~[^ ]*)' | head -5
}

# Read JSON from stdin
INPUT=$(cat)

# Extract tool name, input, and error info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // empty')
TOOL_ERROR=$(echo "$INPUT" | jq -r '.tool_error // empty')
TOOL_RESULT=$(echo "$INPUT" | jq -r '.tool_result // empty')

# Skip if no tool name
[ -z "$TOOL_NAME" ] && exit 0

# === ERROR LOGGING (always, regardless of tool type) ===
if [ -n "$TOOL_ERROR" ] && [ "$TOOL_ERROR" != "null" ]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")
    ERROR_MSG=$(echo "$TOOL_ERROR" | cut -c1-500 | tr '\n' ' ')
    echo "${TIMESTAMP}|${TOOL_NAME}|ERROR|${ERROR_MSG}" >> "$ERROR_LOG"
fi

if echo "$TOOL_RESULT" | grep -qiE '(error|failed|exception|denied|refused|timeout)'; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")
    RESULT_SNIPPET=$(echo "$TOOL_RESULT" | head -c 300 | tr '\n' ' ')
    echo "${TIMESTAMP}|${TOOL_NAME}|RESULT_ERROR|${RESULT_SNIPPET}" >> "$ERROR_LOG"
fi

# === SKIP INTERNAL-ONLY TOOLS ===
case "$TOOL_NAME" in
    TodoWrite|AskUserQuestion|EnterPlanMode|ExitPlanMode|TaskOutput)
        # Internal tools - no external access, skip
        exit 0
        ;;
esac

# === DETERMINE TARGET AND WHETHER TO LOG ===
TARGET=""
SHOULD_LOG=false

case "$TOOL_NAME" in
    # File operations - log if outside project
    Read|Write|Edit|NotebookEdit)
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.file_path // .notebook_path // empty')
        if [ -n "$TARGET" ] && ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET=$(minimize_path "$TARGET")
        fi
        ;;

    # Search operations - log if outside project
    Glob)
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.path // "."')
        PATTERN=$(echo "$TOOL_INPUT" | jq -r '.pattern // empty')
        if [ -n "$TARGET" ] && ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET")/$PATTERN"
        fi
        ;;

    Grep)
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.path // "."')
        PATTERN=$(echo "$TOOL_INPUT" | jq -r '.pattern // empty')
        if [ -n "$TARGET" ] && ! is_inside_project "$TARGET"; then
            SHOULD_LOG=true
            TARGET="$(minimize_path "$TARGET") pattern:${PATTERN:0:50}"
        fi
        ;;

    # Bash - log ALL except project-only paths
    Bash)
        CMD=$(echo "$TOOL_INPUT" | jq -r '.command // empty' | cut -c1-300)
        PATHS=$(extract_paths_from_command "$CMD")

        if [ -z "$PATHS" ]; then
            # No paths = system command → always log
            SHOULD_LOG=true
        else
            # Check if any path is outside project
            for P in $PATHS; do
                EXPANDED_P="${P/#\~/$HOME_DIR}"
                if [ -n "$EXPANDED_P" ] && ! is_inside_project "$EXPANDED_P"; then
                    SHOULD_LOG=true
                    break
                fi
            done
        fi

        if $SHOULD_LOG; then
            TARGET=$(minimize_path "$CMD")
        fi
        ;;

    # External resources - always log
    Task)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.description // empty')
        ;;

    WebFetch)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.url // empty' | cut -c1-100)
        ;;

    WebSearch)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.query // empty' | cut -c1-100)
        ;;

    Skill)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.skill // empty')
        ;;

    KillShell)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -r '.shell_id // empty')
        ;;

    # MCP tools - always log (external server access)
    mcp__*)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -c '.' | cut -c1-150)
        ;;

    # Unknown tools - log them (better safe than sorry)
    *)
        SHOULD_LOG=true
        TARGET=$(echo "$TOOL_INPUT" | jq -c '.' | cut -c1-100)
        ;;
esac

# Skip if shouldn't log
if ! $SHOULD_LOG; then
    exit 0
fi

# Skip if no target extracted
[ -z "$TARGET" ] && exit 0

# Append to audit log
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%S")
echo "${TIMESTAMP}|${TOOL_NAME}|${TARGET}" >> "$AUDIT_LOG"

exit 0
